/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * MMVimView
 *
 * A view class with a tabline, scrollbars, and a text view.  The tabline may
 * appear at the top of the view in which case it fills up the view from left
 * to right edge.  Any number of scrollbars may appear adjacent to all other
 * edges of the view (there may be more than one scrollbar per edge and
 * scrollbars may also be placed on the left edge of the view).  The rest of
 * the view is filled by the text view.
 */

#import "Miscellaneous.h"
#import "MMCoreTextView.h"
#import "MMTextView.h"
#import "MMVimController.h"
#import "MMVimView.h"
#import "MMWindowController.h"
#import "MMTabline.h"



// Scroller type; these must match SBAR_* in gui.h
enum {
    MMScrollerTypeLeft = 0,
    MMScrollerTypeRight,
    MMScrollerTypeBottom
};


// TODO:  Move!
@interface MMScroller : NSScroller {
    int32_t identifier;
    int type;
    NSRange range;
}
- (id)initWithIdentifier:(int32_t)ident type:(int)type;
- (int32_t)scrollerId;
- (int)type;
- (NSRange)range;
- (void)setRange:(NSRange)newRange;
@end


@interface MMVimView (Private) <MMTablineDelegate>
- (BOOL)bottomScrollbarVisible;
- (BOOL)leftScrollbarVisible;
- (BOOL)rightScrollbarVisible;
- (void)placeScrollbars;
- (MMScroller *)scrollbarForIdentifier:(int32_t)ident index:(unsigned *)idx;
- (NSSize)vimViewSizeForTextViewSize:(NSSize)textViewSize;
- (NSRect)textViewRectForVimViewSize:(NSSize)contentSize;
- (void)frameSizeMayHaveChanged:(BOOL)keepGUISize;
@end


// This is an informal protocol implemented by MMWindowController (maybe it
// shold be a formal protocol, but ...).
@interface NSWindowController (MMVimViewDelegate)
- (void)liveResizeWillStart;
- (void)liveResizeDidEnd;
@end



@implementation MMVimView

- (MMVimView *)initWithFrame:(NSRect)frame
               vimController:(MMVimController *)controller
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    vimController = controller;
    scrollbars = [[NSMutableArray alloc] init];

    // Only the tabline is autoresized, all other subview placement is done in
    // frameSizeMayHaveChanged.
    [self setAutoresizesSubviews:YES];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger renderer = [ud integerForKey:MMRendererKey];
    ASLogInfo(@"Use renderer=%ld", renderer);

    if (MMRendererCoreText == renderer) {
        // HACK! 'textView' has type MMTextView, but MMCoreTextView is not
        // derived from MMTextView.
        textView = (MMTextView *)[[MMCoreTextView alloc] initWithFrame:frame];
    } else {
        // Use Cocoa text system for text rendering.
        textView = [[MMTextView alloc] initWithFrame:frame];
    }

    // Allow control of text view inset via MMTextInset* user defaults.
    [textView setTextContainerInset:NSMakeSize(
        [ud integerForKey:MMTextInsetLeftKey],
        [ud integerForKey:MMTextInsetTopKey])];

    [textView setAutoresizingMask:NSViewNotSizable];
    [self addSubview:textView];
    
    // Create the tabline which is responsible for drawing the tabline and tabs.
    NSRect tablineFrame = {{0, frame.size.height - MMTablineHeight}, {frame.size.width, MMTablineHeight}};
    tabline = [[MMTabline alloc] initWithFrame:tablineFrame];
    tabline.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    tabline.delegate = self;
    tabline.hidden = YES;
    tabline.showsAddTabButton = [ud boolForKey:MMShowAddTabButtonKey];
    tabline.showsTabScrollButtons = [ud boolForKey:MMShowTabScrollButtonsKey];
    tabline.optimumTabWidth = [ud integerForKey:MMTabOptimumWidthKey];
    tabline.minimumTabWidth = [ud integerForKey:MMTabMinWidthKey];
    tabline.addTabButton.target = self;
    tabline.addTabButton.action = @selector(addNewTab:);
    [tabline registerForDraggedTypes:@[getPasteboardFilenamesType()]];
    [self addSubview:tabline];
    
    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [tabline release];
    [scrollbars release];  scrollbars = nil;

    // HACK! The text storage is the principal owner of the text system, but we
    // keep only a reference to the text view, so release the text storage
    // first (unless we are using the CoreText renderer).
    if ([textView isKindOfClass:[MMTextView class]])
        [[textView textStorage] release];

    [textView release];  textView = nil;

    [super dealloc];
}

- (BOOL)isOpaque
{
    return textView.defaultBackgroundColor.alphaComponent == 1;
}

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
// The core logic should not be reachable in 10.7 or above and is deprecated code.
// See documentation for showsResizeIndicator and placeScrollbars: comments.
// As such, just ifdef out the whole thing as we no longer support 10.7.
- (void)drawRect:(NSRect)rect
{
    // On Leopard, we want to have a textured window background for nice
    // looking tabs. However, the textured window background looks really
    // weird behind the window resize throbber, so emulate the look of an
    // NSScrollView in the bottom right corner.
    if (![[self window] showsResizeIndicator]
            || !([[self window] styleMask] & NSWindowStyleMaskTexturedBackground))
        return;
    
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
    int sw = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
#else
    int sw = [NSScroller scrollerWidth];
#endif

    // add .5 to the pixel locations to put the lines on a pixel boundary.
    // the top and right edges of the rect will be outside of the bounds rect
    // and clipped away.
    NSRect sizerRect = NSMakeRect([self bounds].size.width - sw + .5, -.5,
            sw, sw);
    //NSBezierPath* path = [NSBezierPath bezierPath];
    NSBezierPath* path = [NSBezierPath bezierPathWithRect:sizerRect];

    // On Tiger, we have color #E8E8E8 behind the resize throbber
    // (which is windowBackgroundColor on untextured windows or controlColor in
    // general). Terminal.app on Leopard has #FFFFFF background and #D9D9D9 as
    // stroke. The colors below are #FFFFFF and #D4D4D4, which is close enough
    // for me.
    [[NSColor controlBackgroundColor] set];
    [path fill];

    [[NSColor secondarySelectedControlColor] set];
    [path stroke];

    if ([self leftScrollbarVisible]) {
        // If the left scrollbar is visible there is an empty square under it.
        // Fill it in just like on the right hand corner.  The half pixel
        // offset ensures the outline goes on the top and right side of the
        // square; the left and bottom parts of the outline are clipped.
        sizerRect = NSMakeRect(-.5,-.5,sw,sw);
        path = [NSBezierPath bezierPathWithRect:sizerRect];
        [[NSColor controlBackgroundColor] set];
        [path fill];
        [[NSColor secondarySelectedControlColor] set];
        [path stroke];
    }
}
#endif

- (MMTextView *)textView
{
    return textView;
}

- (MMTabline *)tabline
{
    return tabline;
}

- (void)cleanup
{
    vimController = nil;
    
    [[self window] setDelegate:nil];

    [tabline removeFromSuperviewWithoutNeedingDisplay];
    [textView removeFromSuperviewWithoutNeedingDisplay];

    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *sb = [scrollbars objectAtIndex:i];
        [sb removeFromSuperviewWithoutNeedingDisplay];
    }
}

- (NSSize)desiredSize
{
    return [self vimViewSizeForTextViewSize:[textView desiredSize]];
}

- (NSSize)minSize
{
    return [self vimViewSizeForTextViewSize:[textView minSize]];
}

- (NSSize)constrainRows:(int *)r columns:(int *)c toSize:(NSSize)size
{
    NSSize textViewSize = [self textViewRectForVimViewSize:size].size;
    textViewSize = [textView constrainRows:r columns:c toSize:textViewSize];
    return [self vimViewSizeForTextViewSize:textViewSize];
}

- (void)setDesiredRows:(int)r columns:(int)c
{
    [textView setMaxRows:r columns:c];
}

- (IBAction)addNewTab:(id)sender
{
    [vimController sendMessage:AddNewTabMsgID data:nil];
}

- (void)updateTabsWithData:(NSData *)data
{
    const void *p = [data bytes];
    const void *end = p + [data length];
    int tabIdx = 0;
    BOOL didCloseTab = NO;
    
    // Count how many tabs Vim has and compare to the number MacVim's tabline has.
    const void *q = [data bytes];
    int vimNumberOfTabs = 0;
    q += sizeof(int); // skip over current tab index
    while (q < end) {
        int infoCount = *((int*)q); q += sizeof(int);
        for (unsigned i = 0; i < infoCount; ++i) {
            int length = *((int*)q); q += sizeof(int);
            if (length <= 0) continue;
            q += length;
            if (i == MMTabLabel) ++vimNumberOfTabs;
        }
    }
    // Close the specific tab where the user clicked the close button.
    if (tabToClose && vimNumberOfTabs == tabline.numberOfTabs - 1) {
        [tabline closeTab:tabToClose force:YES layoutImmediately:NO];
        tabToClose = nil;
        didCloseTab = YES;
    }

    // HACK!  Current tab is first in the message.  This way it is not
    // necessary to guess which tab should be the selected one (this can be
    // problematic for instance when new tabs are created).
    int curtabIdx = *((int*)p);  p += sizeof(int);

    while (p < end) {
        MMTab *tv;

        //int wincount = *((int*)p);  p += sizeof(int);
        int infoCount = *((int*)p); p += sizeof(int);
        unsigned i;
        for (i = 0; i < infoCount; ++i) {
            int length = *((int*)p);  p += sizeof(int);
            if (length <= 0)
                continue;

            NSString *val = [[NSString alloc]
                    initWithBytes:(void*)p length:length
                         encoding:NSUTF8StringEncoding];
            p += length;

            switch (i) {
                case MMTabLabel:
                    // Set the label of the tab, adding a new tab when needed.
                    tv = tabline.numberOfTabs <= tabIdx
                         ? [self addNewTab]
                         : [tabline tabAtIndex:tabIdx];
                    tv.title = val;
                    ++tabIdx;
                    break;
                case MMTabToolTip:
                    if (tv) tv.toolTip = val;
                    break;
                default:
                    ASLogWarn(@"Unknown tab info for index: %d", i);
            }

            [val release];
        }
    }

    // Remove unused tabs from the tabline.
    long i, count = tabline.numberOfTabs;
    for (i = count-1; i >= tabIdx; --i) {
        MMTab *tv = [tabline tabAtIndex:i];
        [tabline closeTab:tv force:YES layoutImmediately:YES];
    }

    [self selectTabWithIndex:curtabIdx];
    // It would be better if we could scroll to the selected tab only if it
    // reflected user intent. Presumably, the user expects MacVim to scroll
    // to the selected tab if they: added a tab, clicked a partially hidden
    // tab, or navigated to a tab with a keyboard command. Since we don't
    // have this kind of information, we always scroll to selected unless
    // the window isn't key or we think the user is in the process of
    // closing a tab by clicking its close button. Doing it this way instead
    // of using a signal of explicit user intent is probably too aggressive.
    if (self.window.isKeyWindow && !tabToClose && !didCloseTab) {
        [tabline scrollTabToVisibleAtIndex:curtabIdx];
    }
}

- (void)selectTabWithIndex:(int)idx
{
    if (idx < 0 || idx >= tabline.numberOfTabs) {
        ASLogWarn(@"No tab with index %d exists.", idx);
        return;
    }
    // Do not try to select a tab if already selected.
    if (idx != tabline.selectedTabIndex) {
        [tabline selectTabAtIndex:idx];
        // We might need to change the scrollbars that are visible.
        self.pendingPlaceScrollbars = YES;
    }
}

- (MMTab *)addNewTab
{
    // NOTE!  A newly created tab is not by selected by default; Vim decides
    // which tab should be selected at all times.  However, the AppKit will
    // automatically select the first tab added to a tab view.
    NSUInteger index = [tabline addTabAtEnd];
    return [tabline tabAtIndex:index];
}

- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type
{
    MMScroller *scroller = [[MMScroller alloc] initWithIdentifier:ident
                                                             type:type];
    [scroller setTarget:self];
    [scroller setAction:@selector(scroll:)];

    [self addSubview:scroller];
    [scrollbars addObject:scroller];
    [scroller release];
    
    self.pendingPlaceScrollbars = YES;
}

- (BOOL)destroyScrollbarWithIdentifier:(int32_t)ident
{
    unsigned idx = 0;
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:&idx];
    if (!scroller) return NO;

    [scroller removeFromSuperview];
    [scrollbars removeObjectAtIndex:idx];
    
    self.pendingPlaceScrollbars = YES;

    // If a visible scroller was removed then the vim view must resize.  This
    // is handled by the window controller (the vim view never resizes itself).
    return ![scroller isHidden];
}

- (BOOL)showScrollbarWithIdentifier:(int32_t)ident state:(BOOL)visible
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    if (!scroller) return NO;

    BOOL wasVisible = ![scroller isHidden];
    [scroller setHidden:!visible];
    
    self.pendingPlaceScrollbars = YES;

    // If a scroller was hidden or shown then the vim view must resize.  This
    // is handled by the window controller (the vim view never resizes itself).
    return wasVisible != visible;
}

- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(int32_t)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    [scroller setDoubleValue:val];
    [scroller setKnobProportion:prop];
    [scroller setEnabled:prop != 1.f];
}


- (void)scroll:(id)sender
{
    NSMutableData *data = [NSMutableData data];
    int32_t ident = [(MMScroller*)sender scrollerId];
    unsigned hitPart = (unsigned)[sender hitPart];
    float value = [sender floatValue];

    [data appendBytes:&ident length:sizeof(int32_t)];
    [data appendBytes:&hitPart length:sizeof(unsigned)];
    [data appendBytes:&value length:sizeof(float)];

    [vimController sendMessage:ScrollbarEventMsgID data:data];
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    NSRange range = NSMakeRange(pos, len);
    if (!NSEqualRanges(range, [scroller range])) {
        [scroller setRange:range];
        // This could be sent because a text window was created or closed, so
        // we might need to update which scrollbars are visible.
    }
    self.pendingPlaceScrollbars = YES;
}

- (void)finishPlaceScrollbars
{
    if (self.pendingPlaceScrollbars) {
        self.pendingPlaceScrollbars = NO;
        [self placeScrollbars];
    }
}

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore
{
    [textView setDefaultColorsBackground:back foreground:fore];
    
    [tabline setTablineSelBackground:back foreground:fore];

    CALayer *backedLayer = [self layer];
    if (backedLayer) {
        // This only happens in 10.14+, where everything is layer-backed by
        // default. Since textView draws itself as a separate layer, we don't
        // want this layer to draw anything. This is especially important with
        // 'transparency' where there's alpha blending and we don't want this
        // layer to be in the way and double-blending things.
        [backedLayer setBackgroundColor:CGColorGetConstantColor(kCGColorClear)];
    }

    for (NSUInteger i = 0, count = [scrollbars count]; i < count; ++i) {
        MMScroller *sb = [scrollbars objectAtIndex:i];
        [sb setNeedsDisplay:YES];
    }
    [self setNeedsDisplay:YES];
}


// -- MMTablineDelegate ----------------------------------------------


- (BOOL)tabline:(MMTabline *)tabline shouldSelectTabAtIndex:(NSUInteger)index
{
    // Propagate the selection message to Vim.
    if (NSNotFound != index) {
        int i = (int)index;   // HACK! Never more than MAXINT tabs?!
        NSData *data = [NSData dataWithBytes:&i length:sizeof(int)];
        [vimController sendMessage:SelectTabMsgID data:data];
    }
    // Let Vim decide whether to select the tab or not.
    return NO;
}

- (BOOL)tabline:(MMTabline *)tabline shouldCloseTabAtIndex:(NSUInteger)index
{
    if (index >= 0 && index < tabline.numberOfTabs - 1) {
        tabToClose = [tabline tabAtIndex:index];
    }
    // HACK!  This method is only called when the user clicks the close button
    // on the tab.  Instead of letting the tab bar close the tab, we return NO
    // and pass a message on to Vim to let it handle the closing.
    int i = (int)index;   // HACK! Never more than MAXINT tabs?!
    NSData *data = [NSData dataWithBytes:&i length:sizeof(int)];
    [vimController sendMessage:CloseTabMsgID data:data];
    return NO;
}

- (void)tabline:(MMTabline *)tabline didDragTab:(MMTab *)tab toIndex:(NSUInteger)index
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&index length:sizeof(int)];
    [vimController sendMessage:DraggedTabMsgID data:data];
}

- (NSDragOperation)tabline:(MMTabline *)tabline draggingEntered:(id <NSDraggingInfo>)dragInfo forTabAtIndex:(NSUInteger)index
{
    return [dragInfo.draggingPasteboard.types containsObject:getPasteboardFilenamesType()]
            ? NSDragOperationCopy
            : NSDragOperationNone;
}

- (BOOL)tabline:(MMTabline *)tabline performDragOperation:(id <NSDraggingInfo>)dragInfo forTabAtIndex:(NSUInteger)index
{
    NSPasteboard *pb = dragInfo.draggingPasteboard;
    NSArray<NSString*>* filenames = extractPasteboardFilenames(pb);
    if (filenames == nil || filenames.count == 0)
        return NO;

    if (index != NSNotFound) {
        // If dropping on a specific tab, only open one file
        [vimController file:[filenames objectAtIndex:0] draggedToTabAtIndex:index];
    } else {
        // Files were dropped on empty part of tab bar; open them all
        [vimController filesDraggedToTabline:filenames];
    }
    return YES;
}


// -- NSView customization ---------------------------------------------------


- (void)viewWillStartLiveResize
{
    id windowController = [[self window] windowController];
    [windowController liveResizeWillStart];

    [super viewWillStartLiveResize];
}

- (void)viewDidEndLiveResize
{
    id windowController = [[self window] windowController];
    [windowController liveResizeDidEnd];

    [super viewDidEndLiveResize];
}

- (void)setFrameSize:(NSSize)size
{
    // NOTE: Instead of only acting when a frame was resized, we do some
    // updating each time a frame may be resized.  (At the moment, if we only
    // respond to actual frame changes then typing ":set lines=1000" twice in a
    // row will result in the vim view holding more rows than the can fit
    // inside the window.)
    [super setFrameSize:size];
    [self frameSizeMayHaveChanged:NO];
}

- (void)setFrameSizeKeepGUISize:(NSSize)size
{
    // NOTE: Instead of only acting when a frame was resized, we do some
    // updating each time a frame may be resized.  (At the moment, if we only
    // respond to actual frame changes then typing ":set lines=1000" twice in a
    // row will result in the vim view holding more rows than the can fit
    // inside the window.)
    [super setFrameSize:size];
    [self frameSizeMayHaveChanged:YES];
}

- (void)setFrame:(NSRect)frame
{
    // See comment in setFrameSize: above.
    [super setFrame:frame];
    [self frameSizeMayHaveChanged:NO];
}

- (void)viewDidChangeEffectiveAppearance
{
    [vimController appearanceChanged:getCurrentAppearance(self.effectiveAppearance)];
}
@end // MMVimView




@implementation MMVimView (Private)

- (BOOL)bottomScrollbarVisible
{
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeBottom && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (BOOL)leftScrollbarVisible
{
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeLeft && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (BOOL)rightScrollbarVisible
{
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeRight && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (void)placeScrollbars
{
    NSRect textViewFrame = [textView frame];
    BOOL leftSbVisible = NO;
    BOOL rightSbVisible = NO;
    BOOL botSbVisible = NO;

    // HACK!  Find the lowest left&right vertical scrollbars This hack
    // continues further down.
    NSUInteger lowestLeftSbIdx = (NSUInteger)-1;
    NSUInteger lowestRightSbIdx = (NSUInteger)-1;
    NSUInteger rowMaxLeft = 0, rowMaxRight = 0;
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if (![scroller isHidden]) {
            NSRange range = [scroller range];
            if ([scroller type] == MMScrollerTypeLeft
                    && range.location >= rowMaxLeft) {
                rowMaxLeft = range.location;
                lowestLeftSbIdx = i;
                leftSbVisible = YES;
            } else if ([scroller type] == MMScrollerTypeRight
                    && range.location >= rowMaxRight) {
                rowMaxRight = range.location;
                lowestRightSbIdx = i;
                rightSbVisible = YES;
            } else if ([scroller type] == MMScrollerTypeBottom) {
                botSbVisible = YES;
            }
        }
    }

    // Place the scrollbars.
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller isHidden])
            continue;

        NSRect rect;
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
        CGFloat scrollerWidth = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
#else
        CGFloat scrollerWidth = [NSScroller scrollerWidth];
#endif
        if ([scroller type] == MMScrollerTypeBottom) {
            rect = [textView rectForColumnsInRange:[scroller range]];
            rect.size.height = scrollerWidth;
            if (leftSbVisible)
                rect.origin.x += scrollerWidth;

            // HACK!  Make sure the horizontal scrollbar covers the text view
            // all the way to the right, otherwise it looks ugly when the user
            // drags the window to resize.
            float w = NSMaxX(textViewFrame) - NSMaxX(rect);
            if (w > 0)
                rect.size.width += w;

            // Make sure scrollbar rect is bounded by the text view frame.
            // Also leave some room for the resize indicator on the right in
            // case there is no right scrollbar.
            if (rect.origin.x < textViewFrame.origin.x)
                rect.origin.x = textViewFrame.origin.x;
            else if (rect.origin.x > NSMaxX(textViewFrame))
                rect.origin.x = NSMaxX(textViewFrame);
            if (NSMaxX(rect) > NSMaxX(textViewFrame))
                rect.size.width -= NSMaxX(rect) - NSMaxX(textViewFrame);
            if (!rightSbVisible)
                rect.size.width -= scrollerWidth;
            if (rect.size.width < 0)
                rect.size.width = 0;
        } else {
            rect = [textView rectForRowsInRange:[scroller range]];
            // Adjust for the fact that text layout is flipped.
            rect.origin.y = NSMaxY(textViewFrame) - rect.origin.y
                    - rect.size.height;
            rect.size.width = scrollerWidth;
            if ([scroller type] == MMScrollerTypeRight)
                rect.origin.x = NSMaxX(textViewFrame);

            // HACK!  Make sure the lowest vertical scrollbar covers the text
            // view all the way to the bottom.  This is done because Vim only
            // makes the scrollbar cover the (vim-)window it is associated with
            // and this means there is always an empty gap in the scrollbar
            // region next to the command line.
            // TODO!  Find a nicer way to do this.
            if (i == lowestLeftSbIdx || i == lowestRightSbIdx) {
                float h = rect.origin.y + rect.size.height
                          - textViewFrame.origin.y;
                if (rect.size.height < h) {
                    rect.origin.y = textViewFrame.origin.y;
                    rect.size.height = h;
                }
            }

            // Vertical scrollers must not cover the resize box in the
            // bottom-right corner of the window.
            if ([[self window] showsResizeIndicator]  // Note: This is deprecated as of 10.7, see below comment.
                && rect.origin.y < scrollerWidth) {
                rect.size.height -= scrollerWidth - rect.origin.y;
                rect.origin.y = scrollerWidth;
            }

            // Make sure scrollbar rect is bounded by the text view frame.
            if (rect.origin.y < textViewFrame.origin.y) {
                rect.size.height -= textViewFrame.origin.y - rect.origin.y;
                rect.origin.y = textViewFrame.origin.y;
            } else if (rect.origin.y > NSMaxY(textViewFrame))
                rect.origin.y = NSMaxY(textViewFrame);
            if (NSMaxY(rect) > NSMaxY(textViewFrame))
                rect.size.height -= NSMaxY(rect) - NSMaxY(textViewFrame);
            if (rect.size.height < 0)
                rect.size.height = 0;
        }

        NSRect oldRect = [scroller frame];
        if (!NSEqualRects(oldRect, rect)) {
            [scroller setFrame:rect];
            // Clear behind the old scroller frame, or parts of the old
            // scroller might still be visible after setFrame:.
            [[[self window] contentView] setNeedsDisplayInRect:oldRect];
            [scroller setNeedsDisplay:YES];
        }
    }

    if (NSAppKitVersionNumber < NSAppKitVersionNumber10_7) {
        // HACK: If there is no bottom or right scrollbar the resize indicator will
        // cover the bottom-right corner of the text view so tell NSWindow not to
        // draw it in this situation.
        //
        // Note: This API is ignored from 10.7 onward and is now deprecated. This
        // should be removed if we want to drop support for 10.6.
        [[self window] setShowsResizeIndicator:(rightSbVisible||botSbVisible)];
    }
}

- (MMScroller *)scrollbarForIdentifier:(int32_t)ident index:(unsigned *)idx
{
    for (NSUInteger i = 0, count = scrollbars.count; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller scrollerId] == ident) {
            if (idx) *idx = (unsigned)i;
            return scroller;
        }
    }

    return nil;
}

- (NSSize)vimViewSizeForTextViewSize:(NSSize)textViewSize
{
    NSSize size = textViewSize;
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
    CGFloat scrollerWidth = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
#else
    CGFloat scrollerWidth = [NSScroller scrollerWidth];
#endif

    if (!tabline.isHidden)
        size.height += NSHeight(tabline.frame);

    if ([self bottomScrollbarVisible])
        size.height += scrollerWidth;
    if ([self leftScrollbarVisible])
        size.width += scrollerWidth;
    if ([self rightScrollbarVisible])
        size.width += scrollerWidth;

    return size;
}

- (NSRect)textViewRectForVimViewSize:(NSSize)contentSize
{
    NSRect rect = { {0, 0}, {contentSize.width, contentSize.height} };
#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
    CGFloat scrollerWidth = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
#else
    CGFloat scrollerWidth = [NSScroller scrollerWidth];
#endif

    if (!tabline.isHidden)
        rect.size.height -= NSHeight(tabline.frame);

    if ([self bottomScrollbarVisible]) {
        rect.size.height -= scrollerWidth;
        rect.origin.y += scrollerWidth;
    }
    if ([self leftScrollbarVisible]) {
        rect.size.width -= scrollerWidth;
        rect.origin.x += scrollerWidth;
    }
    if ([self rightScrollbarVisible])
        rect.size.width -= scrollerWidth;

    return rect;
}

- (void)frameSizeMayHaveChanged:(BOOL)keepGUISize
{
    // NOTE: Whenever a call is made that may have changed the frame size we
    // take the opportunity to make sure all subviews are in place and that the
    // (rows,columns) are constrained to lie inside the new frame.  We not only
    // do this when the frame really has changed since it is possible to modify
    // the number of (rows,columns) without changing the frame size.

    // Give all superfluous space to the text view. It might be smaller or
    // larger than it wants to be, but this is needed during live resizing.
    NSRect textViewRect = [self textViewRectForVimViewSize:[self frame].size];
    [textView setFrame:textViewRect];

    // Immediately place the scrollbars instead of deferring till later here.
    // Deferral ended up causing some bugs, in particular when in <10.14
    // CoreText renderer where [NSAnimationContext beginGrouping] is used to
    // bundle state changes together and the deferred placeScrollbars would get
    // the wrong data to use. An alternative would be to check for that and only
    // call finishPlaceScrollbars once we call [NSAnimationContext endGrouping]
    // but that makes the code mode complicated. Just do it here and the
    // performance is fine as this gets called occasionally only
    // (pendingPlaceScrollbars is mostly for the case if we are adding a lot of
    // scrollbars at once we want to only call placeScrollbars once instead of
    // doing it N times).
    self.pendingPlaceScrollbars = NO;
    [self placeScrollbars];

    // It is possible that the current number of (rows,columns) is too big or
    // too small to fit the new frame.  If so, notify Vim that the text
    // dimensions should change, but don't actually change the number of
    // (rows,columns).  These numbers may only change when Vim initiates the
    // change (as opposed to the user dragging the window resizer, for
    // example).
    //
    // Note that the message sent to Vim depends on whether we're in
    // a live resize or not -- this is necessary to avoid the window jittering
    // when the user drags to resize.
    int constrained[2];
    NSSize textViewSize = [textView frame].size;
    [textView constrainRows:&constrained[0] columns:&constrained[1]
                     toSize:textViewSize];

    int rows, cols;
    [textView getMaxRows:&rows columns:&cols];

    if (constrained[0] != rows || constrained[1] != cols) {
        NSData *data = [NSData dataWithBytes:constrained length:2*sizeof(int)];
        int msgid = [self inLiveResize] ? LiveResizeMsgID
                                        : (keepGUISize ? SetTextDimensionsNoResizeWindowMsgID : SetTextDimensionsMsgID);

        ASLogDebug(@"Notify Vim that text dimensions changed from %dx%d to "
                   "%dx%d (%s)", cols, rows, constrained[1], constrained[0],
                   MMVimMsgIDStrings[msgid]);

        if (msgid != LiveResizeMsgID || !self.pendingLiveResize) {
            // Live resize messages can be sent really rapidly, especailly if
            // it's from double clicking the window border (to indicate filling
            // all the way to that side to the window manager). We want to rate
            // limit sending live resize one at a time, or the IPC will get
            // swamped which causes slowdowns and some messages will also be dropped.
            // As a result we basically discard all live resize messages if one
            // is already going on. liveResizeDidEnd: will perform a final clean
            // up resizing.
            self.pendingLiveResize = (msgid == LiveResizeMsgID);

            [vimController sendMessageNow:msgid data:data timeout:1];
        }

        // We only want to set the window title if this resize came from
        // a live-resize, not (for example) setting 'columns' or 'lines'.
        if ([self inLiveResize]) {
            [[self window] setTitle:[NSString stringWithFormat:@"%d × %d",
                    constrained[1], constrained[0]]];
        }
    }
}

@end // MMVimView (Private)




@implementation MMScroller

- (id)initWithIdentifier:(int32_t)ident type:(int)theType
{
    // HACK! NSScroller creates a horizontal scroller if it is init'ed with a
    // frame whose with exceeds its height; so create a bogus rect and pass it
    // to initWithFrame.
    NSRect frame = theType == MMScrollerTypeBottom
            ? NSMakeRect(0, 0, 1, 0)
            : NSMakeRect(0, 0, 0, 1);

    self = [super initWithFrame:frame];
    if (!self) return nil;

    identifier = ident;
    type = theType;
    [self setHidden:YES];
    [self setEnabled:YES];
    [self setAutoresizingMask:NSViewNotSizable];

    return self;
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag
{
    // Dark mode scrollbars draw a translucent knob slot overlaid on top of
    // whatever background the view has, even when we are using legacy
    // scrollbars with a dedicated space.  This means we need to draw the
    // background with some colors first, or else it would look really black, or
    // show through rendering artifacts (e.g. if guioption 'k' is on, and you
    // turn off the bar bar, the artiacts will show through in the overlay).
    //
    // Note: Another way to fix this is to make sure to draw the underlying
    // MMVimView or the window with the proper color so the scrollbar would just
    // draw on top, but this doesn't work properly right now, and it's difficult
    // to get that to work with the 'transparency' setting as well.
    MMVimView *vimView = [self target];
    NSColor *defaultBackgroundColor = [[vimView textView] defaultBackgroundColor];
    [defaultBackgroundColor setFill];
    NSRectFill(slotRect);

    [super drawKnobSlotInRect:slotRect highlight:flag];
}

- (int32_t)scrollerId
{
    return identifier;
}

- (int)type
{
    return type;
}

- (NSRange)range
{
    return range;
}

- (void)setRange:(NSRange)newRange
{
    range = newRange;
}

- (void)scrollWheel:(NSEvent *)event
{
    // HACK! Pass message on to the text view.
    NSView *vimView = [self superview];
    if ([vimView isKindOfClass:[MMVimView class]])
        [[(MMVimView*)vimView textView] scrollWheel:event];
}

- (void)mouseDown:(NSEvent *)event
{
    // TODO: This is an ugly way of getting the connection to the backend.
    NSConnection *connection = nil;
    id wc = [[self window] windowController];
    if ([wc isKindOfClass:[MMWindowController class]]) {
        MMVimController *vc = [(MMWindowController*)wc vimController];
        id proxy = [vc backendProxy];
        connection = [(NSDistantObject*)proxy connectionForProxy];
    }

    // NOTE: The scroller goes into "event tracking mode" when the user clicks
    // (and holds) the mouse button.  We have to manually add the backend
    // connection to this mode while the mouse button is held, else DO messages
    // from Vim will not be processed until the mouse button is released.
    [connection addRequestMode:NSEventTrackingRunLoopMode];
    [super mouseDown:event];
    [connection removeRequestMode:NSEventTrackingRunLoopMode];
}

@end // MMScroller

/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MacVim.h"



@class MMWindow;
@class MMFullScreenWindow;
@class MMVimController;
@class MMVimView;

@interface MMWindowController : NSWindowController<
    NSWindowDelegate
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
    , NSMenuItemValidation
#endif
    >
{
    MMVimController     *vimController;
    MMVimView           *vimView;
    BOOL                setupDone;
    BOOL                windowPresented;
    BOOL                shouldResizeVimView;
    BOOL                shouldKeepGUISize;
    BOOL                shouldRestoreUserTopLeft;
    BOOL                shouldMaximizeWindow;
    int                 updateToolbarFlag;
    BOOL                keepOnScreen;
    NSString            *windowAutosaveKey;
    BOOL                fullScreenEnabled; ///< Whether full screen is on (native or not)
    MMFullScreenWindow  *fullScreenWindow; ///< The window used for non-native full screen. Will only be non-nil when in non-native full screen.
    int                 fullScreenOptions;
    BOOL                delayEnterFullScreen;
    NSRect              preFullScreenFrame;
    MMWindow            *decoratedWindow;
    NSString            *lastSetTitle;
    int                 userRows;
    int                 userCols;
    NSPoint             userTopLeft;
    NSPoint             defaultTopLeft;
    NSSize              desiredWindowSize;
    NSToolbar           *toolbar;
    BOOL                resizingDueToMove;
    int                 blurRadius;
    BOOL                backgroundDark;
    NSMutableArray      *afterWindowPresentedQueue;
}

- (id)initWithVimController:(MMVimController *)controller;
- (MMVimController *)vimController;
- (MMVimView *)vimView;
- (NSString *)windowAutosaveKey;
- (void)setWindowAutosaveKey:(NSString *)key;
- (void)cleanup;
- (void)openWindow;
- (BOOL)presentWindow:(id)unused;
- (void)moveWindowAcrossScreens:(NSPoint)origin;
- (void)updateTabsWithData:(NSData *)data;
- (void)selectTabWithIndex:(int)idx;
- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols isLive:(BOOL)live
                      keepGUISize:(BOOL)keepGUISize
                     keepOnScreen:(BOOL)onScreen;
- (void)resizeView;
- (void)zoomWithRows:(int)rows columns:(int)cols state:(int)state;
- (void)setTitle:(NSString *)title;
- (void)setDocumentFilename:(NSString *)filename;
- (void)setToolbar:(NSToolbar *)toolbar;
- (void)createScrollbarWithIdentifier:(int32_t)ident type:(int)type;
- (BOOL)destroyScrollbarWithIdentifier:(int32_t)ident;
- (BOOL)showScrollbarWithIdentifier:(int32_t)ident state:(BOOL)visible;
- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(int32_t)ident;
- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(int32_t)ident;

- (void)setBackgroundOption:(int)dark;
- (void)refreshApperanceMode;
- (void)updateResizeConstraints:(BOOL)resizeWindow;

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore;
- (void)setFont:(NSFont *)font;
- (void)setWideFont:(NSFont *)font;
- (void)refreshFonts;
- (void)processInputQueueDidFinish;
- (void)showTabline:(BOOL)on;
- (void)showToolbar:(BOOL)on size:(int)size mode:(int)mode;
- (void)setMouseShape:(int)shape;
- (void)adjustLinespace:(int)linespace;
- (void)adjustColumnspace:(int)columnspace;
- (void)liveResizeWillStart;
- (void)liveResizeDidEnd;

- (void)setBlurRadius:(int)radius;

- (void)enterFullScreen:(int)fuoptions backgroundColor:(NSColor *)back;
- (void)leaveFullScreen;
- (void)setFullScreenBackgroundColor:(NSColor *)back;
- (void)invFullScreen:(id)sender;

- (void)setBufferModified:(BOOL)mod;
- (void)setTopLeft:(NSPoint)pt;
- (BOOL)getDefaultTopLeft:(NSPoint*)pt;
- (void)runAfterWindowPresentedUsingBlock:(void (^)(void))block;

//
// NSMenuItemValidation
//
- (BOOL)validateMenuItem:(NSMenuItem *)item;

// Menu items / macactions
- (IBAction)addNewTab:(id)sender;
- (IBAction)toggleToolbar:(id)sender;
- (IBAction)performClose:(id)sender;
- (IBAction)findNext:(id)sender;
- (IBAction)findPrevious:(id)sender;
- (IBAction)useSelectionForFind:(id)sender;
- (IBAction)vimMenuItemAction:(id)sender;
- (IBAction)vimToolbarItemAction:(id)sender;
- (IBAction)fontSizeUp:(id)sender;
- (IBAction)fontSizeDown:(id)sender;
- (IBAction)findAndReplace:(id)sender;
- (IBAction)zoom:(id)sender;
- (IBAction)zoomLeft:(id)sender;
- (IBAction)zoomRight:(id)sender;
- (IBAction)joinAllStageManagerSets:(id)sender;
- (IBAction)unjoinAllStageManagerSets:(id)sender;

@end

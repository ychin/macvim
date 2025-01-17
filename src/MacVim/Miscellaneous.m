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
#import "Miscellaneous.h"



// NSUserDefaults keys
NSString *MMTabMinWidthKey                = @"MMTabMinWidth";
NSString *MMTabMaxWidthKey                = @"MMTabMaxWidth";
NSString *MMTabOptimumWidthKey            = @"MMTabOptimumWidth";
NSString *MMShowAddTabButtonKey           = @"MMShowAddTabButton";
NSString *MMTextInsetLeftKey              = @"MMTextInsetLeft";
NSString *MMTextInsetRightKey             = @"MMTextInsetRight";
NSString *MMTextInsetTopKey               = @"MMTextInsetTop";
NSString *MMTextInsetBottomKey            = @"MMTextInsetBottom";
NSString *MMTypesetterKey                 = @"MMTypesetter";
NSString *MMCellWidthMultiplierKey        = @"MMCellWidthMultiplier";
NSString *MMBaselineOffsetKey             = @"MMBaselineOffset";
NSString *MMTranslateCtrlClickKey         = @"MMTranslateCtrlClick";
NSString *MMTopLeftPointKey               = @"MMTopLeftPoint";
NSString *MMOpenInCurrentWindowKey        = @"MMOpenInCurrentWindow";
NSString *MMNoFontSubstitutionKey         = @"MMNoFontSubstitution";
NSString *MMFontPreserveLineSpacingKey    = @"MMFontPreserveLineSpacing";
NSString *MMAppearanceModeSelectionKey    = @"MMAppearanceModeSelection";
NSString *MMNoTitleBarWindowKey           = @"MMNoTitleBarWindow";
NSString *MMTitlebarAppearsTransparentKey = @"MMTitlebarAppearsTransparent";
NSString *MMTitlebarShowsDocumentIconKey  = @"MMTitlebarShowsDocumentIcon";
NSString *MMNoWindowShadowKey             = @"MMNoWindowShadow";
NSString *MMDisableLaunchAnimationKey     = @"MMDisableLaunchAnimation";
NSString *MMLoginShellKey                 = @"MMLoginShell";
NSString *MMUntitledWindowKey             = @"MMUntitledWindow";
NSString *MMZoomBothKey                   = @"MMZoomBoth";
NSString *MMCurrentPreferencePaneKey      = @"MMCurrentPreferencePane";
NSString *MMLoginShellCommandKey          = @"MMLoginShellCommand";
NSString *MMLoginShellArgumentKey         = @"MMLoginShellArgument";
NSString *MMDialogsTrackPwdKey            = @"MMDialogsTrackPwd";
NSString *MMOpenLayoutKey                 = @"MMOpenLayout";
NSString *MMVerticalSplitKey              = @"MMVerticalSplit";
NSString *MMPreloadCacheSizeKey           = @"MMPreloadCacheSize";
NSString *MMLastWindowClosedBehaviorKey   = @"MMLastWindowClosedBehavior";
#ifdef INCLUDE_OLD_IM_CODE
NSString *MMUseInlineImKey                = @"MMUseInlineIm";
#endif // INCLUDE_OLD_IM_CODE
NSString *MMSuppressTerminationAlertKey   = @"MMSuppressTerminationAlert";
NSString *MMNativeFullScreenKey           = @"MMNativeFullScreen";
NSString *MMUseMouseTimeKey               = @"MMUseMouseTime";
NSString *MMFullScreenFadeTimeKey         = @"MMFullScreenFadeTime";
NSString *MMNonNativeFullScreenShowMenuKey          = @"MMNonNativeFullScreenShowMenu";
NSString *MMNonNativeFullScreenSafeAreaBehaviorKey  = @"MMNonNativeFullScreenSafeAreaBehavior";
NSString *MMSmoothResizeKey               = @"MMSmoothResize";
NSString *MMCmdLineAlignBottomKey         = @"MMCmdLineAlignBottom";
NSString *MMRendererClipToRowKey          = @"MMRendererClipToRow";
NSString *MMAllowForceClickLookUpKey      = @"MMAllowForceClickLookUp";
NSString *MMUpdaterPrereleaseChannelKey   = @"MMUpdaterPrereleaseChannel";
NSString *MMLastUsedBundleVersionKey      = @"MMLastUsedBundleVersion";
NSString *MMShowWhatsNewOnStartupKey      = @"MMShowWhatsNewOnStartup";
NSString *MMScrollOneDirectionOnlyKey     = @"MMScrollOneDirectionOnly";


@implementation NSIndexSet (MMExtras)

+ (id)indexSetWithVimList:(NSString *)list
{
    NSMutableIndexSet *idxSet = [NSMutableIndexSet indexSet];
    NSArray *array = [list componentsSeparatedByString:@"\n"];
    NSUInteger i, count = [array count];

    for (i = 0; i < count; ++i) {
        NSString *entry = [array objectAtIndex:i];
        if ([entry intValue] > 0)
            [idxSet addIndex:i];
    }

    return idxSet;
}

@end // NSIndexSet (MMExtras)




@implementation NSDocumentController (MMExtras)

- (void)noteNewRecentFilePath:(NSString *)path
{
    NSURL *url = [NSURL fileURLWithPath:path];
    if (url)
        [self noteNewRecentDocumentURL:url];
}

- (void)noteNewRecentFilePaths:(NSArray *)paths
{
    NSEnumerator *e = [paths objectEnumerator];
    NSString *path;
    while ((path = [e nextObject]))
        [self noteNewRecentFilePath:path];
}

@end // NSDocumentController (MMExtras)




@implementation NSSavePanel (MMExtras)

- (void)hiddenFilesButtonToggled:(id)sender
{
    [self setShowsHiddenFiles:[sender intValue]];
}

@end // NSSavePanel (MMExtras)




@implementation NSMenu (MMExtras)

- (int)indexOfItemWithAction:(SEL)action
{
    NSUInteger i, count = [self numberOfItems];
    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [self itemAtIndex:i];
        if ([item action] == action)
            return (int)i;
    }

    return -1;
}

- (NSMenuItem *)itemWithAction:(SEL)action
{
    int idx = [self indexOfItemWithAction:action];
    return idx >= 0 ? [self itemAtIndex:idx] : nil;
}

- (NSMenu *)findMenuContainingItemWithAction:(SEL)action
{
    // NOTE: We only look for the action in the submenus of 'self'
    NSUInteger i, count = [self numberOfItems];
    for (i = 0; i < count; ++i) {
        NSMenu *menu = [[self itemAtIndex:i] submenu];
        NSMenuItem *item = [menu itemWithAction:action];
        if (item) return menu;
    }

    return nil;
}

- (NSMenu *)findWindowsMenu
{
    return [self findMenuContainingItemWithAction:
        @selector(performMiniaturize:)];
}

- (NSMenu *)findApplicationMenu
{
    // TODO: Just return [self itemAtIndex:0]?
    return [self findMenuContainingItemWithAction:@selector(terminate:)];
}

- (NSMenu *)findServicesMenu
{
    // NOTE!  Our heuristic for finding the "Services" menu is to look for the
    // second item before the "Hide MacVim" menu item on the "MacVim" menu.
    // (The item before "Hide MacVim" should be a separator, but this is not
    // important as long as the item before that is the "Services" menu.)

    NSMenu *appMenu = [self findApplicationMenu];
    if (!appMenu) return nil;

    int idx = [appMenu indexOfItemWithAction: @selector(hide:)];
    if (idx-2 < 0) return nil;  // idx == -1, if selector not found

    return [[appMenu itemAtIndex:idx-2] submenu];
}

- (NSMenu *)findFileMenu
{
    return [self findMenuContainingItemWithAction:@selector(performClose:)];
}

- (NSMenu *)findHelpMenu
{
    return [self findMenuContainingItemWithAction:@selector(openWebsite:)];
}

@end // NSMenu (MMExtras)




@implementation NSToolbar (MMExtras)

- (NSUInteger)indexOfItemWithItemIdentifier:(NSString *)identifier
{
    NSArray *items = [self items];
    NSUInteger i, count = [items count];
    for (i = 0; i < count; ++i) {
        id item = [items objectAtIndex:i];
        if ([[item itemIdentifier] isEqual:identifier])
            return i;
    }

    return NSNotFound;
}

- (NSToolbarItem *)itemAtIndex:(NSUInteger)idx
{
    NSArray *items = [self items];
    if (idx >= [items count])
        return nil;

    return [items objectAtIndex:idx];
}

- (NSToolbarItem *)itemWithItemIdentifier:(NSString *)identifier
{
    NSUInteger idx = [self indexOfItemWithItemIdentifier:identifier];
    return idx != NSNotFound ? [self itemAtIndex:idx] : nil;
}

@end // NSToolbar (MMExtras)




@implementation NSTabView (MMExtras)

- (void)removeAllTabViewItems
{
    NSArray *existingItems = [self tabViewItems];
    NSEnumerator *e = [existingItems objectEnumerator];
    NSTabViewItem *item;
    while ((item = [e nextObject])) {
        [self removeTabViewItem:item];
    }
}

@end // NSTabView (MMExtras)




@implementation NSNumber (MMExtras)

// HACK to allow font size to be changed via menu (bound to Cmd+/Cmd-)
- (NSInteger)tag
{
    return [self intValue];
}

@end // NSNumber (MMExtras)

#import <objc/runtime.h>
@implementation NSObject (MMDebug)

static NSString* ivarToString(id obj, const char *ivarType, void* ivarAddress, id ivarObject)
{
    // Documentation: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
    if (ivarType[0] == '^') {
        // Pointer type
        void *pointerDeref = *(void **)ivarObject;
        void *ivarAddressDeref = *((void**)ivarAddress);
        return [NSString stringWithFormat:@"*%@", ivarToString(obj, ivarType + 1, ivarAddressDeref, (id)(pointerDeref))];
    }
    else if (ivarType[0] == '{')
    {
        // Struct
        // If we know this specific struct and have specialized string output utilities, use that.
#define STRUCT_TO_STRING(NAME, METHOD) \
        if (strncmp(ivarType+1, #NAME, strlen(#NAME)) == 0) { \
            return METHOD(*(NAME*)ivarAddress); \
        }
        STRUCT_TO_STRING(CGSize, NSStringFromSize);
        STRUCT_TO_STRING(CGPoint, NSStringFromPoint);
        STRUCT_TO_STRING(CGRect, NSStringFromRect);
        STRUCT_TO_STRING(NSRange, NSStringFromRange);
#undef STRUCT_TO_STRING

        // Commented out WIP code for generic cases where we don't really have a way to calculate the struct's alignment and size easily.
        // In fact, the type encoding does not expose enough information to do this properly. An easy example would be to write a struct
        // of bitfields using int vs char. The size/alignment of the structs would be different but the type encoding would be the same,
        // showing something like {b1b2b4} which do not tell you if in the source it was using char or int's.
#if 0
        char *eq = strchr(ivarType, '=');
        if (eq != NULL) {
            NSString *structName = [[[NSString alloc] initWithBytes:ivarType+1 length:eq-ivarType-1 encoding:NSUTF8StringEncoding] autorelease];
            NSMutableString *structDesc = [NSMutableString stringWithFormat:@"%@: {", structName];
            char *dataStart = eq + 1;
            char *data = dataStart;
            size_t offset = 0;
            NSString *fieldName = nil;
            while (data != NULL && *data != '}') {
                if (*data == '"') {
                    data = strchr(data + 1, '"');
                    if (data != NULL) {
                        fieldName = [[[NSString alloc] initWithBytes:dataStart+1 length:data-dataStart-1 encoding:NSUTF8StringEncoding] autorelease];
                        data += 1;
                    } else {
                        // This is a failure state.
                        return [NSString stringWithFormat:@"%s", ivarType];
                    }
                }
                void *obj = *(void**)(ivarAddress + offset);
                size_t objOffset = 0;
                NSString *fieldDesc = ivarToString(obj, data, ivarAddress+offset, (id)obj, &objOffset);
                offset += objOffset;
                if (fieldName != nil) {
                    [structDesc appendFormat:@"%@=%@ ", fieldName, fieldDesc];
                } else {
                    [structDesc appendFormat:@"%@ ", fieldDesc];
                }

                if (*data == 'b') {
                    // We could let recursion calculate this for us but for now it's simpler to just do it here.
                    do {
                        data++;
                    } while (isdigit(*data));
                } else {
                    data += 1;
                }
            }
            [structDesc appendString:@"}"];
            return structDesc;
        }
#endif
    }

    // Default signed data types
    if(ivarType[0] == 'c')
    {
        char character = (char)(intptr_t)ivarObject;
        return [NSString stringWithFormat:@"'%c'", character];
    }
    else if(ivarType[0] == 'i' || ivarType[0] == 'l') // l is also 32 bit in the 64 bit runtime environment
    {
        int integer = (int)(intptr_t)ivarObject;
        return [NSString stringWithFormat:@"%i", integer];
    }
    else if(ivarType[0] == 's')
    {
        short shortVal = (short)(intptr_t)ivarObject;
        return [NSString stringWithFormat:@"%i", (int)shortVal];
    }
    else if(ivarType[0] == 'q')
    {
        long long longVal = (long long)(intptr_t)ivarObject;
        return [NSString stringWithFormat:@"%lli", longVal];
    }
    // Default unsigned data types
    else if(ivarType[0] == 'C')
    {
        unsigned char chracter = (unsigned char)(uintptr_t)ivarObject;
        return [NSString stringWithFormat:@"'%c'", chracter];
    }
    else if(ivarType[0] == 'I' || ivarType[0] == 'L')
    {
        unsigned int integer = (unsigned int)(uintptr_t)ivarObject;
        return [NSString stringWithFormat:@"%u", integer];
    }
    else if(ivarType[0] == 'S')
    {
        unsigned short shortVal = (unsigned short)(uintptr_t)ivarObject;
        return [NSString stringWithFormat:@"%i", (int)shortVal];
    }
    else if(ivarType[0] == 'Q')
    {
        unsigned long long longVal = (unsigned long long)(uintptr_t)ivarObject;
        return [NSString stringWithFormat:@"%llu", longVal];
    }
    // Floats'n'stuff
    else if(ivarType[0] == 'f')
    {
        float floatVal;
        memcpy(&floatVal, &ivarObject, sizeof(float));

        return [NSString stringWithFormat:@"%f", floatVal];
    }
    else if(ivarType[0] == 'd')
    {
        double doubleVal;
        memcpy(&doubleVal, &ivarObject, sizeof(double));

        return [NSString stringWithFormat:@"%f", doubleVal];
    }
    else if (ivarType[0] == 'b')
    {
        // Bitfield
        // There isn't a good way to handle this because we don't know the offset of this bit field. Just show the whole thing as a 32-bit int for now.
        int integer = (int)(intptr_t)ivarObject;
        return [NSString stringWithFormat:@"0x%x", integer];
    }
    // Boolean and pointer
    else if(ivarType[0] == 'B')
    {
        BOOL booleanVal = (BOOL)ivarObject;
        return [NSString stringWithFormat:@"%@", (booleanVal ? @"YES" : @"NO")];
    }
    else if(ivarType[0] == 'v')
    {
        void *pointer = (void *)ivarObject;
        return [NSString stringWithFormat:@"%p", pointer];
    }
    else if(ivarType[0] == '*' || ivarType[0] == ':') // SEL is just a typecast for a cstring
    {
        char *cstring = (char *)ivarObject;
        return [NSString stringWithFormat:@"\"%s\"", cstring];
    }
    else if(strncmp(ivarType, "@", 1) == 0)
    {
        return [NSString stringWithFormat:@"%@", ivarObject];
    }
    else if(ivarType[0] == '#')
    {
        // Class objects
        return @"#";
    }
    // Not currently handling:
    // - Arrays, e.g. [12^f]
    // - Unions
    // Partially works:
    // - Structs
    // - Bitfields

    return [NSString stringWithFormat:@"%s", ivarType];
}

- (NSString *)ivarDescription
{
    // Modified from https://stackoverflow.com/questions/6376344/generic-objective-c-description-method-to-print-ivar-values
    unsigned int count = 0;
    Class cls = [self class];
    NSMutableString *baseDescription = [NSMutableString stringWithFormat:@"<%@: %p>", NSStringFromClass([self class]), self];
    NSMutableArray *descriptions = [NSMutableArray array];
    [descriptions addObject:baseDescription];

    while (cls != nil) {
        [descriptions addObject:[NSString stringWithFormat:@"\n%@: {", NSStringFromClass(cls)]];
        Ivar *vars = class_copyIvarList(cls, &count);
        for (NSUInteger i=0; i<count; i++) {
            Ivar ivar = vars[i];
            const char *ivarName = ivar_getName(ivar);
            const char *ivarType = ivar_getTypeEncoding(ivar);
            ptrdiff_t ivarOffset = ivar_getOffset(ivar);
            id ivarObject = object_getIvar(self, ivar);

            void* ivarAddress = ((char*)self) + ivarOffset;

            [descriptions addObject:[NSString stringWithFormat:@"\n   %s: ", ivarName]];
            NSString *ivarDesc = ivarToString(self, ivarType, ivarAddress, ivarObject);
            [descriptions addObject:ivarDesc];
        }
        free(vars);
        [descriptions addObject:@"\n}"];

        cls = class_getSuperclass(cls);
    }
    NSString *description = [descriptions componentsJoinedByString:@""];
    return description;
}

- (void)dumpIvars
{
    NSString *ivarsDump = [self ivarDescription];
    NSLog(@"%@", ivarsDump);
    NSURL *dlDir = [NSFileManager.defaultManager URLForDirectory:NSDownloadsDirectory
                                                          inDomain:NSUserDomainMask
                                                 appropriateForURL:NSFileManager.defaultManager.homeDirectoryForCurrentUser
                                                            create:NO
                                                             error:nil];
    if (dlDir != nil) {
        int timestamp = (int)[[NSDate date] timeIntervalSince1970];
        NSURL *newFile = [dlDir URLByAppendingPathComponent:[NSString stringWithFormat:@"macvim_ivarsDump_%d.txt", timestamp]];
        if (![ivarsDump writeToURL:newFile atomically:NO encoding:NSUTF8StringEncoding error:nil]) {
            NSLog(@"Failed to write contents to ivars dump");
        }
    }
}

@end


    NSView *
showHiddenFilesView(void)
{
    // Return a new button object for each NSOpenPanel -- several of them
    // could be displayed at once.
    // If the accessory view should get more complex, it should probably be
    // loaded from a nib file.
    NSButton *button = [[[NSButton alloc]
        initWithFrame:NSMakeRect(0, 0, 140, 18)] autorelease];
    [button setTitle:
        NSLocalizedString(@"Show Hidden Files", @"Show Hidden Files Checkbox")];
    [button setButtonType:NSButtonTypeSwitch];

    [button setTarget:nil];
    [button setAction:@selector(hiddenFilesButtonToggled:)];

    // Use the regular control size (checkbox is a bit smaller without this)
    NSControlSize buttonSize = NSControlSizeRegular;
    float fontSize = [NSFont systemFontSizeForControlSize:buttonSize];
    NSCell *theCell = [button cell];
    NSFont *theFont = [NSFont fontWithName:[[theCell font] fontName]
                                      size:fontSize];
    [theCell setFont:theFont];
    [theCell setControlSize:buttonSize];
    [button sizeToFit];

    return button;
}




    NSString *
normalizeFilename(NSString *filename)
{
    return [filename precomposedStringWithCanonicalMapping];
}

    NSArray *
normalizeFilenames(NSArray *filenames)
{
    NSMutableArray *outnames = [NSMutableArray array];
    if (!filenames)
        return outnames;

    NSUInteger i, count = [filenames count];
    for (i = 0; i < count; ++i) {
        NSString *nfkc = normalizeFilename([filenames objectAtIndex:i]);
        [outnames addObject:nfkc];
    }

    return outnames;
}




    BOOL
shouldUseYosemiteTabBarStyle(void)
{ 
    return floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_10;
}
    BOOL
shouldUseMojaveTabBarStyle(void)
{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
    if (@available(macos 10.14, *)) {
        return true;
    }
#endif
    return false;
}

int
getCurrentAppearance(NSAppearance *appearance){
    int flag = 0; // for macOS 10.13 or earlier always return 0;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
    if (@available(macOS 10.14, *)) {
        NSAppearanceName appearanceName = [appearance bestMatchFromAppearancesWithNames:
                @[NSAppearanceNameAqua
                , NSAppearanceNameDarkAqua
                , NSAppearanceNameAccessibilityHighContrastAqua
                , NSAppearanceNameAccessibilityHighContrastDarkAqua]];
        if ([appearanceName isEqualToString:NSAppearanceNameDarkAqua]) {
            flag = 1;
        } else if ([appearanceName isEqualToString:NSAppearanceNameAccessibilityHighContrastAqua]) {
            flag = 2;
        } else if ([appearanceName isEqualToString:NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
            flag = 3;
        }
    }
#endif
    return flag;
}

/// Returns the pasteboard type to use for retrieving file names from a list of
/// files.
/// @return The pasteboard type that can be passed to NSPasteboard for registration.
NSPasteboardType getPasteboardFilenamesType(void)
{
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_13
    return NSPasteboardTypeFileURL;
#else
    return NSFilenamesPboardType;
#endif
}

/// Extract the list of file names from a pasteboard.
NSArray<NSString*>* extractPasteboardFilenames(NSPasteboard *pboard)
{
    // NSPasteboardTypeFileURL is only available in 10.13, and
    // NSFilenamesPboardType was deprecated soon after that (10.14).

    // As such if we are building with min deployed OS 10.13, we need to use
    // the new method (using NSPasteboardTypeFileURL /
    // readObjectsForClasses:options:) because otherwise we will get
    // deprecation warnings. Otherwise, we just use NSFilenamesPboardType. It
    // will still work if run in a newer OS since it's simply deprecated, and
    // the OS still supports it.
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_13
    if (![pboard.types containsObject:NSPasteboardTypeFileURL]) {
        ASLogNotice(@"Pasteboard contains no NSPasteboardTypeFileURL");
        return nil;
    }
    NSArray<NSURL*> *fileurls = [pboard readObjectsForClasses:@[NSURL.class]
                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: [NSNumber numberWithBool:YES]}];
    if (fileurls == nil || fileurls.count == 0) {
        return nil;
    }
    NSMutableArray<NSString *> *filenames = [NSMutableArray arrayWithCapacity:fileurls.count];
    for (int i = 0; i < fileurls.count; i++) {
        [filenames addObject:fileurls[i].path];
    }
    return filenames;
#else
    if (![pboard.types containsObject:NSFilenamesPboardType]) {
        ASLogNotice(@"Pasteboard contains no NSFilenamesPboardType");
        return nil;
    }

    NSArray<NSString *> *filenames = [pboard propertyListForType:NSFilenamesPboardType];
    return filenames;
#endif
}

/// Compare two version strings (must be in integers separated by dots) and see
/// if one is larger.
///
/// @return 1 if newVersion is newer, 0 if equal, -1 if oldVersion newer.
int compareSemanticVersions(NSString *oldVersion, NSString *newVersion)
{
    NSArray<NSString*> *oldVersionItems = [oldVersion componentsSeparatedByString:@"."];
    NSArray<NSString*> *newVersionItems = [newVersion componentsSeparatedByString:@"."];
    // Compare two arrays lexographically. We just assume that version
    // numbers are also X.Y.Z… with no "beta" etc texts.
    for (int i = 0; i < oldVersionItems.count || i < newVersionItems.count; i++) {
        if (i >= newVersionItems.count) {
            return -1;
        }
        if (i >= oldVersionItems.count) {
            return 1;
        }
        if (newVersionItems[i].integerValue > oldVersionItems[i].integerValue) {
            return 1;
        }
        else if (newVersionItems[i].integerValue < oldVersionItems[i].integerValue) {
            return -1;
        }
    }
    return 0;
}

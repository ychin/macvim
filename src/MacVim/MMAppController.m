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
 * MMAppController
 *
 * MMAppController is the delegate of NSApp and as such handles file open
 * requests, application termination, etc.  It sets up a named NSConnection on
 * which it listens to incoming connections from Vim processes.  It also
 * coordinates all MMVimControllers and takes care of the main menu.
 *
 * A new Vim process is started by calling launchVimProcessWithArguments:.
 * When the Vim process is initialized it notifies the app controller by
 * sending a connectBackend:pid: message.  At this point a new MMVimController
 * is allocated.  Afterwards, the Vim process communicates directly with its
 * MMVimController.
 *
 * A Vim process started from the command line connects directly by sending the
 * connectBackend:pid: message (launchVimProcessWithArguments: is never called
 * in this case).
 *
 * The main menu is handled as follows.  Each Vim controller keeps its own main
 * menu.  All menus except the "MacVim" menu are controlled by the Vim process.
 * The app controller also keeps a reference to the "default main menu" which
 * is set up in MainMenu.nib.  When no editor window is open the default main
 * menu is used.  When a new editor window becomes main its main menu becomes
 * the new main menu, this is done in -[MMAppController setMainMenu:].
 *   NOTE: Certain heuristics are used to find the "MacVim", "Windows", "File",
 * and "Services" menu.  If MainMenu.nib changes these heuristics may have to
 * change as well.  For specifics see the find... methods defined in the NSMenu
 * category "MMExtras".
 */

#import "MMAppController.h"
#import "MMPreferenceController.h"
#import "MMVimController.h"
#import "MMVimView.h"
#import "MMWindowController.h"
#import "MMTextView.h"
#import "MMWhatsNewController.h"
#import "Miscellaneous.h"
#import <unistd.h>
#import <CoreServices/CoreServices.h>
// Need Carbon for TIS...() functions
#import <Carbon/Carbon.h>

#if !DISABLE_SPARKLE
#import "MMSparkle2Delegate.h"
#import "Sparkle.framework/Headers/Sparkle.h"
#endif


#define MM_HANDLE_XCODE_MOD_EVENT 0



// Default timeout intervals on all connections.
static NSTimeInterval MMRequestTimeout = 5;
static NSTimeInterval MMReplyTimeout = 5;

static NSString *MMWebsiteString = @"https://macvim-dev.github.io/macvim/";

// Latency (in s) between FS event occuring and being reported to MacVim.
// Should be small so that MacVim is notified of changes to the ~/.vim
// directory more or less immediately.
static CFTimeInterval MMEventStreamLatency = 0.1;

static float MMCascadeHorizontalOffset = 21;
static float MMCascadeVerticalOffset = 23;


#pragma pack(push,1)
// The alignment and sizes of these fields are based on trial-and-error.  It
// may be necessary to adjust them to fit if Xcode ever changes this struct.
typedef struct
{
    int16_t unused1;      // 0 (not used)
    int16_t lineNum;      // line to select (< 0 to specify range)
    int32_t startRange;   // start of selection range (if line < 0)
    int32_t endRange;     // end of selection range (if line < 0)
    int32_t unused2;      // 0 (not used)
    int32_t theDate;      // modification date/time
} MMXcodeSelectionRange;
#pragma pack(pop)


// This is a private AppKit API gleaned from class-dump.
@interface NSKeyBindingManager : NSObject
+ (id)sharedKeyBindingManager;
- (id)dictionary;
- (void)setDictionary:(id)arg1;
@end


@interface MMAppController (MMServices)
- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error;
- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error;
- (void)newFileHere:(NSPasteboard *)pboard userData:(NSString *)userData
              error:(NSString **)error;
@end


@interface MMAppController (Private)
- (void)startUpdaterAndWhatsNewPage;

- (MMVimController *)topmostVimController;
- (int)launchVimProcessWithArguments:(NSArray *)args
                    workingDirectory:(NSString *)cwd;
- (NSArray *)filterFilesAndNotify:(NSArray *)files;
- (NSArray *)filterOpenFiles:(NSArray *)filenames
               openFilesDict:(NSDictionary **)openFiles;
#if MM_HANDLE_XCODE_MOD_EVENT
- (void)handleXcodeModEvent:(NSAppleEventDescriptor *)event
                 replyEvent:(NSAppleEventDescriptor *)reply;
#endif
+ (NSDictionary*)parseOpenURL:(NSURL*)url;
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event
               replyEvent:(NSAppleEventDescriptor *)reply;
- (NSMutableDictionary *)extractArgumentsFromOdocEvent:
    (NSAppleEventDescriptor *)desc;
- (void)scheduleVimControllerPreloadAfterDelay:(NSTimeInterval)delay;
- (void)cancelVimControllerPreloadRequests;
- (void)preloadVimController:(id)sender;
- (int)maxPreloadCacheSize;
- (MMVimController *)takeVimControllerFromCache;
- (void)clearPreloadCacheWithCount:(int)count;
- (void)rebuildPreloadCache;
- (NSDate *)rcFilesModificationDate;
- (BOOL)openVimControllerWithArguments:(NSDictionary *)arguments;
- (void)activateWhenNextWindowOpens;
- (void)startWatchingVimDir;
- (void)stopWatchingVimDir;
- (void)handleFSEvent;
- (int)executeInLoginShell:(NSString *)path arguments:(NSArray *)args;
- (void)reapChildProcesses:(id)sender;
- (void)processInputQueues:(id)sender;
- (void)addVimController:(MMVimController *)vc;
- (NSDictionary *)convertVimControllerArguments:(NSDictionary *)args
                                  toCommandLine:(NSArray **)cmdline;
- (NSString *)workingDirectoryForArguments:(NSDictionary *)args;
- (NSScreen *)screenContainingTopLeftPoint:(NSPoint)pt;
- (void)addInputSourceChangedObserver;
- (void)removeInputSourceChangedObserver;
- (void)inputSourceChanged:(NSNotification *)notification;
@end



    static void
fsEventCallback(ConstFSEventStreamRef streamRef,
                void *clientCallBackInfo,
                size_t numEvents,
                void *eventPaths,
                const FSEventStreamEventFlags eventFlags[],
                const FSEventStreamEventId eventIds[])
{
    [[MMAppController sharedInstance] handleFSEvent];
}

@implementation MMAppController

/// Register the default settings for MacVim. Supports an optional
/// "-IgnoreUserDefaults 1" command-line argument, which will override
/// persisted user settings to have a clean environment.
+ (void)registerDefaults
{
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;

    NSDictionary *macvimDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO],     MMNoWindowKey,
        [NSNumber numberWithInt:120],     MMTabMinWidthKey,
        [NSNumber numberWithInt:200],     MMTabOptimumWidthKey,
        [NSNumber numberWithBool:YES],    MMShowAddTabButtonKey,
        [NSNumber numberWithBool:NO],     MMShowTabScrollButtonsKey,
        [NSNumber numberWithInt:2],       MMTextInsetLeftKey,
        [NSNumber numberWithInt:1],       MMTextInsetRightKey,
        [NSNumber numberWithInt:1],       MMTextInsetTopKey,
        [NSNumber numberWithInt:1],       MMTextInsetBottomKey,
        @"MMTypesetter",                  MMTypesetterKey,
        [NSNumber numberWithFloat:1],     MMCellWidthMultiplierKey,
        [NSNumber numberWithFloat:-1],    MMBaselineOffsetKey,
        [NSNumber numberWithBool:YES],    MMTranslateCtrlClickKey,
        [NSNumber numberWithInt:0],       MMOpenInCurrentWindowKey,
        [NSNumber numberWithBool:NO],     MMNoFontSubstitutionKey,
        [NSNumber numberWithBool:YES],    MMFontPreserveLineSpacingKey,
        [NSNumber numberWithBool:YES],    MMLoginShellKey,
        [NSNumber numberWithInt:MMRendererCoreText],
                                          MMRendererKey,
        [NSNumber numberWithInt:MMUntitledWindowAlways],
                                          MMUntitledWindowKey,
        [NSNumber numberWithBool:NO],     MMNoWindowShadowKey,
        [NSNumber numberWithBool:NO],     MMDisableLaunchAnimationKey,
        [NSNumber numberWithInt:0],       MMAppearanceModeSelectionKey,
        [NSNumber numberWithBool:NO],     MMNoTitleBarWindowKey,
        [NSNumber numberWithBool:NO],     MMTitlebarAppearsTransparentKey,
        [NSNumber numberWithBool:NO],     MMZoomBothKey,
        @"",                              MMLoginShellCommandKey,
        @"",                              MMLoginShellArgumentKey,
        [NSNumber numberWithBool:YES],    MMDialogsTrackPwdKey,
        [NSNumber numberWithInt:3],       MMOpenLayoutKey,
        [NSNumber numberWithBool:NO],     MMVerticalSplitKey,
        [NSNumber numberWithInt:0],       MMPreloadCacheSizeKey,
        [NSNumber numberWithInt:0],       MMLastWindowClosedBehaviorKey,
#ifdef INCLUDE_OLD_IM_CODE
        [NSNumber numberWithBool:YES],    MMUseInlineImKey,
#endif // INCLUDE_OLD_IM_CODE
        [NSNumber numberWithBool:NO],     MMSuppressTerminationAlertKey,
        [NSNumber numberWithBool:YES],    MMNativeFullScreenKey,
        [NSNumber numberWithDouble:0.0],  MMFullScreenFadeTimeKey,
        [NSNumber numberWithBool:NO],     MMNonNativeFullScreenShowMenuKey,
        [NSNumber numberWithInt:0],       MMNonNativeFullScreenSafeAreaBehaviorKey,
        [NSNumber numberWithBool:YES],    MMShareFindPboardKey,
        [NSNumber numberWithBool:NO],     MMSmoothResizeKey,
        [NSNumber numberWithBool:NO],     MMCmdLineAlignBottomKey,
        [NSNumber numberWithBool:NO],     MMRendererClipToRowKey,
        [NSNumber numberWithBool:YES],    MMAllowForceClickLookUpKey,
        [NSNumber numberWithBool:NO],     MMUpdaterPrereleaseChannelKey,
        @"",                              MMLastUsedBundleVersionKey,
        [NSNumber numberWithBool:YES],    MMShowWhatsNewOnStartupKey,
        [NSNumber numberWithBool:0],      MMScrollOneDirectionOnlyKey,
        nil];

    [ud registerDefaults:macvimDefaults];

    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if ([arguments containsObject:@"-IgnoreUserDefaults"]) {
        NSDictionary<NSString *, id> *argDefaults = [ud volatileDomainForName:NSArgumentDomain];
        NSMutableDictionary<NSString *, id> *combinedDefaults = [NSMutableDictionary dictionaryWithCapacity: macvimDefaults.count];
        [combinedDefaults setDictionary:macvimDefaults];
        [combinedDefaults addEntriesFromDictionary:argDefaults];
        [ud setVolatileDomain:combinedDefaults forName:NSArgumentDomain];
    }
}

+ (void)initialize
{
    static BOOL initDone = NO;
    if (initDone) return;
    initDone = YES;

    ASLInit();

    // HACK! The following user default must be reset, else Ctrl-q (or
    // whichever key is specified by the default) will be blocked by the input
    // manager (interpreargumenttKeyEvents: swallows that key).  (We can't use
    // NSUserDefaults since it only allows us to write to the registration
    // domain and this preference has "higher precedence" than that so such a
    // change would have no effect.)
    CFPreferencesSetAppValue(CFSTR("NSQuotedKeystrokeBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);

    // Also disable NSRepeatCountBinding -- it is not enabled by default, but
    // it does not make much sense to support it since Vim has its own way of
    // dealing with repeat counts.
    CFPreferencesSetAppValue(CFSTR("NSRepeatCountBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);

    if ([NSWindow respondsToSelector:@selector(setAllowsAutomaticWindowTabbing:)]) {
        // Disable automatic tabbing on 10.12+. MacVim already has its own
        // tabbing interface, so we don't want multiple hierarchy of tabs mixing
        // native and Vim tabs. MacVim also doesn't work well with native tabs
        // right now since it doesn't respond well to the size change, and it
        // doesn't show the native menu items (e.g. move tab to new window) in
        // all the tabs.
        //
        // Note: MacVim cannot use macOS native tabs for Vim tabs because Vim
        // assumes only one tab can be shown at a time, and it would be hard to
        // handle native tab's "move tab to a new window" functionality.
        [NSWindow setAllowsAutomaticWindowTabbing:NO];
    }

    [MMAppController registerDefaults];

    NSArray *types = [NSArray arrayWithObject:NSPasteboardTypeString];
    [NSApp registerServicesMenuSendTypes:types returnTypes:types];

    // NOTE: Set the current directory to user's home directory, otherwise it
    // will default to the root directory.  (This matters since new Vim
    // processes inherit MacVim's environment variables.)
    [[NSFileManager defaultManager] changeCurrentDirectoryPath:
            NSHomeDirectory()];
}

- (id)init
{
    if (!(self = [super init])) return nil;

#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
    // Disable automatic relaunching
    if ([NSApp respondsToSelector:@selector(disableRelaunchOnLogin)])
        [NSApp disableRelaunchOnLogin];
#endif

    vimControllers = [NSMutableArray new];
    cachedVimControllers = [NSMutableArray new];
    preloadPid = -1;
    pidArguments = [NSMutableDictionary new];
    inputQueues = [NSMutableDictionary new];

    // NOTE: Do not use the default connection since the Logitech Control
    // Center (LCC) input manager steals and this would cause MacVim to
    // never open any windows.  (This is a bug in LCC but since they are
    // unlikely to fix it, we graciously give them the default connection.)
    connection = [[NSConnection alloc] initWithReceivePort:[NSPort port]
                                                  sendPort:nil];
    NSProtocolChecker *rootObject = [NSProtocolChecker protocolCheckerWithTarget:self
                                                                        protocol:@protocol(MMAppProtocol)];
    [connection setRootObject:rootObject];
    [connection setRequestTimeout:MMRequestTimeout];
    [connection setReplyTimeout:MMReplyTimeout];

    // NOTE!  If the name of the connection changes here it must also be
    // updated in MMBackend.m.
    NSString *name = [NSString stringWithFormat:@"%@-connection",
             [[NSBundle mainBundle] bundlePath]];
    if (![connection registerName:name]) {
        ASLogCrit(@"Failed to register connection with name '%@'", name);
        [connection release];  connection = nil;

        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"OK",
            @"Dialog button")];
        [alert setMessageText:NSLocalizedString(@"MacVim cannot be opened",
            @"MacVim cannot be opened, title")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(
            @"MacVim could not set up its connection. It's likely you already have MacVim opened elsewhere.",
            @"MacVim already opened, text")]];
        [alert setAlertStyle:NSAlertStyleCritical];
        [alert runModal];
        [alert release];

        [[NSApplication sharedApplication] terminate:nil];
    }

    // Register help search handler to support search Vim docs via the Help menu
    [NSApp registerUserInterfaceItemSearchHandler:self];

#if !DISABLE_SPARKLE
    // Sparkle is enabled (this is the default). Initialize it. It will
    // automatically check for update.
#if USE_SPARKLE_1
    updater = [[SUUpdater alloc] init];
#else
    sparkle2delegate = [[MMSparkle2Delegate alloc] init];

    // We don't immediately start the updater, because if it sees an update
    // and immediately shows the dialog box it will pop up behind a new MacVim
    // window. Instead, startUpdaterAndWhatsNewPage will be called later to do so.
    updater = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO updaterDelegate:sparkle2delegate userDriverDelegate:sparkle2delegate];
#endif
#endif

    return self;
}

- (void)dealloc
{
    ASLogDebug(@"");

    [connection release];  connection = nil;
    [inputQueues release];  inputQueues = nil;
    [pidArguments release];  pidArguments = nil;
    [vimControllers release];  vimControllers = nil;
    [cachedVimControllers release];  cachedVimControllers = nil;
    [openSelectionString release];  openSelectionString = nil;
    [recentFilesMenuItem release];  recentFilesMenuItem = nil;
    [defaultMainMenu release];  defaultMainMenu = nil;
    currentMainMenu = nil;
    [appMenuItemTemplate release];  appMenuItemTemplate = nil;
#if !DISABLE_SPARKLE
    [updater release];  updater = nil;
#if !USE_SPARKLE_1
    [sparkle2delegate release];  sparkle2delegate = nil;
#endif
#endif

    [super dealloc];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // This prevents macOS from injecting "Enter Full Screen" menu item.
    // MacVim already has a separate menu item to do that.
    // See https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/index.html#10_11FullScreen
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"NSFullScreenMenuItemEverywhere"];

    // Remember the default menu so that it can be restored if the user closes
    // all editor windows.
    defaultMainMenu = [[NSApp mainMenu] retain];

    // Store a copy of the default app menu so we can use this as a template
    // for all other menus.  We make a copy here because the "Services" menu
    // will not yet have been populated at this time.  If we don't we get
    // problems trying to set key equivalents later on because they might clash
    // with items on the "Services" menu.
    appMenuItemTemplate = [defaultMainMenu itemAtIndex:0];
    appMenuItemTemplate = [appMenuItemTemplate copy];

    // Set up the "Open Recent" menu. See
    //   http://lapcatsoftware.com/blog/2007/07/10/
    //     working-without-a-nib-part-5-open-recent-menu/
    // and
    //   http://www.cocoabuilder.com/archive/message/cocoa/2007/8/15/187793
    // for more information.
    //
    // The menu itself is created in MainMenu.nib but we still seem to have to
    // hack around a bit to get it to work.  (This has to be done in
    // applicationWillFinishLaunching at the latest, otherwise it doesn't
    // work.)
    NSMenu *fileMenu = [defaultMainMenu findFileMenu];
    if (fileMenu) {
        int idx = [fileMenu indexOfItemWithAction:@selector(fileOpen:)];
        if (idx >= 0 && idx+1 < [fileMenu numberOfItems])

        recentFilesMenuItem = [fileMenu itemWithTag:15432];
        [[recentFilesMenuItem submenu] performSelector:@selector(_setMenuName:)
                                        withObject:@"NSRecentDocumentsMenu"];

        // Note: The "Recent Files" menu must be moved around since there is no
        // -[NSApp setRecentFilesMenu:] method.  We keep a reference to it to
        // facilitate this move (see setMainMenu: below).
        [recentFilesMenuItem retain];
    }

#if MM_HANDLE_XCODE_MOD_EVENT
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler:self
                andSelector:@selector(handleXcodeModEvent:replyEvent:)
              forEventClass:'KAHL'
                 andEventID:'MOD '];
#endif

    // Register 'mvim://' URL handler
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler:self
                andSelector:@selector(handleGetURLEvent:replyEvent:)
              forEventClass:kInternetEventClass
                 andEventID:kAEGetURL];

    // Disable the default Cocoa "Key Bindings" since they interfere with the
    // way Vim handles keyboard input.  Cocoa reads bindings from
    //     /System/Library/Frameworks/AppKit.framework/Resources/
    //                                                  StandardKeyBinding.dict
    // and
    //     ~/Library/KeyBindings/DefaultKeyBinding.dict
    // To avoid having the user accidentally break keyboard handling (by
    // modifying the latter in some unexpected way) in MacVim we load our own
    // key binding dictionary from Resource/KeyBinding.plist.  We can't disable
    // the bindings completely since it would break keyboard handling in
    // dialogs so the our custom dictionary contains all the entries from the
    // former location.
    //
    // It is possible to disable key bindings completely by not calling
    // interpretKeyEvents: in keyDown: but this also disables key bindings used
    // by certain input methods.  E.g.  Ctrl-Shift-; would no longer work in
    // the Kotoeri input manager.
    //
    // To solve this problem we access a private API and set the key binding
    // dictionary to our own custom dictionary here.  At this time Cocoa will
    // have already read the above mentioned dictionaries so it (hopefully)
    // won't try to change the key binding dictionary again after this point.
    NSKeyBindingManager *mgr = [NSKeyBindingManager sharedKeyBindingManager];
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *path = [mainBundle pathForResource:@"KeyBinding"
                                          ofType:@"plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (mgr && dict) {
        [mgr setDictionary:dict];
    } else {
        ASLogNotice(@"Failed to override the Cocoa key bindings.  Keyboard "
                "input may behave strangely as a result (path=%@).", path);
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [NSApp setServicesProvider:self];

    if ([self maxPreloadCacheSize] > 0) {
        [self scheduleVimControllerPreloadAfterDelay:2];
        [self startWatchingVimDir];
    }

    [self addInputSourceChangedObserver];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    NSString *lastUsedVersion = [ud stringForKey:MMLastUsedBundleVersionKey];
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:
            @"CFBundleVersion"];
    // This will be used for showing a "What's New" dialog box in the future. For
    // now, just update the stored version for future use so later versions will
    // be able to tell whether to show this dialog box or not.
    if (currentVersion && currentVersion.length != 0) {
        if (!lastUsedVersion || [lastUsedVersion length] == 0) {
            [ud setValue:currentVersion forKey:MMLastUsedBundleVersionKey];
        } else {
            // If the current version is larger, set that to be stored. Don't
            // want to do it otherwise to prevent testing older versions flipping
            // the stored version back to an old one.
            const BOOL currentVersionLarger = (compareSemanticVersions(lastUsedVersion, currentVersion) == 1);
            if (currentVersionLarger) {
                [ud setValue:currentVersion forKey:MMLastUsedBundleVersionKey];

                // We have successfully updated to a new version. Show a
                // "What's New" page to the user with latest release notes
                // unless they configured not to.
                BOOL showWhatsNewSetting = [ud boolForKey:MMShowWhatsNewOnStartupKey];

                shouldShowWhatsNewPage = showWhatsNewSetting;
                [MMWhatsNewController setRequestVersionRange:lastUsedVersion
                                                          to:currentVersion];
            }
        }
    }

    // Start the Sparkle updater and potentially show "What's New". If the user
    // doesn't want a new untitled MacVim window shown, we immediately do so.
    // Otherwise we want to do it *after* the untitled window is opened so the
    // updater / "What's New" page can be shown on top of it. We still schedule
    // a timer to open it as a backup in case something wrong happened with the
    // Vim window (e.g. a crash in Vim) but we still want the updater to work since
    // that update may very well be the fix for the crash.
    const NSInteger untitledWindowFlag = [ud integerForKey:MMUntitledWindowKey];
    if ((untitledWindowFlag & MMUntitledWindowOnOpen) == 0) {
        [self startUpdaterAndWhatsNewPage];
    } else {
        // Per above, this is just a backup. startUpdaterAndWhatsNewPage will
        // not do anything if it's called a second time.
        [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(startUpdaterAndWhatsNewPage) userInfo:nil repeats:NO];
    }

    ASLogInfo(@"MacVim finished launching");
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSAppleEventManager *aem = [NSAppleEventManager sharedAppleEventManager];
    NSAppleEventDescriptor *desc = [aem currentAppleEvent];

    // The user default MMUntitledWindow can be set to control whether an
    // untitled window should open on 'Open' and 'Reopen' events.
    NSInteger untitledWindowFlag = [ud integerForKey:MMUntitledWindowKey];

    BOOL isAppOpenEvent = [desc eventID] == kAEOpenApplication;
    if (isAppOpenEvent && (untitledWindowFlag & MMUntitledWindowOnOpen) == 0)
        return NO;

    BOOL isAppReopenEvent = [desc eventID] == kAEReopenApplication;
    if (isAppReopenEvent
            && (untitledWindowFlag & MMUntitledWindowOnReopen) == 0)
        return NO;

    // When a process is started from the command line, the 'Open' event may
    // contain a parameter to surpress the opening of an untitled window.
    desc = [desc paramDescriptorForKeyword:keyAEPropData];
    desc = [desc paramDescriptorForKeyword:keyMMUntitledWindow];
    if (desc && ![desc booleanValue])
        return NO;

    // Never open an untitled window if there is at least one open window.
    if ([vimControllers count] > 0)
        return NO;

    // Don't open an untitled window if there are processes about to launch...
    NSUInteger numLaunching = [pidArguments count];
    if (numLaunching > 0) {
        // ...unless the launching process is being preloaded
        NSNumber *key = [NSNumber numberWithInt:preloadPid];
        if (numLaunching != 1 || [pidArguments objectForKey:key] == nil)
            return NO;
    }

    // NOTE!  This way it possible to start the app with the command-line
    // argument '-nowindow yes' and no window will be opened by default but
    // this argument will only be heeded when the application is opening.
    if (isAppOpenEvent && [ud boolForKey:MMNoWindowKey] == YES)
        return NO;

    return YES;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender
{
    ASLogDebug(@"Opening untitled window...");
    [self newWindow:self];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    ASLogInfo(@"Opening files %@", filenames);

    // Extract ODB/Xcode/Spotlight parameters from the current Apple event,
    // sort the filenames, and then let openFiles:withArguments: do the heavy
    // lifting.

    if (!(filenames && [filenames count] > 0))
        return;

    // Sort filenames since the Finder doesn't take care in preserving the
    // order in which files are selected anyway (and "sorted" is more
    // predictable than "random").
    if ([filenames count] > 1)
        filenames = [filenames sortedArrayUsingSelector:
                @selector(localizedCompare:)];

    // Extract ODB/Xcode/Spotlight parameters from the current Apple event
    NSMutableDictionary *arguments = [self extractArgumentsFromOdocEvent:
            [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent]];

    if ([self openFiles:filenames withArguments:arguments]) {
        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    } else {
        // TODO: Notify user of failure?
        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    if (!hasShownWindowBefore) {
        // If we have not opened a window before, never return YES. This can
        // happen when MacVim is not configured to open window at launch. We
        // want to give the user a chance to open a window first. Otherwise
        // just opening the About MacVim or Settings windows could immediately
        // terminate the app (since those are not proper app windows),
        // depending if the OS feels like invoking this method.
        return NO;
    }
    return (MMTerminateWhenLastWindowClosed ==
            [[NSUserDefaults standardUserDefaults]
                integerForKey:MMLastWindowClosedBehaviorKey]);
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication *)sender
{
    // TODO: Follow Apple's guidelines for 'Graceful Application Termination'
    // (in particular, allow user to review changes and save).
    int reply = NSTerminateNow;
    BOOL modifiedBuffers = NO;

    // Go through Vim controllers, checking for modified buffers.
    NSEnumerator *e = [vimControllers objectEnumerator];
    id vc;
    while ((vc = [e nextObject])) {
        if ([vc hasModifiedBuffer]) {
            modifiedBuffers = YES;
            break;
        }
    }

    if (modifiedBuffers) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert addButtonWithTitle:NSLocalizedString(@"Quit",
                @"Dialog button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel",
                @"Dialog button")];
        [alert setMessageText:NSLocalizedString(@"Quit without saving?",
                @"Quit dialog with changed buffers, title")];
        [alert setInformativeText:NSLocalizedString(
                @"There are modified buffers, "
                "if you quit now all changes will be lost.  Quit anyway?",
                @"Quit dialog with changed buffers, text")];

        if ([alert runModal] != NSAlertFirstButtonReturn)
            reply = NSTerminateCancel;

        [alert release];
    } else if (![[NSUserDefaults standardUserDefaults]
                                boolForKey:MMSuppressTerminationAlertKey]) {
        // No unmodified buffers, but give a warning if there are multiple
        // windows and/or tabs open.
        int numWindows = (int)[vimControllers count];
        int numTabs = 0;

        // Count the number of open tabs
        e = [vimControllers objectEnumerator];
        while ((vc = [e nextObject]))
            numTabs += [[vc objectForVimStateKey:@"numTabs"] intValue];

        if (numWindows > 1 || numTabs > 1) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setAlertStyle:NSAlertStyleWarning];
            [alert addButtonWithTitle:NSLocalizedString(@"Quit",
                    @"Dialog button")];
            [alert addButtonWithTitle:NSLocalizedString(@"Cancel",
                    @"Dialog button")];
            [alert setMessageText:NSLocalizedString(
                    @"Are you sure you want to quit MacVim?",
                    @"Quit dialog with no changed buffers, title")];
            [alert setShowsSuppressionButton:YES];

            NSString *info = nil;
            if (numWindows > 1) {
                if (numTabs > numWindows)
                    info = [NSString stringWithFormat:NSLocalizedString(
                            @"There are %d windows open in MacVim, with a "
                            "total of %d tabs. Do you want to quit anyway?",
                            @"Quit dialog with no changed buffers, text"),
                         numWindows, numTabs];
                else
                    info = [NSString stringWithFormat:NSLocalizedString(
                            @"There are %d windows open in MacVim. "
                            "Do you want to quit anyway?",
                            @"Quit dialog with no changed buffers, text"),
                        numWindows];

            } else {
                info = [NSString stringWithFormat:NSLocalizedString(
                        @"There are %d tabs open in MacVim. "
                        "Do you want to quit anyway?",
                        @"Quit dialog with no changed buffers, text"), 
                     numTabs];
            }

            [alert setInformativeText:info];

            if ([alert runModal] != NSAlertFirstButtonReturn)
                reply = NSTerminateCancel;

            if ([[alert suppressionButton] state] == NSControlStateValueOn) {
                [[NSUserDefaults standardUserDefaults]
                            setBool:YES forKey:MMSuppressTerminationAlertKey];
            }

            [alert release];
        }
    }


    // Tell all Vim processes to terminate now (otherwise they'll leave swap
    // files behind).
    if (NSTerminateNow == reply) {
        e = [vimControllers objectEnumerator];
        id vc;
        while ((vc = [e nextObject])) {
            ASLogDebug(@"Terminate pid=%d", [vc pid]);
            [vc sendMessage:TerminateNowMsgID data:nil];
        }

        e = [cachedVimControllers objectEnumerator];
        while ((vc = [e nextObject])) {
            ASLogDebug(@"Terminate pid=%d (cached)", [vc pid]);
            [vc sendMessage:TerminateNowMsgID data:nil];
        }

        // If a Vim process is being preloaded as we quit we have to forcibly
        // kill it since we have not established a connection yet.
        if (preloadPid > 0) {
            ASLogDebug(@"Kill incomplete preloaded process pid=%d", preloadPid);
            kill(preloadPid, SIGKILL);
        }

        // If a Vim process was loading as we quit we also have to kill it.
        e = [[pidArguments allKeys] objectEnumerator];
        NSNumber *pidKey;
        while ((pidKey = [e nextObject])) {
            ASLogDebug(@"Kill incomplete process pid=%d", [pidKey intValue]);
            kill([pidKey intValue], SIGKILL);
        }

        // Sleep a little to allow all the Vim processes to exit.
        usleep(10000);
    }

    return reply;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    ASLogInfo(@"Terminating MacVim...");

    [self removeInputSourceChangedObserver];

    [self stopWatchingVimDir];

#if MM_HANDLE_XCODE_MOD_EVENT
    [[NSAppleEventManager sharedAppleEventManager]
            removeEventHandlerForEventClass:'KAHL'
                                 andEventID:'MOD '];
#endif

    // We are hard shutting down the app here by terminating all Vim processes
    // and then just quit without cleanly removing each Vim controller. We
    // don't want the straggler controllers to still interact with the now
    // invalid connections, so we just mark them as uninitialized.
    for (NSUInteger i = 0, count = [vimControllers count]; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [vc uninitialize];
    }

    // This will invalidate all connections (since they were spawned from this
    // connection).
    [connection invalidate];

    [NSApp setDelegate:nil];

    // Try to wait for all child processes to avoid leaving zombies behind (but
    // don't wait around for too long).
    NSDate *timeOutDate = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([timeOutDate timeIntervalSinceNow] > 0) {
        [self reapChildProcesses:nil];
        if (numChildProcesses <= 0)
            break;

        ASLogDebug(@"%d processes still left, hold on...", numChildProcesses);

        // Run in NSConnectionReplyMode while waiting instead of calling e.g.
        // usleep().  Otherwise incoming messages may clog up the DO queues and
        // the outgoing TerminateNowMsgID sent earlier never reaches the Vim
        // process.
        // This has at least one side-effect, namely we may receive the
        // annoying "dropping incoming DO message".  (E.g. this may happen if
        // you quickly hit Cmd-n several times in a row and then immediately
        // press Cmd-q, Enter.)
        while (CFRunLoopRunInMode((CFStringRef)NSConnectionReplyMode,
                0.05, true) == kCFRunLoopRunHandledSource)
            ;   // do nothing
    }

    if (numChildProcesses > 0) {
        ASLogNotice(@"%d zombies left behind", numChildProcesses);
    }
}

+ (MMAppController *)sharedInstance
{
    // Note: The app controller is a singleton which is instantiated in
    // MainMenu.nib where it is also connected as the delegate of NSApp.
    id delegate = [NSApp delegate];
    return [delegate isKindOfClass:self] ? (MMAppController*)delegate : nil;
}

- (NSMenu *)defaultMainMenu
{
    return defaultMainMenu;
}

- (NSMenuItem *)appMenuItemTemplate
{
    return appMenuItemTemplate;
}

- (void)removeVimController:(id)controller
{
    ASLogDebug(@"Remove Vim controller pid=%d id=%lu (processingFlag=%d)",
               [controller pid], [controller vimControllerId], processingFlag);

    NSUInteger idx = [vimControllers indexOfObject:controller];
    if (NSNotFound == idx) {
        ASLogDebug(@"Controller not found, probably due to duplicate removal");
        return;
    }

    [controller retain];
    [vimControllers removeObjectAtIndex:idx];
    [controller cleanup];
    [controller release];

    if (![vimControllers count]) {
        // The last editor window just closed so restore the main menu back to
        // its default state (which is defined in MainMenu.nib).
        [self setMainMenu:defaultMainMenu];

        BOOL hide = (MMHideWhenLastWindowClosed ==
                    [[NSUserDefaults standardUserDefaults]
                        integerForKey:MMLastWindowClosedBehaviorKey]);
        if (hide)
            [NSApp hide:self];
    }

    // There is a small delay before the Vim process actually exits so wait a
    // little before trying to reap the child process.  If the process still
    // hasn't exited after this wait it won't be reaped until the next time
    // reapChildProcesses: is called (but this should be harmless).
    [self performSelector:@selector(reapChildProcesses:)
               withObject:nil
               afterDelay:0.1];
}

- (void)windowControllerWillOpen:(MMWindowController *)windowController
{
    NSPoint topLeft = NSZeroPoint;
    NSWindow *cascadeFrom = [[[self topmostVimController] windowController]
                                                                    window];
    NSWindow *win = [windowController window];

    if (!win) return;

    // Heuristic to determine where to position the window:
    //   1. Use the default top left position (set using :winpos in .[g]vimrc)
    //   2. Cascade from an existing window
    //   3. Use autosaved position
    // If all of the above fail, then the window position is not changed.
    if ([windowController getDefaultTopLeft:&topLeft]) {
        // Make sure the window is not cascaded (note that topLeft was set in
        // the above call).
        cascadeFrom = nil;
    } else if (cascadeFrom) {
        NSRect frame = [cascadeFrom frame];
        topLeft = NSMakePoint(frame.origin.x, NSMaxY(frame));
    } else {
        NSString *topLeftString = [[NSUserDefaults standardUserDefaults]
            stringForKey:MMTopLeftPointKey];
        if (topLeftString)
            topLeft = NSPointFromString(topLeftString);
    }

    if (!NSEqualPoints(topLeft, NSZeroPoint)) {
        // Try to tile from the correct screen in case the user has multiple
        // monitors ([win screen] always seems to return the "main" screen).
        //
        // TODO: Check for screen _closest_ to top left?
        NSScreen *screen = [self screenContainingTopLeftPoint:topLeft];
        if (!screen)
            screen = [win screen];

        BOOL willSwitchScreens = screen != [win screen];
        if (cascadeFrom) {
            // Do manual cascading instead of using
            // -[MMWindow cascadeTopLeftFromPoint:] since it is rather
            // unpredictable.
            topLeft.x += MMCascadeHorizontalOffset;
            topLeft.y -= MMCascadeVerticalOffset;
        }

        if (screen) {
            // Constrain the window so that it is entirely visible on the
            // screen.  If it sticks out on the right, move it all the way
            // left.  If it sticks out on the bottom, move it all the way up.
            // (Assumption: the cascading offsets are positive.)
            NSRect screenFrame = [screen frame];
            NSSize winSize = [win frame].size;
            NSRect winFrame =
                { { topLeft.x, topLeft.y - winSize.height }, winSize };

            if (NSMaxX(winFrame) > NSMaxX(screenFrame))
                topLeft.x = NSMinX(screenFrame);
            if (NSMinY(winFrame) < NSMinY(screenFrame))
                topLeft.y = NSMaxY(screenFrame);
        } else {
            ASLogNotice(@"Window not on screen, don't constrain position");
        }

        // setFrameTopLeftPoint will trigger a resize event if the window is
        // moved across monitors; at this point such a resize would incorrectly
        // constrain the window to the default vim dimensions, so a specialized
        // method is used that will avoid that behavior.
        if (willSwitchScreens)
            [windowController moveWindowAcrossScreens:topLeft];
        else
            [win setFrameTopLeftPoint:topLeft];
    }

    if (1 == [vimControllers count]) {
        // The first window autosaves its position.  (The autosaving
        // features of Cocoa are not used because we need more control over
        // what is autosaved and when it is restored.)
        [windowController setWindowAutosaveKey:MMTopLeftPointKey];
    }

    if (openSelectionString) {
        // TODO: Pass this as a parameter instead!  Get rid of
        // 'openSelectionString' etc.
        //
        // There is some text to paste into this window as a result of the
        // services menu "Open selection ..." being used.
        [[windowController vimController] dropString:openSelectionString];
        [openSelectionString release];
        openSelectionString = nil;
    }

    if (shouldActivateWhenNextWindowOpens) {
        [NSApp activateIgnoringOtherApps:YES];
        shouldActivateWhenNextWindowOpens = NO;
    }

    hasShownWindowBefore = YES;

    // If this is the first untitled window we defer starting updater/what's new
    // to now to make sure they can be shown on top. Otherwise calling this will
    // do nothing so it's safe.
    [self startUpdaterAndWhatsNewPage];
}

- (void)setMainMenu:(NSMenu *)mainMenu
{
    if (currentMainMenu == mainMenu) {
        return;
    }
    currentMainMenu = mainMenu;
    [self refreshMainMenu];
}

// Refresh the currently active main menu. This call is necessary when any
// modification was made to the menu, because refreshMainMenu makes a copy of
// the main menu, meaning that modifications to the original menu wouldn't be
// reflected until refreshMainMenu is invoked.
- (void)markMainMenuDirty:(NSMenu *)mainMenu
{
    if (currentMainMenu != mainMenu) {
        // The menu being updated is not the currently set menu, so just ignore,
        // as this is likely a background Vim window.
        return;
    }
    if (!mainMenuDirty) {
        // Mark the main menu as dirty and queue up a refresh. We don't immediately
        // execute the refresh so that multiple calls would get batched up in one go.
        mainMenuDirty = YES;
        [self performSelectorOnMainThread:@selector(refreshMainMenu) withObject:nil waitUntilDone:NO];
    }
}

- (void)refreshMainMenu
{
    mainMenuDirty = NO;

    // Make a copy of the menu before we pass to AppKit. The main reason is
    // that setWindowsMenu: below will inject items like "Tile Window to Left
    // of Screen" to the Window menu, and on repeated calls it will keep adding
    // the same item over and over again, without resolving for duplicates. Using
    // copies help keep the source menu clean.
    NSMenu *mainMenu = [[currentMainMenu copy] autorelease];

    // If the new menu has a "Recent Files" dummy item, then swap the real item
    // for the dummy.  We are forced to do this since Cocoa initializes the
    // "Recent Files" menu and there is no way to simply point Cocoa to a new
    // item each time the menus are swapped.
    NSMenu *fileMenu = [mainMenu findFileMenu];
    if (recentFilesMenuItem && fileMenu) {
        int dummyIdx =
            [fileMenu indexOfItemWithAction:@selector(recentFilesDummy:)];
        if (dummyIdx >= 0) {
            NSMenuItem *dummyItem = [[fileMenu itemAtIndex:dummyIdx] retain];
            [fileMenu removeItemAtIndex:dummyIdx];

            NSMenu *recentFilesParentMenu = [recentFilesMenuItem menu];
            NSInteger idx = [recentFilesParentMenu indexOfItem:recentFilesMenuItem];
            if (idx >= 0) {
                [[recentFilesMenuItem retain] autorelease];
                [recentFilesParentMenu removeItemAtIndex:idx];
                [recentFilesParentMenu insertItem:dummyItem atIndex:idx];
            }

            [fileMenu insertItem:recentFilesMenuItem atIndex:dummyIdx];
            [dummyItem release];
        }
    }

#if DISABLE_SPARKLE
    NSMenu *appMenu = [mainMenu findApplicationMenu];

    // If Sparkle is disabled, we want to remove the "Check for Updates" menu
    // item since it's no longer useful.
    NSMenuItem *checkForUpdatesItem = [appMenu itemAtIndex:
                                       [appMenu indexOfItemWithAction:@selector(checkForUpdates:)]];
    checkForUpdatesItem.hidden = true;
#endif

    // Now set the new menu.  Notice that we keep one menu for each editor
    // window since each editor can have its own set of menus.  When swapping
    // menus we have to tell Cocoa where the new "MacVim", "Windows", and
    // "Services" menu are.
    [NSApp setMainMenu:mainMenu];

    NSMenu *servicesMenu = [mainMenu findServicesMenu];
    [NSApp setServicesMenu:servicesMenu];

    NSMenu *windowsMenu = [mainMenu findWindowsMenu];
    [NSApp setWindowsMenu:windowsMenu];

    NSMenu *helpMenu = [mainMenu findHelpMenu];
    [NSApp setHelpMenu:helpMenu];
}

- (NSArray *)filterOpenFiles:(NSArray *)filenames
{
    return [self filterOpenFiles:filenames openFilesDict:nil];
}

- (BOOL)openFiles:(NSArray *)filenames withArguments:(NSDictionary *)args
{
    // Opening files works like this:
    //  a) filter out any already open files
    //  b) open any remaining files
    //
    // Each launching Vim process has a dictionary of arguments that are passed
    // to the process when in checks in (via connectBackend:pid:).  The
    // arguments for each launching process can be looked up by its PID (in the
    // pidArguments dictionary).

    NSMutableDictionary *arguments = (args ? [[args mutableCopy] autorelease]
                                           : [NSMutableDictionary dictionary]);

    filenames = normalizeFilenames(filenames);

    //
    // a) Filter out any already open files
    //
    NSString *firstFile = [filenames objectAtIndex:0];
    NSDictionary *openFilesDict = nil;
    filenames = [self filterOpenFiles:filenames openFilesDict:&openFilesDict];

    // The meaning of "layout" is defined by the WIN_* defines in main.c.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger layout = [ud integerForKey:MMOpenLayoutKey];
    BOOL splitVert = [ud boolForKey:MMVerticalSplitKey];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];

    if (splitVert && MMLayoutHorizontalSplit == layout)
        layout = MMLayoutVerticalSplit;
    if (layout < 0 || (layout > MMLayoutTabs && openInCurrentWindow))
        layout = MMLayoutTabs;

    // Pass arguments to vim controllers that had files open.
    id key;
    NSEnumerator *e = [openFilesDict keyEnumerator];

    // (Indicate that we do not wish to open any files at the moment.)
    [arguments setObject:[NSNumber numberWithBool:YES] forKey:@"dontOpen"];

    while ((key = [e nextObject])) {
        MMVimController *vc = [key pointerValue];
        NSArray *files = [openFilesDict objectForKey:key];
        [arguments setObject:files forKey:@"filenames"];

        if ([filenames count] == 0 && [files containsObject:firstFile]) {
            // Raise the window containing the first file that was already
            // open, and make sure that the tab containing that file is
            // selected.  Only do this when there are no more files to open,
            // otherwise sometimes the window with 'firstFile' will be raised,
            // other times it might be the window that will open with the files
            // in the 'filenames' array.
            //
            // NOTE: Raise window before passing arguments, otherwise the
            // selection will be lost when selectionRange is set.
            NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                                  firstFile, @"filename",
                                  [NSNumber numberWithInt:(int)layout], @"layout",
                                  nil];
            [vc sendMessage:SelectAndFocusOpenedFileMsgID data:[args dictionaryAsData]];
        }

        [vc passArguments:arguments];
    }

    // Add filenames to "Recent Files" menu, unless they are being edited
    // remotely (using ODB).
    if ([arguments objectForKey:@"remoteID"] == nil) {
        [[NSDocumentController sharedDocumentController]
                noteNewRecentFilePaths:filenames];
    }

    if ([filenames count] == 0)
        return YES; // No files left to open (all were already open)

    //
    // b) Open any remaining files
    //

    [arguments setObject:[NSNumber numberWithInt:(int)layout] forKey:@"layout"];
    [arguments setObject:filenames forKey:@"filenames"];
    // (Indicate that files should be opened from now on.)
    [arguments setObject:[NSNumber numberWithBool:NO] forKey:@"dontOpen"];

    MMVimController *vc;
    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        // Open files in an already open window.
        [[[vc windowController] window] makeKeyAndOrderFront:self];
        [vc passArguments:arguments];
        return YES;
    }

    BOOL openOk = YES;
    int numFiles = (int)[filenames count];
    if (MMLayoutWindows == layout && numFiles > 1) {
        // Open one file at a time in a new window, but don't open too many at
        // once (at most cap+1 windows will open).  If the user has increased
        // the preload cache size we'll take that as a hint that more windows
        // should be able to open at once.
        int cap = [self maxPreloadCacheSize] - 1;
        if (cap < 4) cap = 4;
        if (cap > numFiles) cap = numFiles;

        int i;
        for (i = 0; i < cap; ++i) {
            NSArray *a = [NSArray arrayWithObject:[filenames objectAtIndex:i]];
            [arguments setObject:a forKey:@"filenames"];

            // NOTE: We have to copy the args since we'll mutate them in the
            // next loop and the below call may retain the arguments while
            // waiting for a process to start.
            NSDictionary *args = [[arguments copy] autorelease];

            openOk = [self openVimControllerWithArguments:args];
            if (!openOk) break;
        }

        // Open remaining files in tabs in a new window.
        if (openOk && numFiles > cap) {
            NSRange range = { i, numFiles-cap };
            NSArray *a = [filenames subarrayWithRange:range];
            [arguments setObject:a forKey:@"filenames"];
            [arguments setObject:[NSNumber numberWithInt:MMLayoutTabs]
                          forKey:@"layout"];

            openOk = [self openVimControllerWithArguments:arguments];
        }
    } else {
        // Open all files at once.
        openOk = [self openVimControllerWithArguments:arguments];
    }

    return openOk;
}

- (void)refreshAllAppearances
{
    const NSUInteger count = [vimControllers count];
    for (unsigned i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [vc.windowController refreshApperanceMode];
    }
}

/// Refresh all Vim text views' fonts.
- (void)refreshAllFonts
{
    const NSUInteger count = [vimControllers count];
    for (unsigned i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [vc.windowController refreshFonts];
    }
}

/// Refresh all resize constraints based on smooth resize configurations
/// and resize the windows to match the constraints.
- (void)refreshAllResizeConstraints
{
    const NSUInteger count = [vimControllers count];
    for (unsigned i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [vc.windowController updateResizeConstraints:YES];
    }
}

/// Refresh all text views and re-render them, as well as updating their
/// cmdline alignment properties to make sure they are pinned properly.
- (void)refreshAllTextViews
{
    const NSUInteger count = [vimControllers count];
    for (unsigned i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [vc.windowController.vimView.textView updateCmdlineRow];
        vc.windowController.vimView.textView.needsDisplay = YES;
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(showWhatsNew:)) {
        return [MMWhatsNewController canOpen];
    }
    // For most of the actions defined in this class we do want them to always be
    // enabled since they are usually app functionality and independent of
    // each Vim's state.
    return YES;
}

/// Open a new Vim window, potentially taking from cached (if preload is used).
///
/// @param mode Determine whether to use clean mode or not. Preload will only
/// be used if using normal mode.
///
/// @param activate Activate the window after it's opened.
- (void)openNewWindow:(enum NewWindowMode)mode activate:(BOOL)activate
{
    if (activate)
        [self activateWhenNextWindowOpens];

    // A cached controller requires no loading times and results in the new
    // window popping up instantaneously.  If the cache is empty it may take
    // 1-2 seconds to start a new Vim process.
    MMVimController *vc = (mode == NewWindowNormal) ? [self takeVimControllerFromCache] : nil;
    if (vc) {
        [[vc backendProxy] acknowledgeConnection];
    } else {
        NSArray *args = (mode == NewWindowNormal) ? nil
            : (mode == NewWindowClean ? @[@"--clean"]
                                      : @[@"--clean", @"-u", @"NONE"]);
        [self launchVimProcessWithArguments:args workingDirectory:nil];
    }
}

- (IBAction)newWindow:(id)sender
{
    ASLogDebug(@"Open new window");
    [self openNewWindow:NewWindowNormal activate:NO];
}

- (IBAction)newWindowClean:(id)sender
{
    [self openNewWindow:NewWindowClean activate:NO];
}

- (IBAction)newWindowCleanNoDefaults:(id)sender
{
    [self openNewWindow:NewWindowCleanNoDefaults activate:NO];
}

- (IBAction)newWindowAndActivate:(id)sender
{
    [self openNewWindow:NewWindowNormal activate:YES];
}

- (IBAction)newWindowCleanAndActivate:(id)sender
{
    [self openNewWindow:NewWindowClean activate:YES];
}

- (IBAction)newWindowCleanNoDefaultsAndActivate:(id)sender
{
    [self openNewWindow:NewWindowCleanNoDefaults activate:YES];
}

- (IBAction)fileOpen:(id)sender
{
    ASLogDebug(@"Show file open panel");

    NSString *dir = nil;
    BOOL trackPwd = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMDialogsTrackPwdKey];
    if (trackPwd) {
        MMVimController *vc = [self keyVimController];
        if (vc) dir = [vc objectForVimStateKey:@"pwd"];
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:YES];
    [panel setCanChooseDirectories:YES];
    [panel setAccessoryView:showHiddenFilesView()];
    dir = [dir stringByExpandingTildeInPath];
    if (dir) {
        NSURL *dirURL = [NSURL fileURLWithPath:dir isDirectory:YES];
        if (dirURL)
            [panel setDirectoryURL:dirURL];
    }

    NSInteger result = [panel runModal];

#if (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10)
    if (NSModalResponseOK == result)
#else
    if (NSOKButton == result)
#endif
    {
        // NOTE: -[NSOpenPanel filenames] is deprecated on 10.7 so use
        // -[NSOpenPanel URLs] instead.  The downside is that we have to check
        // that each URL is really a path first.
        NSMutableArray *filenames = [NSMutableArray array];
        NSArray *urls = [panel URLs];
        NSUInteger i, count = [urls count];
        for (i = 0; i < count; ++i) {
            NSURL *url = [urls objectAtIndex:i];
            if ([url isFileURL]) {
                NSString *path = [url path];
                if (path)
                    [filenames addObject:path];
            }
        }

        if ([filenames count] > 0)
            [self application:NSApp openFiles:filenames];
    }
}

- (IBAction)selectNextWindow:(id)sender
{
    ASLogDebug(@"Select next window");

    NSUInteger i, count = [vimControllers count];
    if (!count) return;

    NSWindow *keyWindow = [NSApp keyWindow];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        if ([[[vc windowController] window] isEqual:keyWindow])
            break;
    }

    if (i < count) {
        if (++i >= count)
            i = 0;
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [[vc windowController] showWindow:self];
    }
}

- (IBAction)selectPreviousWindow:(id)sender
{
    ASLogDebug(@"Select previous window");

    NSUInteger i, count = [vimControllers count];
    if (!count) return;

    NSWindow *keyWindow = [NSApp keyWindow];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        if ([[[vc windowController] window] isEqual:keyWindow])
            break;
    }

    if (i < count) {
        if (i > 0) {
            --i;
        } else {
            i = count - 1;
        }
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [[vc windowController] showWindow:self];
    }
}

- (IBAction)orderFrontPreferencePanel:(id)sender
{
    ASLogDebug(@"Show preferences panel");
    [[MMPreferenceController sharedPrefsWindowController] showWindow:self];
}

- (IBAction)openWebsite:(id)sender
{
    ASLogDebug(@"Open MacVim website");
    [[NSWorkspace sharedWorkspace] openURL:
            [NSURL URLWithString:MMWebsiteString]];
}

- (IBAction)showWhatsNew:(id)sender
{
    ASLogDebug(@"Open What's New page");
    [MMWhatsNewController openSharedInstance];
}

- (IBAction)showVimHelp:(id)sender withCmd:(NSString *)cmd
{
    ASLogDebug(@"Open window with Vim help");
    // Open a new window with only the help window shown.
    [self launchVimProcessWithArguments:[NSArray arrayWithObjects:
                                    @"-c", cmd, @"-c", @":only", nil]
                       workingDirectory:nil];
}

- (IBAction)showVimHelp:(id)sender
{
    [self showVimHelp:sender withCmd:@":h gui_mac"];
}

- (IBAction)checkForUpdates:(id)sender
{
#if !DISABLE_SPARKLE
    // Check for updates for new versions manually.
    ASLogDebug(@"Check for software updates");
    [updater checkForUpdates:sender];
#endif
}

// Note that the zoomAll method does not appear to be called in modern macOS versions
// as NSApplication just handles it and directly calls each window's zoom:. It's
// difficult to trace through history to see when that happened as it's not really
// documented, so we are leaving this method around in case on older macOS
// versions it's useful.
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_13
- (IBAction)zoomAll:(id)sender
{
    // TODO ychin: check on 10.13 etc. This was depreacated post 10.14.
    ASLogDebug(@"Zoom all windows");
    [NSApp makeWindowsPerform:@selector(performZoom:) inOrder:YES];
}
#endif

- (IBAction)stayInFront:(id)sender
{
    ASLogDebug(@"Stay in Front");
    NSWindow *keyWindow = [NSApp keyWindow];
    [keyWindow setLevel:NSFloatingWindowLevel];
}

- (IBAction)stayInBack:(id)sender
{
    ASLogDebug(@"Stay in Back");
    NSWindow *keyWindow = [NSApp keyWindow];
    [keyWindow setLevel:kCGDesktopIconWindowLevel +1];
}

- (IBAction)stayLevelNormal:(id)sender
{
    ASLogDebug(@"Stay level normal");
    NSWindow *keyWindow = [NSApp keyWindow];
    [keyWindow setLevel:NSNormalWindowLevel];
}

- (IBAction)coreTextButtonClicked:(id)sender
{
    ASLogDebug(@"Toggle CoreText renderer");
    NSInteger renderer = MMRendererDefault;
    BOOL enable = ([sender state] == NSControlStateValueOn);

    if (enable) {
        renderer = MMRendererCoreText;
    }

    // Update the user default MMRenderer and synchronize the change so that
    // any new Vim process will pick up on the changed setting.
    CFPreferencesSetAppValue(
            (CFStringRef)MMRendererKey,
            (CFPropertyListRef)[NSNumber numberWithInt:(int)renderer],
            kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);

    ASLogInfo(@"Use renderer=%ld", renderer);

    // This action is called when the user clicks the "use CoreText renderer"
    // button in the advanced preferences pane.
    [self rebuildPreloadCache];
}

- (IBAction)loginShellButtonClicked:(id)sender
{
    ASLogDebug(@"Toggle login shell option");
    // This action is called when the user clicks the "use login shell" button
    // in the advanced preferences pane.
    [self rebuildPreloadCache];
}

- (IBAction)quickstartButtonClicked:(id)sender
{
    ASLogDebug(@"Toggle Quickstart option");
    if ([self maxPreloadCacheSize] > 0) {
        [self scheduleVimControllerPreloadAfterDelay:1.0];
        [self startWatchingVimDir];
    } else {
        [self cancelVimControllerPreloadRequests];
        [self clearPreloadCacheWithCount:-1];
        [self stopWatchingVimDir];
    }
}

- (MMVimController *)keyVimController
{
    NSWindow *keyWindow = [NSApp keyWindow];
    if (keyWindow) {
        NSUInteger i, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if ([[[vc windowController] window] isEqual:keyWindow])
                return vc;
        }
    }

    return nil;
}

- (unsigned long)connectBackend:(byref in id <MMBackendProtocol>)proxy pid:(int)pid
{
    ASLogDebug(@"pid=%d", pid);

    [(NSDistantObject*)proxy setProtocolForProxy:@protocol(MMBackendProtocol)];

    // NOTE: Allocate the vim controller now but don't add it to the list of
    // controllers since this is a distributed object call and as such can
    // arrive at unpredictable times (e.g. while iterating the list of vim
    // controllers).
    // (What if input arrives before the vim controller is added to the list of
    // controllers?  This should not be a problem since the input isn't
    // processed immediately (see processInput:forIdentifier:).)
    // Also, since the app may be multithreaded (e.g. as a result of showing
    // the open panel) we have to ensure this call happens on the main thread,
    // else there is a race condition that may lead to a crash.
    MMVimController *vc = [[MMVimController alloc] initWithBackend:proxy
                                                               pid:pid];
    [self performSelectorOnMainThread:@selector(addVimController:)
                           withObject:vc
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObject:
                                       NSDefaultRunLoopMode]];

    [vc release];

    return [vc vimControllerId];
}

- (oneway void)processInput:(in bycopy NSArray *)queue
              forIdentifier:(unsigned long)identifier
{
    // NOTE: Input is not handled immediately since this is a distributed
    // object call and as such can arrive at unpredictable times.  Instead,
    // queue the input and process it when the run loop is updated.

    if (!(queue && identifier)) {
        ASLogWarn(@"Bad input for identifier=%lu", identifier);
        return;
    }

    ASLogDebug(@"QUEUE for identifier=%lu: <<< %@>>>", identifier,
               debugStringForMessageQueue(queue));

    NSNumber *key = [NSNumber numberWithUnsignedLong:identifier];
    NSArray *q = [inputQueues objectForKey:key];
    if (q) {
        q = [q arrayByAddingObjectsFromArray:queue];
        [inputQueues setObject:q forKey:key];
    } else {
        [inputQueues setObject:queue forKey:key];
    }

    // NOTE: We must use "event tracking mode" as well as "default mode",
    // otherwise the input queue will not be processed e.g. during live
    // resizing.
    // Also, since the app may be multithreaded (e.g. as a result of showing
    // the open panel) we have to ensure this call happens on the main thread,
    // else there is a race condition that may lead to a crash.
    [self performSelectorOnMainThread:@selector(processInputQueues:)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObjects:
                                       NSDefaultRunLoopMode,
                                       NSEventTrackingRunLoopMode, nil]];
}

- (NSArray *)serverList
{
    NSMutableArray *array = [NSMutableArray array];

    NSUInteger i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        if ([controller serverName])
            [array addObject:[controller serverName]];
    }

    return array;
}

// Begin NSUserInterfaceItemSearching implementation
- (NSArray<NSString *> *)localizedTitlesForItem:(id)item
{
    return item;
}

/// Invoked when user typed on the help menu search bar. Will parse doc tags
/// and search among them for the search string and return the match items.
- (void)searchForItemsWithSearchString:(NSString *)searchString
                           resultLimit:(NSInteger)resultLimit
                    matchedItemHandler:(void (^)(NSArray *items))handleMatchedItems
{
    // Search documentation tags and provide the results in a pair of (file
    // name, tag name). Currently lazily parse the Vim's doc tags, and reuse
    // that in future searches.
    //
    // Does not support plugins for now, as different Vim instances could have
    // different plugins loaded. Theoretically it's possible to query the
    // current Vim instance for what plugins are loaded and the tags associated
    // with them but it's tricky especially since this function is not invoked
    // on the main thread. Just providing Vim's builtin docs should be mostly
    // good enough.

    static BOOL parsed = NO;
    static NSMutableArray *parsedLineComponents = nil;

    @synchronized (self) {
        if (!parsed) {
            parsedLineComponents = [[NSMutableArray alloc]init];
            
            NSString *tagsFilePath = [[[NSBundle mainBundle] resourcePath]
                                      stringByAppendingPathComponent:@"vim/runtime/doc/tags"];
            NSString *fileContent = [NSString stringWithContentsOfFile:tagsFilePath encoding:NSUTF8StringEncoding error:NULL];
            NSArray *lines = [fileContent componentsSeparatedByString:@"\n"];
            
            for (NSString *line in lines) {
                NSArray<NSString *> *components = [line componentsSeparatedByString:@"\t"];
                if ([components count] < 2) {
                    continue;
                }
                [parsedLineComponents addObject:components];
            }
            
            parsed = YES;
        }
    }

    // Use a simple search algorithm where the string is split by whitespace and each word has to match
    // substring in the tag. Don't do fuzzy matching or regex for simplicity for now.
    NSArray<NSString *> *searchStrings = [searchString componentsSeparatedByString:@" "];

    NSMutableArray *ret = [[[NSMutableArray alloc]init] autorelease];
    for (NSArray<NSString *> *line in parsedLineComponents) {
        BOOL found = YES;
        for (NSString *curSearchString in searchStrings) {
            if (![line[0] localizedCaseInsensitiveContainsString:curSearchString]) {
                found = NO;
                break;
            }
        }
        if (found) {
            // We flip the ordering because we want it to look like "file_name.txt > tag_name" in the results.
            NSArray *foundObject = @[line[1], line[0]];
            
            if ([searchStrings count] == 1 && [searchString localizedCaseInsensitiveCompare:line[0]] == NSOrderedSame) {
                // Exact match has highest priority.
                [ret insertObject:foundObject atIndex:0];
            }
            else {
                // Don't do any other prioritization for now. May add more sophisticated sorting/heuristics
                // in the future.
                [ret addObject:foundObject];
            }
        }
    }

    // Return the results to callback.
    handleMatchedItems(ret);
}

/// Invoked when user clicked on a Help menu item for a documentation tag
/// previously returned by searchForItemsWithSearchString.
- (void)performActionForItem:(id)item
{
    // When opening a help page, either open a new Vim instance, or reuse the
    // existing one.
    MMVimController *vimController = [self keyVimController];
    if (vimController == nil) {
        [self showVimHelp:self withCmd:[NSString stringWithFormat:
                                        @":help %@", item[1]]];
        return;
    }

    // Vim is already open. We want to send it a message to open help. However,
    // we're using `addVimInput`, which always treats input like "<Up>" as a key
    // while we want to type it literally. The only way to do so is to manually
    // split it up and concatenate the results together and pass it to :execute.
    NSString *helpStr = item[1];

    NSMutableString *cmd = [NSMutableString stringWithCapacity:40 + helpStr.length];
    [cmd setString:@"<C-\\><C-N>:exe 'help "];

    NSArray<NSString*> *splitComponents = [helpStr componentsSeparatedByString:@"<"];
    for (NSUInteger i = 0; i < splitComponents.count; i++) {
        if (i != 0) {
            [cmd appendString:@"<'..'"];
        }
        NSString *component = splitComponents[i];
        component = [component stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
        [cmd appendString:component];
    }
    [cmd appendString:@"'<CR>"];
    [vimController addVimInput:cmd];
}
// End NSUserInterfaceItemSearching

@end // MMAppController




@implementation MMAppController (MMServices)

- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error
{
    if (![[pboard types] containsObject:NSPasteboardTypeString]) {
        ASLogNotice(@"Pasteboard contains no NSPasteboardTypeString");
        return;
    }

    ASLogInfo(@"Open new window containing current selection");

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        [vc sendMessage:AddNewTabMsgID data:nil];
        [vc dropString:[pboard stringForType:NSPasteboardTypeString]];
    } else {
        // Save the text, open a new window, and paste the text when the next
        // window opens.  (If this is called several times in a row, then all
        // but the last call may be ignored.)
        if (openSelectionString) [openSelectionString release];
        openSelectionString = [[pboard stringForType:NSPasteboardTypeString] copy];

        [self newWindow:self];
    }
}

- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error
{
    if (![[pboard types] containsObject:NSPasteboardTypeString]) {
        ASLogNotice(@"Pasteboard contains no NSPasteboardTypeString");
        return;
    }

    // TODO: Parse multiple filenames and create array with names.
    NSString *string = [pboard stringForType:NSPasteboardTypeString];
    string = [string stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    string = [string stringByStandardizingPath];

    ASLogInfo(@"Open new window with selected file: %@", string);

    NSArray *filenames = [self filterFilesAndNotify:
            [NSArray arrayWithObject:string]];
    if ([filenames count] == 0)
        return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        [vc dropFiles:filenames forceOpen:YES];
    } else {
        [self openFiles:filenames withArguments:nil];
    }
}

- (void)newFileHere:(NSPasteboard *)pboard userData:(NSString *)userData
              error:(NSString **)error
{
    NSArray<NSString *> *filenames = extractPasteboardFilenames(pboard);
    if (filenames == nil || filenames.count == 0)
        return;
    NSString *path = [filenames lastObject];

    BOOL dirIndicator;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path
                                              isDirectory:&dirIndicator]) {
        ASLogNotice(@"Invalid path. Cannot open new document at: %@", path);
        return;
    }

    ASLogInfo(@"Open new file at path=%@", path);

    if (!dirIndicator)
        path = [path stringByDeletingLastPathComponent];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                              path, @"path",
                              nil];
        [vc sendMessage:NewFileHereMsgID data:[args dictionaryAsData]];
    } else {
        [self launchVimProcessWithArguments:nil workingDirectory:path];
    }
}

@end // MMAppController (MMServices)




@implementation MMAppController (Private)

/// Initializes the Sparkle updater and show a "What's New" page if needed.
/// Can be called more than once, but later calls will be silently ignored.
/// This should be called after the initial untitled window is shown to make
/// sure the updater/"What's New" windows can be shown on top of it.
- (void)startUpdaterAndWhatsNewPage
{
    static BOOL started = NO;
    if (!started) {
#if !DISABLE_SPARKLE && !USE_SPARKLE_1
        [updater startUpdater];
#endif

        if (shouldShowWhatsNewPage) {
            // Schedule it to be run later to make sure it will show up on top
            // of the new untitled window.
            [MMWhatsNewController performSelectorOnMainThread:@selector(openSharedInstance) withObject:nil waitUntilDone:NO];
        }

        started = YES;
    }
}

- (MMVimController *)topmostVimController
{
    // Find the topmost visible window which has an associated vim controller
    // as follows:
    //
    // 1. Search through ordered windows as determined by NSApp.  Unfortunately
    //    this method can fail, e.g. if a full-screen window is on another
    //    "Space" (in this case NSApp returns no windows at all), so we have to
    //    fall back on ...
    // 2. Search through all Vim controllers and return the first visible
    //    window.

    NSEnumerator *e = [[NSApp orderedWindows] objectEnumerator];
    id window;
    while ((window = [e nextObject]) && [window isVisible]) {
        NSUInteger i, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if ([[[vc windowController] window] isEqual:window])
                return vc;
        }
    }

    NSUInteger i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        if ([[[vc windowController] window] isVisible]) {
            return vc;
        }
    }

    return nil;
}

- (int)launchVimProcessWithArguments:(NSArray *)args
                    workingDirectory:(NSString *)cwd
{
    int pid = -1;
    NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"Vim"];

    if (!path) {
        ASLogCrit(@"Vim executable could not be found inside app bundle!");
        return -1;
    }

    // Change current working directory so that the child process picks it up.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *restoreCwd = nil;
    if (cwd) {
        restoreCwd = [fm currentDirectoryPath];
        [fm changeCurrentDirectoryPath:cwd];
    }

    NSArray *taskArgs = [NSArray arrayWithObjects:@"-g", @"-f", nil];
    if (args)
        taskArgs = [taskArgs arrayByAddingObjectsFromArray:args];

    BOOL useLoginShell = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMLoginShellKey];
    if (useLoginShell) {
        // Run process with a login shell, roughly:
        //   echo "exec Vim -g -f args" | ARGV0=-`basename $SHELL` $SHELL [-l]
        pid = [self executeInLoginShell:path arguments:taskArgs];
    } else {
        // Run process directly:
        //   Vim -g -f args
        NSTask *task = [NSTask launchedTaskWithLaunchPath:path
                                                arguments:taskArgs];
        pid = task ? [task processIdentifier] : -1;
    }

    if (-1 != pid) {
        // The 'pidArguments' dictionary keeps arguments to be passed to the
        // process when it connects (this is in contrast to arguments which are
        // passed on the command line, like '-f' and '-g').
        // NOTE: If there are no arguments to pass we still add a null object
        // so that we can use this dictionary to check if there are any
        // processes loading.
        NSNumber *pidKey = [NSNumber numberWithInt:pid];
        if (![pidArguments objectForKey:pidKey])
            [pidArguments setObject:[NSNull null] forKey:pidKey];
    } else {
        ASLogWarn(@"Failed to launch Vim process: args=%@, useLoginShell=%d",
                  args, useLoginShell);
    }

    // Now that child has launched, restore the current working directory.
    if (restoreCwd)
        [fm changeCurrentDirectoryPath:restoreCwd];

    return pid;
}

- (NSArray *)filterFilesAndNotify:(NSArray *)filenames
{
    // Go trough 'filenames' array and make sure each file exists.  Present
    // warning dialog if some file was missing.

    NSString *firstMissingFile = nil;
    NSMutableArray *files = [NSMutableArray array];
    NSUInteger i, count = [filenames count];

    for (i = 0; i < count; ++i) {
        NSString *name = [filenames objectAtIndex:i];
        if ([[NSFileManager defaultManager] fileExistsAtPath:name]) {
            [files addObject:name];
        } else if (!firstMissingFile) {
            firstMissingFile = name;
        }
    }

    if (firstMissingFile) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"OK",
                @"Dialog button")];

        NSString *text;
        if ([files count] >= count-1) {
            [alert setMessageText:NSLocalizedString(@"File not found",
                    @"File not found dialog, title")];
            text = [NSString stringWithFormat:NSLocalizedString(
                    @"Could not open file with name %@.",
                    @"File not found dialog, text"), firstMissingFile];
        } else {
            [alert setMessageText:NSLocalizedString(@"Multiple files not found",
                    @"File not found dialog, title")];
            text = [NSString stringWithFormat:NSLocalizedString(
                    @"Could not open file with name %@, and %u other files.",
                    @"File not found dialog, text"),
                firstMissingFile, (unsigned int)(count-[files count]-1)];
        }

        [alert setInformativeText:text];
        [alert setAlertStyle:NSAlertStyleWarning];

        [alert runModal];
        [alert release];

        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
    }

    return files;
}

- (NSArray *)filterOpenFiles:(NSArray *)filenames
               openFilesDict:(NSDictionary **)openFiles
{
    // Filter out any files in the 'filenames' array that are open and return
    // all files that are not already open.  On return, the 'openFiles'
    // parameter (if non-nil) will point to a dictionary of open files, indexed
    // by Vim controller.

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSMutableArray *files = [filenames mutableCopy];

    // TODO: Escape special characters in 'files'?
    NSString *expr = [NSString stringWithFormat:
            @"map([\"%@\"],\"bufloaded(v:val)\")",
            [files componentsJoinedByString:@"\",\""]];

    NSUInteger i, count = [vimControllers count];
    for (i = 0; i < count && [files count] > 0; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];

        // Query Vim for which files in the 'files' array are open.
        NSString *eval = [vc evaluateVimExpression:expr];
        if (!eval) continue;

        NSIndexSet *idxSet = [NSIndexSet indexSetWithVimList:eval];
        if ([idxSet count] > 0) {
            [dict setObject:[files objectsAtIndexes:idxSet]
                     forKey:[NSValue valueWithPointer:vc]];

            // Remove all the files that were open in this Vim process and
            // create a new expression to evaluate.
            [files removeObjectsAtIndexes:idxSet];
            expr = [NSString stringWithFormat:
                    @"map([\"%@\"],\"bufloaded(v:val)\")",
                    [files componentsJoinedByString:@"\",\""]];
        }
    }

    if (openFiles != nil)
        *openFiles = dict;

    return [files autorelease];
}

#if MM_HANDLE_XCODE_MOD_EVENT
- (void)handleXcodeModEvent:(NSAppleEventDescriptor *)event
                 replyEvent:(NSAppleEventDescriptor *)reply
{
#if 0
    // Xcode sends this event to query MacVim which open files have been
    // modified.
    ASLogDebug(@"reply:%@", reply);
    ASLogDebug(@"event:%@", event);

    NSEnumerator *e = [vimControllers objectEnumerator];
    id vc;
    while ((vc = [e nextObject])) {
        DescType type = [reply descriptorType];
        unsigned len = [[type data] length];
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&type length:sizeof(DescType)];
        [data appendBytes:&len length:sizeof(unsigned)];
        [data appendBytes:[reply data] length:len];

        [vc sendMessage:XcodeModMsgID data:data];
    }
#endif
}
#endif

+ (NSDictionary*)parseOpenURL:(NSURL*)url
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // Parse query ("url=file://...&line=14") into a dictionary
    NSArray *queries = [[url query] componentsSeparatedByString:@"&"];
    NSEnumerator *enumerator = [queries objectEnumerator];
    NSString *param;
    while ((param = [enumerator nextObject])) {
        // query: <field>=<value>
        NSArray *arr = [param componentsSeparatedByString:@"="];
        if ([arr count] == 2) {
            // parse field
            NSString *f = [arr objectAtIndex:0];
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_11
            f = [f stringByRemovingPercentEncoding];
#else
            f = [f stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
#endif

            // parse value
            NSString *v = [arr objectAtIndex:1];

            // We need to decode the parameters here because most URL
            // parsers treat the query component as needing to be decoded
            // instead of treating it as is. It does mean that a link to
            // open file "/tmp/file name.txt" will be
            // mvim://open?url=file:///tmp/file%2520name.txt to encode a
            // URL of file:///tmp/file%20name.txt. This double-encoding is
            // intentional to follow the URL spec.
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_11
            v = [v stringByRemovingPercentEncoding];
#else
            v = [v stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
#endif

            if ([f isEqualToString:@"url"]) {
                // Since the URL scheme uses a double-encoding due to a
                // file:// URL encoded in another mvim: one, existing tools
                // like iTerm2 could sometimes erroneously only do a single
                // encode. To maximize compatiblity, we re-encode invalid
                // characters if we detect them as they would not work
                // later on when we pass this string to URLWithString.
                //
                // E.g. mvim://open?uri=file:///foo%20bar => "file:///foo bar"
                // which is not a valid URL, so we re-encode it to
                // file:///foo%20bar here. The only important case is to
                // not touch the "%" character as it introduces ambiguity
                // and the re-encoding is a nice compatibility feature, but
                // the canonical form should be double-encoded, i.e.
                // mvim://open?uri=file:///foo%2520bar
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_10
                if (AVAILABLE_MAC_OS(10, 10)) {
                    NSMutableCharacterSet *charSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"%"];
                    [charSet formUnionWithCharacterSet:NSCharacterSet.URLHostAllowedCharacterSet];
                    [charSet formUnionWithCharacterSet:NSCharacterSet.URLPathAllowedCharacterSet];
                    v = [v stringByAddingPercentEncodingWithAllowedCharacters:charSet];
                }
#endif
            }

            [dict setValue:v forKey:f];
        }
    }
    return dict;
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event
               replyEvent:(NSAppleEventDescriptor *)reply
{
    NSURL *url = [NSURL URLWithString:[[event
                                        paramDescriptorForKeyword:keyDirectObject]
                                        stringValue]];

    // We try to be compatible with TextMate's URL scheme here, as documented
    // at https://macromates.com/blog/2007/the-textmate-url-scheme/ . Currently,
    // this means that:
    //
    // The format is: mvim://open?<arguments> where arguments can be:
    //
    // * url — the actual file to open (i.e. a file://… URL), if you leave
    //         out this argument, the frontmost document is implied.
    // * line — line number to go to (one based).
    // * column — column number to go to (one based).
    //
    // Example: mvim://open?url=file:///etc/profile&line=20

    if ([[url host] isEqualToString:@"open"]) {
        // Parse the URL and process it
        NSDictionary *dict = [MMAppController parseOpenURL:url];

        // Actually open the file.
        NSString *file = [dict objectForKey:@"url"];
        if (file != nil) {
            NSURL *fileUrl = [NSURL URLWithString:file];
            if ([fileUrl isFileURL]) {
                NSString *filePath = [fileUrl path];
                // Only opens files that already exist.
                if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
                    NSArray *filenames = [NSArray arrayWithObject:filePath];

                    // Look for the line and column options.
                    NSDictionary *args = nil;
                    NSString *line = [dict objectForKey:@"line"];
                    if (line) {
                        NSString *column = [dict objectForKey:@"column"];
                        if (column)
                            args = [NSDictionary dictionaryWithObjectsAndKeys:
                                    line, @"cursorLine",
                                    column, @"cursorColumn",
                                    nil];
                        else
                            args = [NSDictionary dictionaryWithObject:line
                                                               forKey:@"cursorLine"];
                    }

                    [self openFiles:filenames withArguments:args];
                } else {
                    NSAlert *alert = [[NSAlert alloc] init];
                    [alert addButtonWithTitle:NSLocalizedString(@"OK",
                        @"Dialog button")];

                    [alert setMessageText:NSLocalizedString(@"Bad file path",
                        @"Bad file path dialog, title")];
                    [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(
                        @"Cannot open file path \"%@\"",
                        @"Bad file path dialog, text"),
                        filePath]];

                    [alert setAlertStyle:NSAlertStyleWarning];
                    [alert runModal];
                    [alert release];
                }
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert addButtonWithTitle:NSLocalizedString(@"OK",
                    @"Dialog button")];

                [alert setMessageText:NSLocalizedString(@"Invalid File URL",
                    @"Unknown Fie URL dialog, title")];
                [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(
                    @"Unknown file URL in \"%@\"",
                    @"Unknown file URL dialog, text"),
                    file]];

                [alert setAlertStyle:NSAlertStyleWarning];
                [alert runModal];
                [alert release];
            }
        }
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"OK",
            @"Dialog button")];

        [alert setMessageText:NSLocalizedString(@"Unknown URL Scheme",
            @"Unknown URL Scheme dialog, title")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(
            @"This version of MacVim does not support \"%@\""
            @" in its URL scheme.",
            @"Unknown URL Scheme dialog, text"),
            [url host]]];

        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        [alert release];
    }
}

- (NSMutableDictionary *)extractArgumentsFromOdocEvent:
    (NSAppleEventDescriptor *)desc
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // 1. Extract ODB parameters (if any)
    NSAppleEventDescriptor *odbdesc = desc;
    if (![odbdesc paramDescriptorForKeyword:keyFileSender]) {
        // The ODB paramaters may hide inside the 'keyAEPropData' descriptor.
        odbdesc = [odbdesc paramDescriptorForKeyword:keyAEPropData];
        if (![odbdesc paramDescriptorForKeyword:keyFileSender])
            odbdesc = nil;
    }

    if (odbdesc) {
        NSAppleEventDescriptor *p =
                [odbdesc paramDescriptorForKeyword:keyFileSender];
        if (p)
            [dict setObject:[NSNumber numberWithUnsignedInt:[p typeCodeValue]]
                     forKey:@"remoteID"];

        p = [odbdesc paramDescriptorForKeyword:keyFileCustomPath];
        if (p)
            [dict setObject:[p stringValue] forKey:@"remotePath"];

        p = [odbdesc paramDescriptorForKeyword:keyFileSenderToken];
        if (p) {
            [dict setObject:[NSNumber numberWithUnsignedLong:[p descriptorType]]
                     forKey:@"remoteTokenDescType"];
            [dict setObject:[p data] forKey:@"remoteTokenData"];
        }
    }

    // 2. Extract Xcode parameters (if any)
    NSAppleEventDescriptor *xcodedesc =
            [desc paramDescriptorForKeyword:keyAEPosition];
    if (xcodedesc) {
        NSRange range;
        NSData *data = [xcodedesc data];
        NSUInteger length = [data length];

        if (length == sizeof(MMXcodeSelectionRange)) {
            MMXcodeSelectionRange *sr = (MMXcodeSelectionRange*)[data bytes];
            ASLogDebug(@"Xcode selection range (%d,%d,%d,%d,%d,%d)",
                    sr->unused1, sr->lineNum, sr->startRange, sr->endRange,
                    sr->unused2, sr->theDate);

            if (sr->lineNum < 0) {
                // Should select a range of characters.
                range.location = sr->startRange + 1;
                range.length = sr->endRange > sr->startRange
                             ? sr->endRange - sr->startRange : 1;
            } else {
                // Should only move cursor to a line.
                range.location = sr->lineNum + 1;
                range.length = 0;
            }

            [dict setObject:NSStringFromRange(range) forKey:@"selectionRange"];
        } else {
            ASLogErr(@"Xcode selection range size mismatch! got=%ld "
                     "expected=%ld", length, sizeof(MMXcodeSelectionRange));
        }
    }

    // 3. Extract Spotlight search text (if any)
    NSAppleEventDescriptor *spotlightdesc = 
            [desc paramDescriptorForKeyword:keyAESearchText];
    if (spotlightdesc) {
        NSString *s = [[spotlightdesc stringValue]
                                            stringBySanitizingSpotlightSearch];
        if (s && [s length] > 0)
            [dict setObject:s forKey:@"searchText"];
    }

    return dict;
}

- (void)scheduleVimControllerPreloadAfterDelay:(NSTimeInterval)delay
{
    [self performSelector:@selector(preloadVimController:)
               withObject:nil
               afterDelay:delay];
}

- (void)cancelVimControllerPreloadRequests
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
            selector:@selector(preloadVimController:)
              object:nil];
}

- (void)preloadVimController:(id)sender
{
    // We only allow preloading of one Vim process at a time (to avoid hogging
    // CPU), so schedule another preload in a little while if necessary.
    if (-1 != preloadPid) {
        [self scheduleVimControllerPreloadAfterDelay:2];
        return;
    }

    if ([cachedVimControllers count] >= [self maxPreloadCacheSize])
        return;

    preloadPid = [self launchVimProcessWithArguments:
                                    [NSArray arrayWithObject:@"--mmwaitforack"]
                                    workingDirectory:nil];

    // This method is kicked off via FSEvents, so if MacVim is in the
    // background, the runloop won't bother flushing the autorelease pool.
    // Triggering an NSEvent works around this.
    // http://www.mikeash.com/pyblog/more-fun-with-autorelease.html
    NSEvent* event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:0
                                           data1:0
                                           data2:0];
    [NSApp postEvent:event atStart:NO];
}

- (int)maxPreloadCacheSize
{
    // The maximum number of Vim processes to keep in the cache can be
    // controlled via the user default "MMPreloadCacheSize".
    NSInteger maxCacheSize = [[NSUserDefaults standardUserDefaults]
            integerForKey:MMPreloadCacheSizeKey];
    if (maxCacheSize < 0) maxCacheSize = 0;
    else if (maxCacheSize > 10) maxCacheSize = 10;

    return (int)maxCacheSize;
}

- (MMVimController *)takeVimControllerFromCache
{
    // NOTE: After calling this message the backend corresponding to the
    // returned vim controller must be sent an acknowledgeConnection message,
    // else the vim process will be stuck.
    //
    // This method may return nil even though the cache might be non-empty; the
    // caller should handle this by starting a new Vim process.

    NSUInteger i, count = [cachedVimControllers count];
    if (0 == count) return nil;

    // Locate the first Vim controller with up-to-date rc-files sourced.
    NSDate *rcDate = [self rcFilesModificationDate];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [cachedVimControllers objectAtIndex:i];
        NSDate *date = [vc creationDate];
        if ([date compare:rcDate] != NSOrderedAscending)
            break;
    }

    if (i > 0) {
        // Clear out cache entries whose vimrc/gvimrc files were sourced before
        // the latest modification date for those files.  This ensures that the
        // latest rc-files are always sourced for new windows.
        [self clearPreloadCacheWithCount:(int)i];
    }

    if ([cachedVimControllers count] == 0) {
        [self scheduleVimControllerPreloadAfterDelay:2.0];
        return nil;
    }

    MMVimController *vc = [cachedVimControllers objectAtIndex:0];
    [vimControllers addObject:vc];
    [cachedVimControllers removeObjectAtIndex:0];
    [vc setIsPreloading:NO];

    // If the Vim process has finished loading then the window will displayed
    // now, otherwise it will be displayed when the OpenWindowMsgID message is
    // received.
    [[vc windowController] presentWindow:nil];

    // Since we've taken one controller from the cache we take the opportunity
    // to preload another.
    [self scheduleVimControllerPreloadAfterDelay:1];

    return vc;
}

- (void)clearPreloadCacheWithCount:(int)count
{
    // Remove the 'count' first entries in the preload cache.  It is assumed
    // that objects are added/removed from the cache in a FIFO manner so that
    // this effectively clears the 'count' oldest entries.
    // If 'count' is negative, then the entire cache is cleared.

    if ([cachedVimControllers count] == 0 || count == 0)
        return;

    if (count < 0)
        count = (int)[cachedVimControllers count];

    // Make sure the preloaded Vim processes get killed or they'll just hang
    // around being useless until MacVim is terminated.
    NSEnumerator *e = [cachedVimControllers objectEnumerator];
    MMVimController *vc;
    int n = count;
    while ((vc = [e nextObject]) && n-- > 0) {
        [[NSNotificationCenter defaultCenter] removeObserver:vc];
        [vc sendMessage:TerminateNowMsgID data:nil];

        // Since the preloaded processes were killed "prematurely" we have to
        // manually tell them to cleanup (it is not enough to simply release
        // them since deallocation and cleanup are separated).
        [vc cleanup];
    }

    n = count;
    while (n-- > 0 && [cachedVimControllers count] > 0)
        [cachedVimControllers removeObjectAtIndex:0];

    // There is a small delay before the Vim process actually exits so wait a
    // little before trying to reap the child process.  If the process still
    // hasn't exited after this wait it won't be reaped until the next time
    // reapChildProcesses: is called (but this should be harmless).
    [self performSelector:@selector(reapChildProcesses:)
               withObject:nil
               afterDelay:0.1];
}

- (void)rebuildPreloadCache
{
    if ([self maxPreloadCacheSize] > 0) {
        [self clearPreloadCacheWithCount:-1];
        [self cancelVimControllerPreloadRequests];
        [self scheduleVimControllerPreloadAfterDelay:1.0];
    }
}

- (NSDate *)rcFilesModificationDate
{
    // Check modification dates for ~/.vimrc and ~/.gvimrc and return the
    // latest modification date.  If ~/.vimrc does not exist, check ~/_vimrc
    // and similarly for gvimrc.
    // Returns distantPath if no rc files were found.

    NSDate *date = [NSDate distantPast];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *path = [@"~/.vimrc" stringByExpandingTildeInPath];
    NSDictionary *attr = [fm attributesOfItemAtPath:path error:NULL];
    if (!attr) {
        path = [@"~/_vimrc" stringByExpandingTildeInPath];
        attr = [fm attributesOfItemAtPath:path error:NULL];
    }
    NSDate *modDate = [attr objectForKey:NSFileModificationDate];
    if (modDate)
        date = modDate;

    path = [@"~/.gvimrc" stringByExpandingTildeInPath];
    attr = [fm attributesOfItemAtPath:path error:NULL];
    if (!attr) {
        path = [@"~/_gvimrc" stringByExpandingTildeInPath];
        attr = [fm attributesOfItemAtPath:path error:NULL];
    }
    modDate = [attr objectForKey:NSFileModificationDate];
    if (modDate)
        date = [date laterDate:modDate];

    return date;
}

- (BOOL)openVimControllerWithArguments:(NSDictionary *)arguments
{
    MMVimController *vc = [self takeVimControllerFromCache];
    if (vc) {
        // Open files in a new window using a cached vim controller.  This
        // requires virtually no loading time so the new window will pop up
        // instantaneously.
        [vc passArguments:arguments];
        [[vc backendProxy] acknowledgeConnection];
    } else {
        NSArray *cmdline = nil;
        NSString *cwd = [self workingDirectoryForArguments:arguments];
        arguments = [self convertVimControllerArguments:arguments
                                          toCommandLine:&cmdline];
        int pid = [self launchVimProcessWithArguments:cmdline
                                     workingDirectory:cwd];
        if (-1 == pid)
            return NO;

        // TODO: If the Vim process fails to start, or if it changes PID,
        // then the memory allocated for these parameters will leak.
        // Ensure that this cannot happen or somehow detect it.

        if ([arguments count] > 0)
            [pidArguments setObject:arguments
                             forKey:[NSNumber numberWithInt:pid]];
    }

    return YES;
}

- (void)activateWhenNextWindowOpens
{
    ASLogDebug(@"Activate MacVim when next window opens");
    shouldActivateWhenNextWindowOpens = YES;
}

- (void)startWatchingVimDir
{
    if (fsEventStream)
        return;

    NSString *path = [@"~/.vim" stringByExpandingTildeInPath];
    NSArray *pathsToWatch = [NSArray arrayWithObject:path];

    fsEventStream = FSEventStreamCreate(NULL, &fsEventCallback, NULL,
            (CFArrayRef)pathsToWatch, kFSEventStreamEventIdSinceNow,
            MMEventStreamLatency, kFSEventStreamCreateFlagNone);

    FSEventStreamSetDispatchQueue(fsEventStream, dispatch_get_main_queue());

    FSEventStreamStart(fsEventStream);
    ASLogDebug(@"Started FS event stream");
}

- (void)stopWatchingVimDir
{
    if (fsEventStream) {
        FSEventStreamStop(fsEventStream);
        FSEventStreamInvalidate(fsEventStream);
        FSEventStreamRelease(fsEventStream);
        fsEventStream = NULL;
        ASLogDebug(@"Stopped FS event stream");
    }
}

- (void)handleFSEvent
{
    [self clearPreloadCacheWithCount:-1];

    // Several FS events may arrive in quick succession so make sure to cancel
    // any previous preload requests before making a new one.
    [self cancelVimControllerPreloadRequests];
    [self scheduleVimControllerPreloadAfterDelay:0.5];
}

- (int)executeInLoginShell:(NSString *)path arguments:(NSArray *)args
{
    // Start a login shell and execute the command 'path' with arguments 'args'
    // in the shell.  This ensures that user environment variables are set even
    // when MacVim was started from the Finder.

    int pid = -1;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // Determine which shell to use to execute the command.  The user
    // may decide which shell to use by setting a user default or the
    // $SHELL environment variable.
    NSString *shell = [ud stringForKey:MMLoginShellCommandKey];
    if (!shell || [shell length] == 0)
        shell = [[[NSProcessInfo processInfo] environment]
            objectForKey:@"SHELL"];
    if (!shell)
        shell = @"/bin/bash";

    // Bash needs the '-l' flag to launch a login shell.  The user may add
    // flags by setting a user default.
    NSString *shellArgument = [ud stringForKey:MMLoginShellArgumentKey];
    if (!shellArgument || [shellArgument length] == 0) {
        if ([[shell lastPathComponent] isEqual:@"bash"])
            shellArgument = @"-l";
        else
            shellArgument = nil;
    }

    // Build input string to pipe to the login shell.
    NSMutableString *input = [NSMutableString stringWithFormat:
            @"exec \"%@\"", path];
    if (args) {
        // Append all arguments, making sure they are properly quoted, even
        // when they contain single quotes.
        NSEnumerator *e = [args objectEnumerator];
        id obj;

        while ((obj = [e nextObject])) {
            NSMutableString *arg = [NSMutableString stringWithString:obj];
            [arg replaceOccurrencesOfString:@"'" withString:@"'\"'\"'"
                                    options:NSLiteralSearch
                                      range:NSMakeRange(0, [arg length])];
            [input appendFormat:@" '%@'", arg];
        }
    }

    // Build the argument vector used to start the login shell.
    NSString *shellArg0 = [NSString stringWithFormat:@"-%@",
             [shell lastPathComponent]];
    char *shellArgv[3] = { (char *)[shellArg0 UTF8String], NULL, NULL };
    if (shellArgument)
        shellArgv[1] = (char *)[shellArgument UTF8String];

    // Get the C string representation of the shell path before the fork since
    // we must not call Foundation functions after a fork.
    const char *shellPath = [shell fileSystemRepresentation];

    // Fork and execute the process.
    int ds[2];
    if (pipe(ds)) return -1;

    pid = fork();
    if (pid == -1) {
        return -1;
    } else if (pid == 0) {
        // Child process

        if (close(ds[1]) == -1) exit(255);
        if (dup2(ds[0], 0) == -1) exit(255);

        // Without the following call warning messages like this appear on the
        // console:
        //     com.apple.launchd[69] : Stray process with PGID equal to this
        //                             dead job: PID 1589 PPID 1 Vim
        setsid();

        execv(shellPath, shellArgv);

        // Never reached unless execv fails
        exit(255);
    } else {
        // Parent process
        if (close(ds[0]) == -1) return -1;

        // Send input to execute to the child process
        [input appendString:@"\n"];
        NSUInteger bytes = [input lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (write(ds[1], [input UTF8String], (size_t)bytes) != (ssize_t)bytes) return -1;
        if (close(ds[1]) == -1) return -1;

        ++numChildProcesses;
        ASLogDebug(@"new process pid=%d (count=%d)", pid, numChildProcesses);
    }

    return pid;
}

- (void)reapChildProcesses:(id)sender
{
    // NOTE: numChildProcesses (currently) only counts the number of Vim
    // processes that have been started with executeInLoginShell::.  If other
    // processes are spawned this code may need to be adjusted (or
    // numChildProcesses needs to be incremented when such a process is
    // started).
    while (numChildProcesses > 0) {
        int status = 0;
        int pid = waitpid(-1, &status, WNOHANG);
        if (pid <= 0)
            break;

        ASLogDebug(@"Wait for pid=%d complete", pid);
        --numChildProcesses;
    }
}

- (void)processInputQueues:(id)sender
{
    // NOTE: Because we use distributed objects it is quite possible for this
    // function to be re-entered.  This can cause all sorts of unexpected
    // problems so we guard against it here so that the rest of the code does
    // not need to worry about it.

    // The processing flag is > 0 if this function is already on the call
    // stack; < 0 if this function was also re-entered.
    if (processingFlag != 0) {
        ASLogDebug(@"BUSY!");
        processingFlag = -1;
        return;
    }

    // NOTE: Be _very_ careful that no exceptions can be raised between here
    // and the point at which 'processingFlag' is reset.  Otherwise the above
    // test could end up always failing and no input queues would ever be
    // processed!
    processingFlag = 1;

    // NOTE: New input may arrive while we're busy processing; we deal with
    // this by putting the current queue aside and creating a new input queue
    // for future input.
    NSDictionary *queues = inputQueues;
    inputQueues = [NSMutableDictionary new];

    // Pass each input queue on to the vim controller with matching
    // identifier (and note that it could be cached).
    NSEnumerator *e = [queues keyEnumerator];
    NSNumber *key;
    while ((key = [e nextObject])) {
        unsigned long ukey = [key unsignedLongValue];
        NSUInteger i = 0, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if (ukey == [vc vimControllerId]) {
                [vc processInputQueue:[queues objectForKey:key]]; // !exceptions
                break;
            }
        }

        if (i < count) continue;

        count = [cachedVimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [cachedVimControllers objectAtIndex:i];
            if (ukey == [vc vimControllerId]) {
                [vc processInputQueue:[queues objectForKey:key]]; // !exceptions
                break;
            }
        }

        if (i == count) {
            ASLogWarn(@"No Vim controller for identifier=%lu", ukey);
        }
    }

    [queues release];

    // If new input arrived while we were processing it would have been
    // blocked so we have to schedule it to be processed again.
    if (processingFlag < 0)
        [self performSelectorOnMainThread:@selector(processInputQueues:)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:[NSArray arrayWithObjects:
                                           NSDefaultRunLoopMode,
                                           NSEventTrackingRunLoopMode, nil]];

    processingFlag = 0;
}

- (void)addVimController:(MMVimController *)vc
{
    ASLogDebug(@"Add Vim controller pid=%d id=%lu",
            [vc pid], [vc vimControllerId]);

    int pid = [vc pid];
    NSNumber *pidKey = [NSNumber numberWithInt:pid];
    id args = [pidArguments objectForKey:pidKey];

    if (preloadPid == pid) {
        // This controller was preloaded, so add it to the cache and
        // schedule another vim process to be preloaded.
        preloadPid = -1;
        [vc setIsPreloading:YES];
        [cachedVimControllers addObject:vc];
        [self scheduleVimControllerPreloadAfterDelay:1];
    } else {
        [vimControllers addObject:vc];

        if (args && [NSNull null] != args)
            [vc passArguments:args];

        // HACK!  MacVim does not get activated if it is launched from the
        // terminal, so we forcibly activate here.  Note that each process
        // launched from MacVim has an entry in the pidArguments dictionary,
        // which is how we detect if the process was launched from the
        // terminal.
        if (!args) [self activateWhenNextWindowOpens];
    }

    if (args)
        [pidArguments removeObjectForKey:pidKey];
}

- (NSDictionary *)convertVimControllerArguments:(NSDictionary *)args
                                  toCommandLine:(NSArray **)cmdline
{
    // Take all arguments out of 'args' and put them on an array suitable to
    // pass as arguments to launchVimProcessWithArguments:.  The untouched
    // dictionary items are returned in a new autoreleased dictionary.

    if (cmdline)
        *cmdline = nil;

    NSArray *filenames = [args objectForKey:@"filenames"];
    NSUInteger numFiles = filenames ? [filenames count] : 0;
    BOOL openFiles = ![[args objectForKey:@"dontOpen"] boolValue];

    if (numFiles <= 0 || !openFiles)
        return args;

    NSMutableArray *a = [NSMutableArray array];
    NSMutableDictionary *d = [[args mutableCopy] autorelease];

    // Search for text and highlight it (this Vim script avoids warnings in
    // case there is no match for the search text).
    NSString *searchText = [args objectForKey:@"searchText"];
    if (searchText && [searchText length] > 0) {
        [a addObject:@"-c"];
        NSString *s = [NSString stringWithFormat:@"if search('\\V\\c%@','cW')"
                "|let @/='\\V\\c%@'|set hls|endif", searchText, searchText];
        [a addObject:s];

        [d removeObjectForKey:@"searchText"];
    }

    // Position cursor using "+line" or "-c :cal cursor(line,column)".
    NSString *lineString = [args objectForKey:@"cursorLine"];
    if (lineString && [lineString intValue] > 0) {
        NSString *columnString = [args objectForKey:@"cursorColumn"];
        if (columnString && [columnString intValue] > 0) {
            [a addObject:@"-c"];
            [a addObject:[NSString stringWithFormat:@":cal cursor(%@,%@)",
                          lineString, columnString]];

            [d removeObjectForKey:@"cursorColumn"];
        } else {
            [a addObject:[NSString stringWithFormat:@"+%@", lineString]];
        }

        [d removeObjectForKey:@"cursorLine"];
    }

    // Set selection using normal mode commands.
    NSString *rangeString = [args objectForKey:@"selectionRange"];
    if (rangeString) {
        NSRange r = NSRangeFromString(rangeString);
        [a addObject:@"-c"];
        if (r.length > 0) {
            // Select given range of characters.
            // TODO: This only works for encodings where 1 byte == 1 character
            [a addObject:[NSString stringWithFormat:@"norm %ldgov%ldgo",
                                                r.location, NSMaxRange(r)-1]];
        } else {
            // Position cursor on line at start of range.
            [a addObject:[NSString stringWithFormat:@"norm %ldGz.0",
                                                                r.location]];
        }

        [d removeObjectForKey:@"selectionRange"];
    }

    // Choose file layout using "-[o|O|p]".
    int layout = [[args objectForKey:@"layout"] intValue];
    switch (layout) {
        case MMLayoutHorizontalSplit: [a addObject:@"-o"]; break;
        case MMLayoutVerticalSplit:   [a addObject:@"-O"]; break;
        case MMLayoutTabs:            [a addObject:@"-p"]; break;
    }
    [d removeObjectForKey:@"layout"];


    // Last of all add the names of all files to open (DO NOT add more args
    // after this point).
    [a addObjectsFromArray:filenames];

    if ([args objectForKey:@"remoteID"]) {
        // These files should be edited remotely so keep the filenames on the
        // argument list -- they will need to be passed back to Vim when it
        // checks in.  Also set the 'dontOpen' flag or the files will be
        // opened twice.
        [d setObject:[NSNumber numberWithBool:YES] forKey:@"dontOpen"];
    } else {
        [d removeObjectForKey:@"dontOpen"];
        [d removeObjectForKey:@"filenames"];
    }

    if (cmdline)
        *cmdline = a;

    return d;
}

- (NSString *)workingDirectoryForArguments:(NSDictionary *)args
{
    // Find the "filenames" argument and pick the first path that actually
    // exists and return it.
    // TODO: Return common parent directory in the case of multiple files?
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *filenames = [args objectForKey:@"filenames"];
    NSUInteger i, count = [filenames count];
    for (i = 0; i < count; ++i) {
        BOOL isdir;
        NSString *file = [filenames objectAtIndex:i];
        if ([fm fileExistsAtPath:file isDirectory:&isdir])
            return isdir ? file : [file stringByDeletingLastPathComponent];
    }

    return nil;
}

- (NSScreen *)screenContainingTopLeftPoint:(NSPoint)pt
{
    // NOTE: The top left point has y-coordinate which lies one pixel above the
    // window which must be taken into consideration (this method used to be
    // called screenContainingPoint: but that method is "off by one" in
    // y-coordinate).

    NSArray *screens = [NSScreen screens];
    NSUInteger i, count = [screens count];
    for (i = 0; i < count; ++i) {
        NSScreen *screen = [screens objectAtIndex:i];
        NSRect frame = [screen frame];
        if (pt.x >= frame.origin.x && pt.x < NSMaxX(frame)
                // NOTE: inequalities below are correct due to this being a top
                // left test (see comment above)
                && pt.y > frame.origin.y && pt.y <= NSMaxY(frame))
            return screen;
    }

    return nil;
}

- (void)addInputSourceChangedObserver
{
    id nc = [NSDistributedNotificationCenter defaultCenter];
    NSString *notifyInputSourceChanged =
        (NSString *)kTISNotifySelectedKeyboardInputSourceChanged;
    [nc addObserver:self
           selector:@selector(inputSourceChanged:)
               name:notifyInputSourceChanged
             object:nil];
}

- (void)removeInputSourceChangedObserver
{
    id nc = [NSDistributedNotificationCenter defaultCenter];
    [nc removeObserver:self];
}

- (void)inputSourceChanged:(NSNotification *)notification
{
    NSUInteger i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        MMWindowController *wc = [controller windowController];
        MMTextView *tv = (MMTextView *)[[wc vimView] textView];
        [tv checkImState];
    }
}

@end // MMAppController (Private)

/* vi:set ts=8 sts=4 sw=4 ft=objc fdm=syntax:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

// This file contains root-level commonly used definitions that both Vim and
// MacVim processes need access to.

#import <Cocoa/Cocoa.h>

#pragma region Backward compatibility defines

// Taken from /usr/include/AvailabilityMacros.h
#ifndef MAC_OS_X_VERSION_10_7
# define MAC_OS_X_VERSION_10_7 1070
#endif
#ifndef MAC_OS_X_VERSION_10_8
# define MAC_OS_X_VERSION_10_8 1080
#endif
#ifndef MAC_OS_X_VERSION_10_9
# define MAC_OS_X_VERSION_10_9 1090
#endif
#ifndef MAC_OS_X_VERSION_10_10
# define MAC_OS_X_VERSION_10_10 101000
#endif
#ifndef MAC_OS_X_VERSION_10_11
# define MAC_OS_X_VERSION_10_11 101100
#endif
#ifndef MAC_OS_X_VERSION_10_12
# define MAC_OS_X_VERSION_10_12 101200
#endif
#ifndef MAC_OS_X_VERSION_10_12_2
# define MAC_OS_X_VERSION_10_12_2 101202
#endif
#ifndef MAC_OS_X_VERSION_10_13
# define MAC_OS_X_VERSION_10_13 101300
#endif
#ifndef MAC_OS_X_VERSION_10_14
# define MAC_OS_X_VERSION_10_14 101400
#endif
#ifndef MAC_OS_X_VERSION_10_15
# define MAC_OS_X_VERSION_10_15 101500
#endif
#ifndef MAC_OS_VERSION_11_0
# define MAC_OS_VERSION_11_0 110000
#endif
#ifndef MAC_OS_VERSION_12_0
# define MAC_OS_VERSION_12_0 120000
#endif
#ifndef MAC_OS_VERSION_13_0
# define MAC_OS_VERSION_13_0 130000
#endif
#ifndef MAC_OS_VERSION_14_0
# define MAC_OS_VERSION_14_0 140000
#endif

#ifndef NSAppKitVersionNumber10_10
# define NSAppKitVersionNumber10_10 1343
#endif
#ifndef NSAppKitVersionNumber10_10_Max
# define NSAppKitVersionNumber10_10_Max 1349
#endif
#ifndef NSAppKitVersionNumber10_12
# define NSAppKitVersionNumber10_12 1504
#endif
#ifndef NSAppKitVersionNumber10_12_2
# define NSAppKitVersionNumber10_12_2 1504.76
#endif
#ifndef NSAppKitVersionNumber10_13
# define NSAppKitVersionNumber10_13 1561
#endif
#ifndef NSAppKitVersionNumber10_14
# define NSAppKitVersionNumber10_14 1671
#endif
#ifndef NSAppKitVersionNumber11_0
# define NSAppKitVersionNumber11_0 2022
#endif

// Macro to detect runtime OS version. Ideally, we would just like to use
// @available to test for this because the compiler can optimize it out
// depending on your min/max OS configuration. However, it was added in Xcode 9
// (macOS 10.13 SDK). For any code that we want to be compilable for Xcode 8
// (macOS 10.12) or below, we need to use the macro below which will
// selectively use NSAppKitVersionNumber instead.
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_13
// Xcode 9+, can use @available, which is more efficient.
# define AVAILABLE_MAC_OS(MAJOR, MINOR) @available(macos MAJOR##.##MINOR, *)
# define AVAILABLE_MAC_OS_PATCH(MAJOR, MINOR, PATCH) @available(macos MAJOR##.##MINOR##.##PATCH, *)
#else
// Xcode 8 or below. Use the old-school NSAppKitVersionNumber check.
# define AVAILABLE_MAC_OS(MAJOR, MINOR) NSAppKitVersionNumber >= NSAppKitVersionNumber##MAJOR##_##MINOR
# define AVAILABLE_MAC_OS_PATCH(MAJOR, MINOR, PATCH) NSAppKitVersionNumber >= NSAppKitVersionNumber##MAJOR##_##MINOR##_##PATCH
#endif

// Deprecated constants. Since these are constants, we just need the compiler,
// not the runtime to know about them. As such, we can use MAX_ALLOWED to
// determine if we need to map or not.

#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_12
// Deprecated constants in 10.12 SDK
# define NSAlertStyleCritical NSCriticalAlertStyle
# define NSAlertStyleInformational NSInformationalAlertStyle
# define NSAlertStyleWarning NSWarningAlertStyle
# define NSButtonTypeSwitch NSSwitchButton
# define NSCompositingOperationSourceOver NSCompositeSourceOver
# define NSCompositingOperationDifference NSCompositeDifference
# define NSControlSizeRegular NSRegularControlSize
# define NSEventModifierFlagCapsLock NSAlphaShiftKeyMask
# define NSEventModifierFlagCommand NSCommandKeyMask
# define NSEventModifierFlagControl NSControlKeyMask
# define NSEventModifierFlagDeviceIndependentFlagsMask NSDeviceIndependentModifierFlagsMask
# define NSEventModifierFlagHelp NSHelpKeyMask
# define NSEventModifierFlagNumericPad NSNumericPadKeyMask
# define NSEventModifierFlagOption NSAlternateKeyMask
# define NSEventModifierFlagShift NSShiftKeyMask
# define NSEventTypeApplicationDefined NSApplicationDefined
# define NSEventTypeKeyDown NSKeyDown
# define NSEventTypeKeyUp NSKeyUp
# define NSEventTypeLeftMouseUp NSLeftMouseUp
# define NSEventTypeMouseEntered NSMouseEntered
# define NSEventTypeMouseExited NSMouseExited
# define NSEventTypeRightMouseDown NSRightMouseDown
# define NSWindowStyleMaskBorderless NSBorderlessWindowMask
# define NSWindowStyleMaskClosable NSClosableWindowMask
# define NSWindowStyleMaskFullScreen NSFullScreenWindowMask
# define NSWindowStyleMaskMiniaturizable NSMiniaturizableWindowMask
# define NSWindowStyleMaskResizable NSResizableWindowMask
# define NSWindowStyleMaskTexturedBackground NSTexturedBackgroundWindowMask
# define NSWindowStyleMaskTitled NSTitledWindowMask
# define NSWindowStyleMaskUnifiedTitleAndToolbar NSUnifiedTitleAndToolbarWindowMask
#endif

#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_13
// Deprecated constants in 10.13 SDK
#define NSControlStateValueOn NSOnState
#define NSControlStateValueOff NSOffState

// Newly introduced symbols in 10.13 SDK
typedef NSString* NSPasteboardType;
typedef NSString* NSAttributedStringKey;
#endif

// Deprecated runtime values. Since these are runtime values, we need to use the
// minimum required OS as determining factor. Otherwise it would crash.

#if MAC_OS_X_VERSION_MIN_REQUIRED <  MAC_OS_X_VERSION_10_13
// Deprecated runtime values in 10.13 SDK.
# define NSPasteboardNameFind NSFindPboard
#endif

#pragma endregion

#import <asl.h>
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_12
# define MM_USE_ASL
#else
# import <os/log.h>
#endif

#pragma region Shared protocols

//
// This is the protocol MMBackend implements.
//
// Only processInput:data: is allowed to cause state changes in Vim; all other
// messages should only read the Vim state.  (Note that setDialogReturn: is an
// exception to this rule; there really is no other way to deal with dialogs
// since they work with callbacks, so we cannot wait for them to return.)
//
// Be careful with messages with return type other than 'oneway void' -- there
// is a reply timeout set in MMAppController, if a message fails to get a
// response within the given timeout an exception will be thrown.  Use
// @try/@catch/@finally to deal with timeouts.
//
@protocol MMBackendProtocol
- (oneway void)processInput:(int)msgid data:(in bycopy NSData *)data;
- (oneway void)setDialogReturn:(in bycopy id)obj;
- (NSString *)evaluateExpression:(in bycopy NSString *)expr;
- (id)evaluateExpressionCocoa:(in bycopy NSString *)expr
                  errorString:(out bycopy NSString **)errstr;
- (BOOL)selectedTextToPasteboard:(byref NSPasteboard *)pboard;
- (NSString *)selectedText;
- (BOOL)mouseScreenposIsSelection:(int)row column:(int)column selRow:(byref int *)startRow selCol:(byref int *)startCol;
- (oneway void)acknowledgeConnection;
@end


//
// This is the protocol MMAppController implements.
//
// It handles connections between MacVim and Vim and communication from Vim to
// MacVim.
//
// Do not add methods to this interface without a _very_ good reason (if
// possible, instead add a new message to the *MsgID enum below and pass it via
// processInput:forIdentifier).  Methods should not modify the state directly
// but should instead delay any potential modifications (see
// connectBackend:pid: and processInput:forIdentifier:).
//
@protocol MMAppProtocol
- (unsigned long)connectBackend:(byref in id <MMBackendProtocol>)proxy pid:(int)pid;
- (oneway void)processInput:(in bycopy NSArray *)queue
              forIdentifier:(unsigned long)identifier;
- (NSArray *)serverList;
@end


@protocol MMVimServerProtocol;

//
// The Vim client protocol (implemented by MMBackend).
//
// The client needs to keep track of server replies.  Take a look at MMBackend
// if you want to implement this protocol in another program.
//
@protocol MMVimClientProtocol
- (oneway void)addReply:(in bycopy NSString *)reply
                 server:(in byref id <MMVimServerProtocol>)server;
@end


//
// The Vim server protocol (implemented by MMBackend).
//
// Note that addInput:client: is not asynchronous, because otherwise Vim might
// quit before the message has been passed (e.g. if --remote was used on the
// command line).
//
@protocol MMVimServerProtocol
- (void)addInput:(in bycopy NSString *)input
                 client:(in byref id <MMVimClientProtocol>)client;
- (NSString *)evaluateExpression:(in bycopy NSString *)expr
                 client:(in byref id <MMVimClientProtocol>)client;
@end

#pragma endregion

#pragma region IPC messages

//
// The following enum lists all messages that are passed between MacVim and
// Vim.  These can be sent in processInput:data: and in processCommandQueue:.
//

extern const char * const MMVimMsgIDStrings[];

#define FOREACH_MMVimMsgID(MSG) \
    MSG(NullMsgID) \
    MSG(OpenWindowMsgID) \
    MSG(KeyDownMsgID) \
    MSG(BatchDrawMsgID) \
    MSG(SelectTabMsgID) \
    MSG(CloseTabMsgID) \
    MSG(AddNewTabMsgID) \
    MSG(DraggedTabMsgID) \
    MSG(UpdateTabBarMsgID) \
    MSG(ShowTabBarMsgID) \
    MSG(HideTabBarMsgID) \
    MSG(SetTextRowsMsgID) \
    MSG(SetTextColumnsMsgID) \
    MSG(SetTextDimensionsMsgID) \
    MSG(SetTextDimensionsNoResizeWindowMsgID) \
    MSG(LiveResizeMsgID) \
    MSG(SetTextDimensionsReplyMsgID) \
    MSG(ResizeViewMsgID) \
    MSG(SetWindowTitleMsgID) \
    MSG(ScrollWheelMsgID) \
    MSG(MouseDownMsgID) \
    MSG(MouseUpMsgID) \
    MSG(MouseDraggedMsgID) \
    MSG(FlushQueueMsgID) \
    MSG(AddMenuMsgID) \
    MSG(AddMenuItemMsgID) \
    MSG(RemoveMenuItemMsgID) \
    MSG(EnableMenuItemMsgID) \
    MSG(ExecuteMenuMsgID) \
    MSG(UpdateMenuItemTooltipMsgID) \
    MSG(ShowToolbarMsgID) \
    MSG(ToggleToolbarMsgID) \
    MSG(CreateScrollbarMsgID) \
    MSG(DestroyScrollbarMsgID) \
    MSG(ShowScrollbarMsgID) \
    MSG(SetScrollbarPositionMsgID) \
    MSG(SetScrollbarThumbMsgID) \
    MSG(ScrollbarEventMsgID) \
    MSG(SetFontMsgID) \
    MSG(SetWideFontMsgID) \
    MSG(VimShouldCloseMsgID) \
    MSG(SetDefaultColorsMsgID) \
    MSG(ExecuteActionMsgID) \
    MSG(DropFilesMsgID) \
    MSG(DropStringMsgID) \
    MSG(ShowPopupMenuMsgID) \
    MSG(GotFocusMsgID) \
    MSG(LostFocusMsgID) \
    MSG(MouseMovedMsgID) \
    MSG(SetMouseShapeMsgID) \
    MSG(AdjustLinespaceMsgID) \
    MSG(AdjustColumnspaceMsgID) \
    MSG(ActivateMsgID) \
    MSG(SetServerNameMsgID) \
    MSG(EnterFullScreenMsgID) \
    MSG(LeaveFullScreenMsgID) \
    MSG(SetBuffersModifiedMsgID) \
    MSG(AddInputMsgID) \
    MSG(SetPreEditPositionMsgID) \
    MSG(TerminateNowMsgID) \
    MSG(XcodeModMsgID) \
    MSG(EnableAntialiasMsgID) \
    MSG(DisableAntialiasMsgID) \
    MSG(SetVimStateMsgID) \
    MSG(SetDocumentFilenameMsgID) \
    MSG(OpenWithArgumentsMsgID) \
    MSG(SelectAndFocusOpenedFileMsgID) \
    MSG(NewFileHereMsgID) \
    MSG(CloseWindowMsgID) \
    MSG(SetFullScreenColorMsgID) \
    MSG(ShowFindReplaceDialogMsgID) \
    MSG(FindReplaceMsgID) \
    MSG(UseSelectionForFindMsgID) \
    MSG(ActivateKeyScriptMsgID) \
    MSG(DeactivateKeyScriptMsgID) \
    MSG(EnableImControlMsgID) \
    MSG(DisableImControlMsgID) \
    MSG(ActivatedImMsgID) \
    MSG(DeactivatedImMsgID) \
    MSG(BrowseForFileMsgID) \
    MSG(ShowDialogMsgID) \
    MSG(SetMarkedTextMsgID) \
    MSG(ZoomMsgID) \
    MSG(SetWindowPositionMsgID) \
    MSG(DeleteSignMsgID) \
    MSG(SetTooltipMsgID) \
    MSG(GestureMsgID) \
    MSG(AddToMRUMsgID) \
    MSG(BackingPropertiesChangedMsgID) \
    MSG(SetBlurRadiusMsgID) \
    MSG(SetBackgroundOptionMsgID) \
    MSG(NotifyAppearanceChangeMsgID) \
    MSG(EnableLigaturesMsgID) \
    MSG(DisableLigaturesMsgID) \
    MSG(EnableThinStrokesMsgID) \
    MSG(DisableThinStrokesMsgID) \
    MSG(ShowDefinitionMsgID) \
    MSG(LoopBackMsgID) /* Simple message that Vim will reflect back to MacVim */ \
    MSG(LastMsgID) \

enum {
#define ENUM_ENTRY(X) X,
    FOREACH_MMVimMsgID(ENUM_ENTRY)
#undef ENUM_ENTRY
};


enum {
    ClearAllDrawType = 1,
    ClearBlockDrawType,
    DeleteLinesDrawType,
    DrawStringDrawType,
    InsertLinesDrawType,
    DrawCursorDrawType,
    SetCursorPosDrawType,
    DrawInvertedRectDrawType,
    DrawSignDrawType,

    InvalidDrawType = -1
};

enum {
    MMInsertionPointBlock,
    MMInsertionPointHorizontal,
    MMInsertionPointVertical,
    MMInsertionPointHollow,
    MMInsertionPointVerticalRight,
};


enum {
    ToolbarLabelFlag = 1,
    ToolbarIconFlag = 2,
    ToolbarSizeRegularFlag = 4
};


enum {
    MMTabLabel = 0,
    MMTabToolTip,
    MMTabInfoCount
};

enum {
    MMGestureSwipeLeft = 0,
    MMGestureSwipeRight,
    MMGestureSwipeUp,
    MMGestureSwipeDown,
    MMGestureForceClick,
};

#pragma endregion


// Create a string holding the labels of all messages in message queue for
// debugging purposes (condense some messages since there may typically be LOTS
// of them on a queue).
NSString *debugStringForMessageQueue(NSArray *queue);


// Shared user defaults (most user defaults are in Miscellaneous.h).
// Contrary to the user defaults in Miscellaneous.h these defaults are not
// initialized to any default values.  That is, unless the user sets them
// these keys will not be present in the user default database.
extern NSString *MMLogLevelKey;
extern NSString *MMLogToStdErrKey;

// Argument used to stop MacVim from opening an empty window on startup
// (technically this is a user default but should not be used as such).
extern NSString *MMNoWindowKey;

// Argument used to control MacVim sharing search text via the Find Pasteboard.
extern NSString *MMShareFindPboardKey;

extern NSString *MMAutosaveRowsKey;
extern NSString *MMAutosaveColumnsKey;
extern NSString *MMRendererKey; // Deprecated: Non-CoreText renderer

enum {
    MMRendererDefault = 0,
    MMRendererCoreText
};


extern NSString *VimFindPboardType;

// Alias for system monospace font name
extern NSString *MMSystemFontAlias;


@interface NSString (MMExtras)
- (NSString *)stringByRemovingFindPatterns;
- (NSString *)stringBySanitizingSpotlightSearch;
@end


@interface NSColor (MMExtras)
@property(readonly) unsigned argbInt;
+ (NSColor *)colorWithRgbInt:(unsigned)rgb;
+ (NSColor *)colorWithArgbInt:(unsigned)argb;
@end


@interface NSDictionary (MMExtras)
+ (id)dictionaryWithData:(NSData *)data;
- (NSData *)dictionaryAsData;
@end

@interface NSMutableDictionary (MMExtras)
+ (id)dictionaryWithData:(NSData *)data;
@end




// ODB Editor Suite Constants (taken from ODBEditorSuite.h)
#define	keyFileSender		'FSnd'
#define	keyFileSenderToken	'FTok'
#define	keyFileCustomPath	'Burl'
#define	kODBEditorSuite		'R*ch'
#define	kAEModifiedFile		'FMod'
#define	keyNewLocation		'New?'
#define	kAEClosedFile		'FCls'
#define	keySenderToken		'Tokn'


// MacVim Apple Event Constants
#define keyMMUntitledWindow       'MMuw'

#pragma region Logging

// Logging related functions and macros.
//
// This is a very simplistic logging facility built on top of ASL.  Two user
// defaults allow for changing the local log filter level (MMLogLevel) and
// whether logs should be sent to stderr (MMLogToStdErr).  (These user defaults
// are only checked during startup.)  The default is to block level 6 (info)
// and 7 (debug) logs and _not_ to send logs to stderr.  Apart from this
// "syslog" (see "man syslog") can be used to modify the ASL filters (it is
// currently not possible to change the local filter at runtime).  For example:
//   Enable all logs to reach the ASL database (by default 'debug' and 'info'
//   are filtered out, see "man syslogd"):
//     $ sudo syslog -c syslogd -d
//   Reset the ASL database filter:
//     $ sudo syslog -c syslogd off
//   Change the master filter to block logs less severe than errors:
//     $ sudo syslog -c 0 -e
//   Change per-process filter for running MacVim process to block logs less
//   severe than warnings:
//     $ syslog -c MacVim -w
//
// Note that there are four ASL filters:
//   1) The ASL database filter (syslog -c syslogd ...)
//   2) The master filter (syslog -c 0 ...)
//   3) The per-process filter (syslog -c PID ...)
//   4) The local filter (MMLogLevel)
//
// To view the logs, either use "Console.app" or the "syslog" command:
//   $ syslog -w | grep Vim
// To get the logs to show up in Xcode enable the MMLogToStdErr user default.

extern int ASLogLevel;

void ASLInit(void);

#if defined(MM_USE_ASL)

# define MM_ASL_LEVEL_DEFAULT ASL_LEVEL_NOTICE
# define ASLog(level, fmt, ...) \
    if (level <= ASLogLevel) { \
        asl_log(NULL, NULL, level, "%s@%d: %s", \
            __PRETTY_FUNCTION__, __LINE__, \
            [[NSString stringWithFormat:fmt, ##__VA_ARGS__] UTF8String]); \
    }

// Note: These macros are used like ASLogErr(@"text num=%d", 42).  Objective-C
// style specifiers (%@) are supported.
# define ASLogCrit(fmt, ...)   ASLog(ASL_LEVEL_CRIT,    fmt, ##__VA_ARGS__)
# define ASLogErr(fmt, ...)    ASLog(ASL_LEVEL_ERR,     fmt, ##__VA_ARGS__)
# define ASLogWarn(fmt, ...)   ASLog(ASL_LEVEL_WARNING, fmt, ##__VA_ARGS__)
# define ASLogNotice(fmt, ...) ASLog(ASL_LEVEL_NOTICE,  fmt, ##__VA_ARGS__)
# define ASLogInfo(fmt, ...)   ASLog(ASL_LEVEL_INFO,    fmt, ##__VA_ARGS__)
# define ASLogDebug(fmt, ...)  ASLog(ASL_LEVEL_DEBUG,   fmt, ##__VA_ARGS__)
# define ASLogTmp(fmt, ...)    ASLog(ASL_LEVEL_NOTICE,  fmt, ##__VA_ARGS__)

#else

# define MM_ASL_LEVEL_DEFAULT OS_LOG_TYPE_DEFAULT
# define ASLog(level, fmt, ...) \
    if (level <= ASLogLevel) { \
        if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_12) { \
            os_log_with_type(OS_LOG_DEFAULT, level, "%s@%d: %s", \
                __PRETTY_FUNCTION__, __LINE__, \
                [[NSString stringWithFormat:fmt, ##__VA_ARGS__] UTF8String]); \
        } else { \
            int logLevel; \
            switch (level) { \
            case OS_LOG_TYPE_FAULT: logLevel = ASL_LEVEL_CRIT; break; \
            case OS_LOG_TYPE_ERROR: logLevel = ASL_LEVEL_ERR; break; \
            case OS_LOG_TYPE_INFO: logLevel = ASL_LEVEL_INFO; break; \
            case OS_LOG_TYPE_DEBUG: logLevel = ASL_LEVEL_DEBUG; break; \
            default: logLevel = ASL_LEVEL_NOTICE; break; \
            } \
            _Pragma("clang diagnostic push") \
            _Pragma("clang diagnostic ignored \"-Wdeprecated-declarations\"") \
            asl_log(NULL, NULL, logLevel, "%s@%d: %s", \
                __PRETTY_FUNCTION__, __LINE__, \
                [[NSString stringWithFormat:fmt, ##__VA_ARGS__] UTF8String]); \
            _Pragma("clang diagnostic pop") \
        } \
    }

# define ASLogCrit(fmt, ...)   ASLog(OS_LOG_TYPE_FAULT,   fmt, ##__VA_ARGS__)
# define ASLogErr(fmt, ...)    ASLog(OS_LOG_TYPE_ERROR,   fmt, ##__VA_ARGS__)
# define ASLogWarn(fmt, ...)   ASLog(OS_LOG_TYPE_DEFAULT, fmt, ##__VA_ARGS__)
# define ASLogNotice(fmt, ...) ASLog(OS_LOG_TYPE_DEFAULT, fmt, ##__VA_ARGS__)
# define ASLogInfo(fmt, ...)   ASLog(OS_LOG_TYPE_INFO,    fmt, ##__VA_ARGS__)
# define ASLogDebug(fmt, ...)  ASLog(OS_LOG_TYPE_DEBUG,   fmt, ##__VA_ARGS__)
# define ASLogTmp(fmt, ...)    ASLog(OS_LOG_TYPE_DEFAULT, fmt, ##__VA_ARGS__)

#endif

#pragma endregion

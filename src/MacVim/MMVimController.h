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


@class MMWindowController;
@class MMTouchBarInfo;


#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12
/// Button used for Touch Bar support, with an additional metadata to store the
/// Vim command it should send.
@interface MMTouchBarButton : NSButton {
    NSArray *_desc;
}
- (NSArray *)desc;
- (void)setDesc:(NSArray *)desc;
@end
#endif

@interface MMVimController : NSObject<
    NSToolbarDelegate
    , NSOpenSavePanelDelegate
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
    , NSTouchBarDelegate
#endif
    >
{
    unsigned long       identifier;
    BOOL                isInitialized;
    MMWindowController  *windowController;
    id                  backendProxy;
    NSMenu              *mainMenu;
    NSMutableArray      *popupMenuItems;

    // TODO: Move all toolbar code to window controller?
    NSToolbar           *toolbar;
    NSMutableDictionary *toolbarItemDict;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
    MMTouchBarInfo      *touchbarInfo;
#endif

    int                 pid;
    NSString            *serverName;
    NSDictionary        *vimState;
    BOOL                isPreloading;
    NSDate              *creationDate;
    BOOL                hasModifiedBuffer;
}

- (id)initWithBackend:(id)backend pid:(int)processIdentifier;
- (void)uninitialize;
- (unsigned long)vimControllerId;
- (id)backendProxy;
- (int)pid;
- (void)setServerName:(NSString *)name;
- (NSString *)serverName;
- (MMWindowController *)windowController;
- (NSDictionary *)vimState;
- (id)objectForVimStateKey:(NSString *)key;
- (NSMenu *)mainMenu;
- (BOOL)isPreloading;
- (void)setIsPreloading:(BOOL)yn;
- (BOOL)hasModifiedBuffer;
- (NSDate *)creationDate;
- (void)cleanup;
- (void)dropFiles:(NSArray *)filenames forceOpen:(BOOL)force;
- (void)file:(NSString *)filename draggedToTabAtIndex:(NSUInteger)tabIndex;
- (void)filesDraggedToTabline:(NSArray *)filenames;
- (void)dropString:(NSString *)string;
- (void)appearanceChanged:(int)flag;

- (void)passArguments:(NSDictionary *)args;
- (void)sendMessage:(int)msgid data:(NSData *)data;
- (BOOL)sendMessageNow:(int)msgid data:(NSData *)data
               timeout:(NSTimeInterval)timeout;
- (void)addVimInput:(NSString *)string;
- (NSString *)evaluateVimExpression:(NSString *)expr;
- (id)evaluateVimExpressionCocoa:(NSString *)expr
                     errorString:(NSString **)errstr;
- (void)processInputQueue:(NSArray *)queue;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12_2
- (NSTouchBar *)makeTouchBar;
#endif
@end

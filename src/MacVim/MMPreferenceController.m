/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved            by Bram Moolenaar
 *                              MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMPreferenceController.h"
#import "MMAppController.h"
#import "Miscellaneous.h"

@implementation MMPreferenceController

- (void)windowDidLoad
{
#if DISABLE_SPARKLE
    {
        // If Sparkle is disabled in config, we don't want to show the preference pane
        // which could be confusing as it won't do anything.
        // After hiding the Sparkle subview, shorten the height of the General pane
        // and move its other subviews down.
        [sparkleUpdaterPane setHidden:YES];
        CGFloat sparkleHeight = NSHeight(sparkleUpdaterPane.frame);
        NSRect frame = generalPreferences.frame;
        frame.size.height -= sparkleHeight;
        generalPreferences.frame = frame;
    }
#endif

#if DISABLE_SPARKLE || USE_SPARKLE_1
    {
        // Also hide the pre-release update channel pane, if we disabled Sparkle, or
        // we are using Sparkle 1 still (since it doesn't support this feature).
        [sparklePrereleaseButton setHidden:YES];
        CGFloat sparkleHeight = NSHeight(sparklePrereleaseButton.frame);
        NSRect frame = advancedPreferences.frame;
        frame.size.height -= sparkleHeight;
        advancedPreferences.frame = frame;

        [sparklePrereleaseDesc setHidden:YES];
        sparkleHeight = NSHeight(sparklePrereleaseDesc.frame);
        frame = advancedPreferences.frame;
        frame.size.height -= sparkleHeight;
        advancedPreferences.frame = frame;
    }
#endif
    [super windowDidLoad];

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 110000
    if (@available(macos 11.0, *)) {
        // macOS 11 will default to a unified toolbar style unless you use the new
        // toolbarStyle to tell it to use a "preference" style, which makes it look nice
        // and centered.
        [self window].toolbarStyle = NSWindowToolbarStylePreference;
    }
#endif
}

- (IBAction)showWindow:(id)sender
{
    [super setCrossFade:NO];
    [super showWindow:sender];

    // Refresh enabled states for settings that may or may not make sense
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (allowForceClickLookUpButton != nil) {
        // Only enable force click lookup setting if only the user has configured so to begin with.
        // Otherwise it doesn't make sense at all.
        // Note: This cannot be done in simple bindings, because NSUserDefaults don't really support
        //       global domain bindings from what I can tell, we have to manually read it.
        const BOOL useForceClickLookup = [ud boolForKey:@"com.apple.trackpad.forceClick"];
        [allowForceClickLookUpButton setEnabled:useForceClickLookup];
    }
}

- (void)setupToolbar
{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_11_0
    if (@available(macos 11.0, *)) {
        // Use SF Symbols for versions of the OS that supports it to be more unified with OS appearance.
        [self addView:generalPreferences
                label:@"General"
                image:[NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil]];

        [self addView:appearancePreferences
                label:@"Appearance"
                image:[NSImage imageWithSystemSymbolName:@"paintbrush" accessibilityDescription:nil]];

        [self addView:inputPreferences
                label:@"Input"
                image:[NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:nil]];

        [self addView:advancedPreferences
                label:@"Advanced"
                image:[NSImage imageWithSystemSymbolName:@"gearshape.2" accessibilityDescription:nil]];
    }
    else
#endif
    {
        [self addView:generalPreferences
                label:@"General"
                image:[NSImage imageNamed:NSImageNamePreferencesGeneral]];

        [self addView:appearancePreferences
                label:@"Appearance"
                image:[NSImage imageNamed:NSImageNameColorPanel]];

        [self addView:inputPreferences
                label:@"Input"
                image:[NSImage imageNamed:NSImageNamePreferencesGeneral]]; // not a good choice but works for now

        [self addView:advancedPreferences
                label:@"Advanced"
                image:[NSImage imageNamed:NSImageNameAdvanced]];
    }
}


- (NSString *)currentPaneIdentifier
{
    // We override this to persist the current pane.
    return [[NSUserDefaults standardUserDefaults]
        stringForKey:MMCurrentPreferencePaneKey];
}

- (void)setCurrentPaneIdentifier:(NSString *)identifier
{
    // We override this to persist the current pane.
    [[NSUserDefaults standardUserDefaults]
        setObject:identifier forKey:MMCurrentPreferencePaneKey];
}


- (IBAction)openInCurrentWindowSelectionChanged:(id)sender
{
    BOOL openInCurrentWindowSelected = ([[sender selectedCell] tag] != 0);
    BOOL useWindowsLayout =
            ([[layoutPopUpButton selectedItem] tag] == MMLayoutWindows);
    if (openInCurrentWindowSelected && useWindowsLayout) {
        [[NSUserDefaults standardUserDefaults] setInteger:MMLayoutTabs forKey:MMOpenLayoutKey];
    }
}

- (IBAction)checkForUpdatesChanged:(id)sender
{
    // Sparkle's auto-install update preference trumps "check for update", so
    // need to make sure to unset that if the user unchecks "check for update".
    NSButton *button = (NSButton *)sender;
    BOOL checkForUpdates = ([button state] != 0);
    if (!checkForUpdates) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"SUAutomaticallyUpdate"];
    }
}

- (IBAction)appearanceChanged:(id)sender
{
    // Refresh all windows' appearance to match preference.
    [[MMAppController sharedInstance] refreshAllAppearances];
}

- (IBAction)fontPropertiesChanged:(id)sender
{
    // Refresh all windows' fonts.
    [[MMAppController sharedInstance] refreshAllFonts];
}

- (IBAction)tabsPropertiesChanged:(id)sender
{
    [[MMAppController sharedInstance] refreshAllTabProperties];
}

- (IBAction)smoothResizeChanged:(id)sender
{
    [[MMAppController sharedInstance] refreshAllResizeConstraints];
}

- (IBAction)cmdlineAlignBottomChanged:(id)sender
{
    [[MMAppController sharedInstance] refreshAllTextViews];
}

- (IBAction)nonNativeFullScreenShowMenuChanged:(id)sender
{
    [[MMAppController sharedInstance] refreshAllFullScreenPresentationOptions];
}

@end

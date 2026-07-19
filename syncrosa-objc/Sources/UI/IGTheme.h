#ifndef IGTheme_h
#define IGTheme_h

#import <Cocoa/Cocoa.h>

extern NSString * const IGThemeDefaultsKey;
extern NSString * const IGThemeDidChangeNotification;

NSArray *IGThemeIdentifiers(void);
NSString *IGThemeDisplayNameForIdentifier(NSString *identifier);
NSString *IGActiveThemeIdentifier(void);
void IGSetActiveThemeIdentifier(NSString *identifier);

typedef NSInteger IGThemeBackgroundRole;
enum {
    IGThemeBackgroundRoleWindow = 0,
    IGThemeBackgroundRoleSidebar = 1,
    IGThemeBackgroundRoleContent = 2
};

typedef NSInteger IGThemeButtonRole;
enum {
    IGThemeButtonRoleSecondary = 0,
    IGThemeButtonRolePrimary = 1,
    IGThemeButtonRoleDanger = 2,
    IGThemeButtonRoleSidebar = 3,
    IGThemeButtonRoleTab = 4
};

NSColor *IGThemeWindowColor(void);
NSColor *IGThemeSidebarColor(void);
NSColor *IGThemeContentColor(void);
NSColor *IGThemePanelColor(void);
NSColor *IGThemePanelInsetColor(void);
NSColor *IGThemeControlColor(void);
NSColor *IGThemeControlBorderColor(void);
NSColor *IGThemeDividerColor(void);
NSColor *IGThemeTextColor(void);
NSColor *IGThemeMutedTextColor(void);
NSColor *IGThemeAccentColor(void);
NSColor *IGThemeDangerColor(void);

NSView *IGCreateThemedBackgroundView(NSRect frame, IGThemeBackgroundRole role);
void IGInstallThemedContentBackground(NSView *view);
void IGApplyThemeToButton(NSButton *button, IGThemeButtonRole role);
void IGApplyThemeToViewHierarchy(NSView *view);
void IGRefreshThemedViews(NSView *view);

#endif

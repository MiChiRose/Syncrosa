#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, IGThemeIconRole) {
    IGThemeIconRoleAccent = 0,
    IGThemeIconRoleText = 1,
    IGThemeIconRoleMuted = 2
};

NSImage *IGIconImageNamed(NSString *name);
NSImage *IGIconImageNamedFlipped(NSString *name, BOOL flippedHorizontally);
NSImage *IGIconImageNamedRotated(NSString *name, CGFloat degrees);
void IGConfigureIconButton(NSButton *button, NSString *name, NSString *toolTip, BOOL imageOnly);
NSView *IGCreateThemedIconView(NSString *name, NSRect frame, IGThemeIconRole role);

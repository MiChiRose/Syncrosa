#import "IGHelpSheetPresenter.h"
#import "IGIconProvider.h"
#import "IGTheme.h"

static NSString * const IGHelpSectionTitleKey = @"title";
static NSString * const IGHelpSectionBodyKey = @"body";

NSDictionary *IGHelpSectionMake(NSString *title, NSString *body)
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ?: @"", IGHelpSectionTitleKey,
            body ?: @"", IGHelpSectionBodyKey,
            nil];
}

static NSTextField *IGHelpLabel(NSString *text, NSRect frame, NSFont *font, NSColor *color)
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    label.stringValue = text ?: @"";
    label.font = font ?: [NSFont systemFontOfSize:12.0];
    label.textColor = color ?: IGThemeTextColor();
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    NSCell *cell = [label cell];
    if ([cell respondsToSelector:@selector(setLineBreakMode:)]) {
        [cell setLineBreakMode:NSLineBreakByWordWrapping];
    }
    return label;
}

@implementation IGHelpSheetPresenter

+ (NSWindow *)sheetWithTitle:(NSString *)title
                     summary:(NSString *)summary
                    sections:(NSArray *)sections
                  closeTitle:(NSString *)closeTitle
                      target:(id)target
                      action:(SEL)action
{
    NSWindow *sheet = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 350)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES] autorelease];
    sheet.title = @"Syncrosa Help";
    IGInstallThemedContentBackground(sheet.contentView);

    NSView *icon = IGCreateThemedIconView(@"info", NSMakeRect(26, 286, 38, 38), IGThemeIconRoleAccent);
    [sheet.contentView addSubview:icon];

    NSTextField *titleLabel = IGHelpLabel(title, NSMakeRect(78, 298, 392, 24),
                                          [NSFont boldSystemFontOfSize:16.0], IGThemeTextColor());
    [sheet.contentView addSubview:titleLabel];

    NSTextField *summaryLabel = IGHelpLabel(summary, NSMakeRect(78, 260, 392, 38),
                                            [NSFont systemFontOfSize:11.5], IGThemeMutedTextColor());
    [sheet.contentView addSubview:summaryLabel];

    NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(24, 250, 452, 1)] autorelease];
    separator.boxType = NSBoxSeparator;
    [sheet.contentView addSubview:separator];

    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(24, 62, 452, 174)] autorelease];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;

    NSTextView *textView = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 438, 174)] autorelease];
    textView.editable = NO;
    textView.selectable = YES;
    textView.drawsBackground = NO;
    textView.textContainerInset = NSMakeSize(2.0, 4.0);

    NSMutableAttributedString *content = [[[NSMutableAttributedString alloc] init] autorelease];
    NSUInteger sectionIndex = 0;
    for (NSDictionary *section in sections ?: @[]) {
        NSString *sectionTitle = [section objectForKey:IGHelpSectionTitleKey] ?: @"";
        NSString *sectionBody = [section objectForKey:IGHelpSectionBodyKey] ?: @"";
        if (sectionIndex > 0) {
            [content appendAttributedString:[[[NSAttributedString alloc] initWithString:@"\n"] autorelease]];
        }

        NSMutableParagraphStyle *headingStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        headingStyle.paragraphSpacing = 4.0;
        NSDictionary *headingAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSFont boldSystemFontOfSize:12.0], NSFontAttributeName,
                                           IGThemeTextColor(), NSForegroundColorAttributeName,
                                           headingStyle, NSParagraphStyleAttributeName,
                                           nil];
        [content appendAttributedString:[[[NSAttributedString alloc] initWithString:[sectionTitle stringByAppendingString:@"\n"]
                                                                          attributes:headingAttributes] autorelease]];

        NSMutableParagraphStyle *bodyStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        bodyStyle.lineSpacing = 2.0;
        bodyStyle.paragraphSpacing = 8.0;
        NSDictionary *bodyAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSFont systemFontOfSize:11.5], NSFontAttributeName,
                                        IGThemeMutedTextColor(), NSForegroundColorAttributeName,
                                        bodyStyle, NSParagraphStyleAttributeName,
                                        nil];
        [content appendAttributedString:[[[NSAttributedString alloc] initWithString:sectionBody
                                                                          attributes:bodyAttributes] autorelease]];
        sectionIndex += 1;
    }
    [[textView textStorage] setAttributedString:content];
    scroll.documentView = textView;
    [sheet.contentView addSubview:scroll];

    NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(376, 18, 100, 30)] autorelease];
    closeButton.title = [closeTitle length] ? closeTitle : @"Close";
    closeButton.bezelStyle = NSRoundedBezelStyle;
    closeButton.target = target;
    closeButton.action = action;
    IGApplyThemeToButton(closeButton, IGThemeButtonRolePrimary);
    [sheet.contentView addSubview:closeButton];

    IGApplyThemeToWindow(sheet);
    return sheet;
}

+ (void)presentSheet:(NSWindow *)sheet forWindow:(NSWindow *)parentWindow
{
    if (!sheet || !parentWindow) {
        return;
    }
    [NSApp beginSheet:sheet
       modalForWindow:parentWindow
        modalDelegate:nil
       didEndSelector:NULL
          contextInfo:NULL];
}

+ (void)dismissSheet:(NSWindow *)sheet fromWindow:(NSWindow *)parentWindow
{
    if (!sheet) {
        return;
    }
    if (parentWindow) {
        [parentWindow endSheet:sheet];
    } else {
        [NSApp endSheet:sheet];
    }
    [sheet orderOut:nil];
}

@end

#import "AppDelegate.h"
#import "IGMainWindowController.h"
#import "IGLocalizationService.h"

@interface AppDelegate ()
@property (nonatomic, strong) IGMainWindowController *mainWindowController;
@property (nonatomic, strong) NSMenu *languageMenu;
@property (nonatomic, strong) NSWindow *fallbackWindow;
@end

@implementation AppDelegate

static void IGAppStartupLog(NSString *message) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop/Syncrosa-objc-startup.log"];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    IGAppStartupLog(@"applicationDidFinishLaunching entered");
    @try {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(localizationChanged:)
                                                     name:@"IGLanguageChangedNotification"
                                                   object:nil];
        [self setupMenu];
        IGAppStartupLog(@"menu created");
        self.mainWindowController = [[IGMainWindowController alloc] init];
        IGAppStartupLog(@"main window controller created");
        [self.mainWindowController showWindow:self];
        IGAppStartupLog(@"main window shown");
    } @catch (NSException *exception) {
        IGAppStartupLog([NSString stringWithFormat:@"launch exception: %@ - %@", exception.name, exception.reason]);
        IGAppStartupLog([NSString stringWithFormat:@"launch stack: %@", exception.callStackSymbols]);
        [self showFallbackWindowForException:exception];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    // App Menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];

    // Edit Menu (Required for Copy/Paste)
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenuItem setSubmenu:editMenu];

    // Language Menu
    NSMenuItem *langMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:langMenuItem];
    self.languageMenu = [[NSMenu alloc] initWithTitle:@"Language"];
    NSArray *langs = @[@"English", @"Русский", @"Беларуская", @"한국어", @"日本語", @"中文", @"Deutsch", @"Polski", @"Eesti", @"Español"];
    for (NSInteger i = 0; i < langs.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:langs[i] action:@selector(changeLanguage:) keyEquivalent:@""];
        item.tag = i;
        [self.languageMenu addItem:item];
    }
    [langMenuItem setSubmenu:self.languageMenu];
    [self updateLanguageMenuState:self.languageMenu];

    [NSApp setMainMenu:mainMenu];
}

- (void)showFallbackWindowForException:(NSException *)exception {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 220)
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window center];
    [window setTitle:@"Syncrosa Legacy Safe Mode"];

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 160, 512, 28)];
    [title setStringValue:@"Syncrosa could not open the full interface."];
    [title setFont:[NSFont boldSystemFontOfSize:16]];
    [title setEditable:NO];
    [title setBordered:NO];
    [title setDrawsBackground:NO];
    [window.contentView addSubview:title];

    NSTextField *body = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 60, 512, 90)];
    [body setStringValue:[NSString stringWithFormat:@"The app is still running in safe mode. A diagnostic log was written to Desktop/Syncrosa-objc-startup.log.\n\n%@", exception.reason ?: @"Unknown launch error."]];
    [body setFont:[NSFont systemFontOfSize:12]];
    [body setEditable:NO];
    [body setBordered:NO];
    [body setDrawsBackground:NO];
    [window.contentView addSubview:body];

    self.fallbackWindow = window;
    [self.fallbackWindow makeKeyAndOrderFront:nil];
}

- (void)changeLanguage:(NSMenuItem *)sender {
    NSArray *codes = @[@"en", @"ru", @"be", @"ko", @"ja", @"zh", @"de", @"pl", @"et", @"es"];
    NSInteger index = sender.tag;
    if (index >= 0 && index < codes.count) {
        [IGLocalizationService sharedService].selectedLanguage = codes[index];
    }
}

- (void)updateLanguageMenuState:(NSMenu *)menu {
    NSString *currentLang = [IGLocalizationService sharedService].selectedLanguage;
    NSArray *codes = @[@"en", @"ru", @"be", @"ko", @"ja", @"zh", @"de", @"pl", @"et", @"es"];

    for (NSMenuItem *item in menu.itemArray) {
        if (item.tag >= 0 && item.tag < codes.count) {
            if ([codes[item.tag] isEqualToString:currentLang]) {
                item.state = NSOnState;
            } else {
                item.state = NSOffState;
            }
        }
    }
}

- (void)localizationChanged:(NSNotification *)notification {
    [self updateLanguageMenuState:self.languageMenu];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end

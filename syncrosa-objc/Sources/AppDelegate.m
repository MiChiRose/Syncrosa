#import "AppDelegate.h"
#import "IGMainWindowController.h"
#import "IGLocalizationService.h"

@interface AppDelegate ()
@property (nonatomic, strong) IGMainWindowController *mainWindowController;
@property (nonatomic, strong) NSMenu *languageMenu;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
    [self setupMenu];
    self.mainWindowController = [[IGMainWindowController alloc] init];
    [self.mainWindowController showWindow:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

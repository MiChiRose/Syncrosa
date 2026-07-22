#import "IGGeniusViewController.h"
#import "IGiTunesService.h"
#import "IGAIService.h"
#import "IGLocalizationService.h"
#import "IGNotificationView.h"
#import "IGTheme.h"
#import "IGHelpSheetPresenter.h"
#import "IGIconProvider.h"

@interface IGGeniusViewController () <NSTextFieldDelegate>

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *configLabel;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *nameCounterLabel;
@property (nonatomic, strong) NSTextField *playlistNameField;
@property (nonatomic, strong) NSTextField *promptLabel;
@property (nonatomic, strong) NSTextField *promptCounterLabel;
@property (nonatomic, strong) NSTextField *promptField;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSTextField *countField;
@property (nonatomic, strong) NSStepper *stepper;
@property (nonatomic, strong) NSButton *generateButton;
@property (nonatomic, strong) NSWindow *helpSheetWindow;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, assign) BOOL isGenerating;

@end

static NSBox *IGGeniusRoundedPanel(NSRect frame)
{
    NSBox *panel = [[[NSBox alloc] initWithFrame:frame] autorelease];
    panel.boxType = NSBoxCustom;
    panel.titlePosition = NSNoTitle;
    panel.borderType = NSLineBorder;
    panel.borderWidth = 1.0;
    panel.cornerRadius = 8.0;
    panel.fillColor = IGThemePanelColor();
    panel.borderColor = IGThemeControlBorderColor();
    panel.transparent = NO;
    return panel;
}

@implementation IGGeniusViewController

- (void)loadView {
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)] autorelease];
    [self setupUI];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(apiSettingsSaved:)
                                                 name:@"IGAPISettingsSavedNotification"
                                               object:nil];
    [self updateConfigLabel];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
    [_titleLabel release];
    [_configLabel release];
    [_nameLabel release];
    [_nameCounterLabel release];
    [_playlistNameField release];
    [_promptLabel release];
    [_promptCounterLabel release];
    [_promptField release];
    [_countLabel release];
    [_countField release];
    [_stepper release];
    [_generateButton release];
    [_helpSheetWindow release];
    [_progressIndicator release];
    [_statusLabel release];
    [super dealloc];
#endif
}

- (void)setupUI {
    self.titleLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 432, 540, 30)] autorelease];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:18];
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.alignment = NSCenterTextAlignment;
    [self.view addSubview:self.titleLabel];

    NSButton *helpButton = [[[NSButton alloc] initWithFrame:NSMakeRect(520, 434, 25, 25)] autorelease];
    helpButton.bezelStyle = NSHelpButtonBezelStyle;
    helpButton.title = @"";
    helpButton.target = self;
    helpButton.action = @selector(helpClicked:);
    [self.view addSubview:helpButton];

    NSBox *configPanel = IGGeniusRoundedPanel(NSMakeRect(70, 388, 440, 36));
    [configPanel addSubview:IGCreateThemedIconView(@"star", NSMakeRect(14, 9, 18, 18), IGThemeIconRoleAccent)];
    [self.view addSubview:configPanel];

    self.configLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(42, 8, 382, 19)] autorelease];
    self.configLabel.font = [NSFont systemFontOfSize:11];
    self.configLabel.textColor = IGThemeMutedTextColor();
    self.configLabel.editable = NO;
    self.configLabel.bordered = NO;
    self.configLabel.drawsBackground = NO;
    self.configLabel.alignment = NSCenterTextAlignment;
    [[self.configLabel cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [configPanel addSubview:self.configLabel];

    NSBox *detailsPanel = IGGeniusRoundedPanel(NSMakeRect(35, 270, 510, 104));
    [self.view addSubview:detailsPanel];

    self.nameLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(22, 66, 250, 20)] autorelease];
    self.nameLabel.font = [NSFont systemFontOfSize:13];
    self.nameLabel.editable = NO;
    self.nameLabel.bordered = NO;
    self.nameLabel.drawsBackground = NO;
    [detailsPanel addSubview:self.nameLabel];

    self.nameCounterLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(276, 66, 62, 20)] autorelease];
    self.nameCounterLabel.font = [NSFont systemFontOfSize:11];
    self.nameCounterLabel.textColor = IGThemeMutedTextColor();
    self.nameCounterLabel.alignment = NSRightTextAlignment;
    self.nameCounterLabel.editable = NO;
    self.nameCounterLabel.bordered = NO;
    self.nameCounterLabel.drawsBackground = NO;
    [detailsPanel addSubview:self.nameCounterLabel];

    self.countLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(358, 66, 128, 20)] autorelease];
    self.countLabel.font = [NSFont systemFontOfSize:13];
    self.countLabel.editable = NO;
    self.countLabel.bordered = NO;
    self.countLabel.drawsBackground = NO;
    [detailsPanel addSubview:self.countLabel];

    self.playlistNameField = [[[NSTextField alloc] initWithFrame:NSMakeRect(22, 24, 316, 30)] autorelease];
    self.playlistNameField.bezelStyle = NSTextFieldRoundedBezel;
    self.playlistNameField.stringValue = @"My AI Playlist";
    self.playlistNameField.delegate = self;
    [detailsPanel addSubview:self.playlistNameField];

    self.countField = [[[NSTextField alloc] initWithFrame:NSMakeRect(358, 24, 88, 30)] autorelease];
    self.countField.bezelStyle = NSTextFieldRoundedBezel;
    self.countField.stringValue = @"20";
    self.countField.delegate = self;
    [detailsPanel addSubview:self.countField];

    self.stepper = [[[NSStepper alloc] initWithFrame:NSMakeRect(454, 24, 19, 30)] autorelease];
    self.stepper.minValue = 1;
    self.stepper.maxValue = 100;
    self.stepper.integerValue = 20;
    self.stepper.target = self;
    self.stepper.action = @selector(stepperChanged:);
    [detailsPanel addSubview:self.stepper];

    NSBox *promptPanel = IGGeniusRoundedPanel(NSMakeRect(35, 157, 510, 99));
    [self.view addSubview:promptPanel];

    self.promptLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(22, 61, 390, 20)] autorelease];
    self.promptLabel.font = [NSFont systemFontOfSize:13];
    self.promptLabel.editable = NO;
    self.promptLabel.bordered = NO;
    self.promptLabel.drawsBackground = NO;
    [promptPanel addSubview:self.promptLabel];

    self.promptCounterLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(414, 61, 72, 20)] autorelease];
    self.promptCounterLabel.font = [NSFont systemFontOfSize:11];
    self.promptCounterLabel.textColor = IGThemeMutedTextColor();
    self.promptCounterLabel.alignment = NSRightTextAlignment;
    self.promptCounterLabel.editable = NO;
    self.promptCounterLabel.bordered = NO;
    self.promptCounterLabel.drawsBackground = NO;
    [promptPanel addSubview:self.promptCounterLabel];

    self.promptField = [[[NSTextField alloc] initWithFrame:NSMakeRect(22, 19, 464, 30)] autorelease];
    self.promptField.bezelStyle = NSTextFieldRoundedBezel;
    self.promptField.delegate = self;
    [promptPanel addSubview:self.promptField];

    NSBox *actionPanel = IGGeniusRoundedPanel(NSMakeRect(35, 35, 510, 108));
    [self.view addSubview:actionPanel];

    self.generateButton = [[[NSButton alloc] initWithFrame:NSMakeRect(125, 59, 260, 38)] autorelease];
    self.generateButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.generateButton.target = self;
    self.generateButton.action = @selector(generateClicked:);
    IGConfigureIconButton(self.generateButton, @"star", @"Generate an AI playlist from the current iTunes library", NO);
    [actionPanel addSubview:self.generateButton];

    self.progressIndicator = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(25, 34, 460, 15)] autorelease];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.hidden = YES;
    [actionPanel addSubview:self.progressIndicator];

    self.statusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(25, 11, 460, 18)] autorelease];
    self.statusLabel.editable = NO;
    self.statusLabel.bordered = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.alignment = NSCenterTextAlignment;
    self.statusLabel.textColor = IGThemeMutedTextColor();
    [actionPanel addSubview:self.statusLabel];

    [self updateLocalization];
    [self updateCharacterCounters];
    [self updateGenerateButtonState];
}

- (void)updateLocalization {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    
    self.titleLabel.stringValue = [lang t:@"ai_playlist"];
    self.nameLabel.stringValue = [lang t:@"pl_name"];
    self.promptLabel.stringValue = [lang t:@"pl_mood"];
    self.countLabel.stringValue = [lang t:@"track_count"];
    self.generateButton.title = [lang t:@"generate_playlist"];
    IGConfigureIconButton(self.generateButton, @"star", @"Generate an AI playlist from the current iTunes library", NO);
    IGApplyThemeToButton(self.generateButton, IGThemeButtonRolePrimary);
    
    if (self.statusLabel.stringValue.length == 0 || 
        [self.statusLabel.stringValue isEqualToString:@"Ready"] || 
        [self.statusLabel.stringValue isEqualToString:@"Готово."]) {
        self.statusLabel.stringValue = [lang t:@"ready"];
    }
    
    [[self.promptField cell] setPlaceholderString:[lang.selectedLanguage isEqualToString:@"ru"] ? 
        @"например: синтвейв 80-х для ночной поездки" : 
        @"e.g. 80s synthwave for late night drive"];
    
    [self updateConfigLabel];
}

- (void)updateConfigLabel {
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    NSString *provider = [IGAIService sharedService].provider ?: @"-";
    NSString *model = [IGAIService sharedService].model ?: @"-";
    self.configLabel.stringValue = [NSString stringWithFormat:@"%@: %@ / %@", [lang t:@"active_config"], provider, model];
}

- (void)localizationChanged:(NSNotification *)notification {
    [self updateLocalization];
}

- (void)apiSettingsSaved:(NSNotification *)notification {
    [self updateConfigLabel];
}

- (void)stepperChanged:(id)sender {
    self.countField.stringValue = [NSString stringWithFormat:@"%ld", (long)self.stepper.integerValue];
    [self updateGenerateButtonState];
}

#pragma mark - TextField Delegate (Character Counting)

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *textField = [obj object];
    if (textField == self.playlistNameField) {
        if (self.playlistNameField.stringValue.length > 30) {
            self.playlistNameField.stringValue = [self.playlistNameField.stringValue substringToIndex:30];
        }
    } else if (textField == self.promptField) {
        if (self.promptField.stringValue.length > 150) {
            self.promptField.stringValue = [self.promptField.stringValue substringToIndex:150];
        }
    } else if (textField == self.countField) {
        NSInteger val = [self.countField integerValue];
        if (val < 1) val = 1;
        if (val > 100) val = 100;
        self.stepper.integerValue = val;
    }
    [self updateCharacterCounters];
    [self updateGenerateButtonState];
}

- (void)updateCharacterCounters {
    self.nameCounterLabel.stringValue = [NSString stringWithFormat:@"%ld/30", (long)self.playlistNameField.stringValue.length];
    self.promptCounterLabel.stringValue = [NSString stringWithFormat:@"%ld/150", (long)self.promptField.stringValue.length];
}

- (BOOL)canGeneratePlaylist {
    NSString *name = [self.playlistNameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *prompt = [self.promptField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return !self.isGenerating && name.length > 0 && prompt.length > 0 && [self.countField integerValue] > 0;
}

- (void)updateGenerateButtonState {
    self.generateButton.enabled = [self canGeneratePlaylist];
    IGApplyThemeToButton(self.generateButton, IGThemeButtonRolePrimary);
}

- (void)finishGeneration {
    self.isGenerating = NO;
    [self updateGenerateButtonState];
}

#pragma mark - Generation

- (void)generateClicked:(id)sender {
    if (![self canGeneratePlaylist]) {
        return;
    }
    IGLocalizationService *lang = [IGLocalizationService sharedService];
    self.isGenerating = YES;
    [self updateGenerateButtonState];
    self.progressIndicator.hidden = NO;
    self.progressIndicator.doubleValue = 0;
    self.statusLabel.stringValue = @"Reading iTunes Library...";

    [[IGiTunesService sharedService] fetchLibraryTrackCountWithCompletion:^(NSInteger trackCount, NSString *errorMessage) {
        if (trackCount < 0) {
            self.statusLabel.stringValue = errorMessage ?: @"Could not read iTunes library.";
            [self finishGeneration];
            self.progressIndicator.hidden = YES;
            [IGNotificationView showInView:self.view message:self.statusLabel.stringValue isError:YES];
            return;
        }
        if (trackCount == 0) {
            self.statusLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ?
                @"В iTunes нет треков. Создавать ИИ-плейлист пока не из чего." :
                @"iTunes has no tracks. There is nothing to use for an AI playlist.";
            [self finishGeneration];
            self.progressIndicator.hidden = YES;
            [IGNotificationView showInView:self.view message:self.statusLabel.stringValue isError:YES];
            return;
        }

        [[IGiTunesService sharedService] fetchAllTracksWithProgress:^(NSInteger current, NSInteger total) {
        self.progressIndicator.maxValue = total;
        self.progressIndicator.doubleValue = current;
        } completion:^(NSArray *tracks) {
        if (tracks.count == 0) {
            self.statusLabel.stringValue = [lang t:@"lib_empty"];
            [self finishGeneration];
            self.progressIndicator.hidden = YES;
            [IGNotificationView showInView:self.view message:[lang t:@"lib_empty"] isError:YES];
            return;
        }
        
        self.statusLabel.stringValue = [lang t:@"asking_ai"];
        self.progressIndicator.indeterminate = YES;
        [self.progressIndicator startAnimation:nil];
        
        NSArray *shuffledTracks = [tracks sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            return arc4random_uniform(3) - 1;
        }];
        
        NSInteger maxSample = 500;
        NSArray *limitedSample = [shuffledTracks subarrayWithRange:NSMakeRange(0, MIN(tracks.count, maxSample))];
        
        NSMutableArray *sampleStrings = [NSMutableArray array];
        for (IGTrack *t in limitedSample) {
            [sampleStrings addObject:[NSString stringWithFormat:@"%@|%@|%@|%@|%ld", t.persistentID, t.artist, t.name, t.genre, (long)t.year]];
        }
        
        [[IGAIService sharedService] generatePlaylistWithPrompt:self.promptField.stringValue
                                                           count:[self.countField integerValue]
                                                   librarySample:sampleStrings
                                                      completion:^(NSArray *suggestedIDs) {
            [self.progressIndicator stopAnimation:nil];
            self.progressIndicator.indeterminate = NO;
            
            if (!suggestedIDs || suggestedIDs.count == 0) {
                self.statusLabel.stringValue = [lang t:@"ai_fail"];
                [self finishGeneration];
                [IGNotificationView showInView:self.view message:[lang t:@"ai_fail"] isError:YES];
                return;
            }
            
            self.statusLabel.stringValue = [lang t:@"creating_playlist"];
            
            [[IGiTunesService sharedService] createPlaylistWithName:self.playlistNameField.stringValue
                                                      persistentIDs:suggestedIDs
                                                         completion:^(NSInteger addedCount) {
                if (addedCount <= 0) {
                    self.statusLabel.stringValue = [lang.selectedLanguage isEqualToString:@"ru"] ?
                        @"Плейлист не создан: iTunes не добавил ни одного трека." :
                        @"Playlist was not created: iTunes added zero tracks.";
                    [self finishGeneration];
                    self.progressIndicator.hidden = YES;
                    [IGNotificationView showInView:self.view message:self.statusLabel.stringValue isError:YES];
                    return;
                }
                NSString *successMsg = [lang t:@"success_added" args:@[@((long)addedCount)]];
                self.statusLabel.stringValue = successMsg;
                [self finishGeneration];
                self.progressIndicator.hidden = YES;
                
                [IGNotificationView showInView:self.view message:successMsg isError:NO];
            }];
        }];
    }];
    }];
}

- (void)helpClicked:(id)sender {
    (void)sender;
    if (self.helpSheetWindow) return;
    NSArray *sections = @[
        IGHelpSectionMake(@"Prepare", @"Save a valid AI provider key in Settings, make sure iTunes is running, and choose a name for the new playlist."),
        IGHelpSectionMake(@"Describe the selection", @"Write a clear mood, activity, style, or genre request and choose the desired track count. Syncrosa sends library metadata, not audio files."),
        IGHelpSectionMake(@"Review the result", @"The provider returns matching tracks from your library. Syncrosa creates and fills the playlist only after a usable selection is received.")
    ];
    self.helpSheetWindow = [IGHelpSheetPresenter sheetWithTitle:@"AI Playlist Generator"
                                                        summary:@"Build a playlist from your own iTunes library using the provider configured in Settings."
                                                       sections:sections
                                                     closeTitle:@"Close"
                                                         target:self
                                                         action:@selector(closeHelpSheet:)];
    [IGHelpSheetPresenter presentSheet:self.helpSheetWindow forWindow:self.view.window];
}

- (void)closeHelpSheet:(id)sender {
    if (self.helpSheetWindow) {
        if ([self.view.window respondsToSelector:@selector(endSheet:)]) {
            [self.view.window endSheet:self.helpSheetWindow];
        } else {
            [NSApp endSheet:self.helpSheetWindow];
        }
        [self.helpSheetWindow orderOut:nil];
        self.helpSheetWindow = nil;
    }
}

@end

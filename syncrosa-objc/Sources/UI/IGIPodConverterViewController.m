#import "IGIPodConverterViewController.h"
#import "IGIPodCompatibilityService.h"
#import "IGiTunesService.h"
#import "IGLocalizationService.h"
#import "IGTheme.h"
#import <math.h>

@interface IGIPodConverterViewController ()
@property (nonatomic, strong) NSArray *selectedFiles;
@property (nonatomic, strong) NSURL *outputDirectory;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *descriptionLabel;
@property (nonatomic, strong) NSTextField *filesLabel;
@property (nonatomic, strong) NSTextField *outputLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *phaseLabel;
@property (nonatomic, strong) NSTextField *percentageLabel;
@property (nonatomic, strong) NSTextField *metricsLabel;
@property (nonatomic, strong) NSTextField *profileLabel;
@property (nonatomic, strong) NSButton *selectFilesButton;
@property (nonatomic, strong) NSButton *selectOutputButton;
@property (nonatomic, strong) NSButton *convertButton;
@property (nonatomic, strong) NSPopUpButton *modePopUpButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSBox *selectionBox;
@property (nonatomic, strong) NSBox *progressBox;
@property (nonatomic, strong) NSDate *conversionStartDate;
@property (nonatomic, assign) BOOL converting;
- (NSBox *)panelWithFrame:(NSRect)frame;
@end

@implementation IGIPodConverterViewController

- (void)loadView {
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 480)] autorelease];

    self.titleLabel = [self labelWithFrame:NSMakeRect(30, 427, 520, 30)
                                      font:[NSFont boldSystemFontOfSize:18.0]
                                 alignment:NSCenterTextAlignment];
    [self.view addSubview:self.titleLabel];

    self.descriptionLabel = [self labelWithFrame:NSMakeRect(55, 382, 470, 38)
                                            font:[NSFont systemFontOfSize:12.0]
                                       alignment:NSCenterTextAlignment];
    [[self.descriptionLabel cell] setWraps:YES];
    [self.view addSubview:self.descriptionLabel];

    self.selectionBox = [self panelWithFrame:NSMakeRect(45, 232, 490, 145)];
    [self.view addSubview:self.selectionBox];

    self.modePopUpButton = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(65, 337, 450, 26)
                                                      pullsDown:NO] autorelease];
    self.modePopUpButton.target = self;
    self.modePopUpButton.action = @selector(modeChanged:);
    [self.view addSubview:self.modePopUpButton];

    self.selectFilesButton = [[[NSButton alloc] initWithFrame:NSMakeRect(65, 294, 210, 32)] autorelease];
    self.selectFilesButton.bezelStyle = NSRoundedBezelStyle;
    self.selectFilesButton.target = self;
    self.selectFilesButton.action = @selector(selectFilesClicked:);
    [self.view addSubview:self.selectFilesButton];

    self.selectOutputButton = [[[NSButton alloc] initWithFrame:NSMakeRect(305, 294, 210, 32)] autorelease];
    self.selectOutputButton.bezelStyle = NSRoundedBezelStyle;
    self.selectOutputButton.target = self;
    self.selectOutputButton.action = @selector(selectOutputClicked:);
    [self.view addSubview:self.selectOutputButton];

    self.filesLabel = [self labelWithFrame:NSMakeRect(65, 264, 450, 20)
                                      font:[NSFont systemFontOfSize:11.0]
                                 alignment:NSLeftTextAlignment];
    [[self.filesLabel cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [self.view addSubview:self.filesLabel];

    self.outputLabel = [self labelWithFrame:NSMakeRect(65, 239, 450, 20)
                                       font:[NSFont systemFontOfSize:11.0]
                                  alignment:NSLeftTextAlignment];
    [[self.outputLabel cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [self.view addSubview:self.outputLabel];

    self.progressBox = [self panelWithFrame:NSMakeRect(45, 42, 490, 187)];
    [self.view addSubview:self.progressBox];

    self.phaseLabel = [self labelWithFrame:NSMakeRect(65, 198, 350, 18)
                                      font:[NSFont boldSystemFontOfSize:10.0]
                                 alignment:NSLeftTextAlignment];
    [self.view addSubview:self.phaseLabel];

    self.percentageLabel = [self labelWithFrame:NSMakeRect(415, 181, 100, 34)
                                           font:[NSFont boldSystemFontOfSize:24.0]
                                      alignment:NSRightTextAlignment];
    [self.view addSubview:self.percentageLabel];

    self.statusLabel = [self labelWithFrame:NSMakeRect(65, 169, 345, 22)
                                       font:[NSFont systemFontOfSize:12.0]
                                  alignment:NSLeftTextAlignment];
    [[self.statusLabel cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [self.view addSubview:self.statusLabel];

    self.progressIndicator = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(65, 139, 450, 18)] autorelease];
    self.progressIndicator.style = NSProgressIndicatorBarStyle;
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.minValue = 0.0;
    self.progressIndicator.maxValue = 100.0;
    self.progressIndicator.doubleValue = 0.0;
    self.progressIndicator.displayedWhenStopped = YES;
    [self.view addSubview:self.progressIndicator];

    self.metricsLabel = [self labelWithFrame:NSMakeRect(65, 111, 450, 18)
                                        font:[NSFont systemFontOfSize:10.0]
                                   alignment:NSCenterTextAlignment];
    [self.view addSubview:self.metricsLabel];

    self.profileLabel = [self labelWithFrame:NSMakeRect(65, 88, 450, 18)
                                        font:[NSFont systemFontOfSize:10.0]
                                   alignment:NSCenterTextAlignment];
    [self.view addSubview:self.profileLabel];

    self.convertButton = [[[NSButton alloc] initWithFrame:NSMakeRect(190, 51, 200, 34)] autorelease];
    self.convertButton.bezelStyle = NSTexturedRoundedBezelStyle;
    self.convertButton.target = self;
    self.convertButton.action = @selector(convertClicked:);
    [self.view addSubview:self.convertButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localizationChanged:)
                                                 name:@"IGLanguageChangedNotification"
                                               object:nil];
    [self updateLocalization];
    [self updateControls];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
    [_selectedFiles release];
    [_outputDirectory release];
    [_titleLabel release];
    [_descriptionLabel release];
    [_filesLabel release];
    [_outputLabel release];
    [_statusLabel release];
    [_phaseLabel release];
    [_percentageLabel release];
    [_metricsLabel release];
    [_profileLabel release];
    [_selectFilesButton release];
    [_selectOutputButton release];
    [_convertButton release];
    [_modePopUpButton release];
    [_progressIndicator release];
    [_selectionBox release];
    [_progressBox release];
    [_conversionStartDate release];
    [super dealloc];
#endif
}

- (NSBox *)panelWithFrame:(NSRect)frame {
    NSBox *box = [[[NSBox alloc] initWithFrame:frame] autorelease];
    box.boxType = NSBoxCustom;
    box.borderType = NSLineBorder;
    box.borderWidth = 1.0;
    box.cornerRadius = 8.0;
    box.borderColor = IGThemeControlBorderColor();
    box.fillColor = IGThemePanelColor();
    return box;
}

- (NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.font = font;
    label.textColor = IGThemeTextColor();
    label.alignment = alignment;
    return label;
}

- (BOOL)isRussian {
    return [[[IGLocalizationService sharedService] selectedLanguage] isEqualToString:@"ru"];
}

- (void)updateLocalization {
    BOOL russian = [self isRussian];
    NSInteger selectedMode = [self.modePopUpButton indexOfSelectedItem];
    [self.modePopUpButton removeAllItems];
    [self.modePopUpButton addItemsWithTitles:[NSArray arrayWithObjects:
        (russian ? @"Режим: создать совместимую копию" : @"Mode: Create a compatible copy"),
        (russian ? @"Режим: заменить M4A-трек в iTunes" : @"Mode: Replace an M4A track in iTunes"),
        nil]];
    [self.modePopUpButton selectItemAtIndex:MAX(0, selectedMode)];
    self.titleLabel.stringValue = russian ? @"Конвертер для iPod" : @"iPod Converter";
    self.descriptionLabel.stringValue = russian
        ? @"Готовит M4A для старых iPod. ALAC остаётся lossless ALAC без потери качества."
        : @"Creates M4A files for older iPods. ALAC stays lossless ALAC without quality loss.";
    self.selectFilesButton.title = russian ? @"Выбрать аудиофайлы" : @"Choose Audio Files";
    self.selectOutputButton.title = russian ? @"Выбрать папку" : @"Choose Output Folder";
    BOOL replaceMode = [self.modePopUpButton indexOfSelectedItem] == 1;
    self.convertButton.title = self.converting
        ? (russian ? @"Остановить" : @"Stop")
        : (replaceMode
            ? (russian ? @"Заменить трек в iTunes" : @"Replace Track in iTunes")
            : (russian ? @"Подготовить для iPod" : @"Prepare for iPod"));
    [self updateControls];
}

- (void)localizationChanged:(NSNotification *)notification {
    (void)notification;
    [self updateLocalization];
}

- (void)modeChanged:(id)sender {
    (void)sender;
    self.statusLabel.stringValue = @"";
    self.progressIndicator.doubleValue = 0.0;
    [self updateLocalization];
}

- (NSString *)durationStringForSeconds:(NSTimeInterval)seconds {
    NSInteger totalSeconds = MAX(0, (NSInteger)floor(seconds));
    NSInteger hours = totalSeconds / 3600;
    NSInteger minutes = (totalSeconds % 3600) / 60;
    NSInteger remainingSeconds = totalSeconds % 60;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld",
                (long)hours, (long)minutes, (long)remainingSeconds];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)remainingSeconds];
}

- (void)showProgressWithCompleted:(NSInteger)completed
                            total:(NSInteger)total
                         filename:(NSString *)filename
                     fileProgress:(double)fileProgress {
    if (total <= 0) {
        return;
    }

    double safeFileProgress = MAX(0.0, MIN(1.0, fileProgress));
    double overallProgress = MAX(0.0, MIN(1.0, ((double)completed + safeFileProgress) / (double)total));
    double percentage = floor((overallProgress * 100.0) + 0.5);
    NSTimeInterval elapsed = self.conversionStartDate ? -[self.conversionStartDate timeIntervalSinceNow] : 0.0;
    BOOL russian = [self isRussian];

    self.progressIndicator.doubleValue = overallProgress * 100.0;
    self.percentageLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", percentage];
    self.phaseLabel.stringValue = [NSString stringWithFormat:
        (russian ? @"ПЕРЕКОДИРОВАНИЕ · ФАЙЛ %ld ИЗ %ld" : @"CONVERTING · FILE %ld OF %ld"),
        (long)MIN(completed + 1, total), (long)total];
    self.statusLabel.stringValue = filename ?: @"";

    NSString *elapsedText = [self durationStringForSeconds:elapsed];
    NSString *remainingText = nil;
    if (overallProgress >= 0.005 && elapsed >= 2.0 && overallProgress < 1.0) {
        NSTimeInterval remaining = (elapsed / overallProgress) * (1.0 - overallProgress);
        remainingText = [self durationStringForSeconds:remaining];
    }

    if (overallProgress >= 1.0) {
        self.metricsLabel.stringValue = [NSString stringWithFormat:
            (russian ? @"Прошло %@ · завершение файла…" : @"Elapsed %@ · finishing file…"),
            elapsedText];
    } else if (remainingText) {
        self.metricsLabel.stringValue = [NSString stringWithFormat:
            (russian ? @"Прошло %@   ·   текущий файл %.0f%%   ·   осталось примерно %@"
                     : @"Elapsed %@   ·   current file %.0f%%   ·   about %@ remaining"),
            elapsedText, safeFileProgress * 100.0, remainingText];
    } else {
        self.metricsLabel.stringValue = [NSString stringWithFormat:
            (russian ? @"Прошло %@   ·   вычисляем оставшееся время…"
                     : @"Elapsed %@   ·   calculating remaining time…"),
            elapsedText];
    }
}

- (void)updateControls {
    BOOL russian = [self isRussian];
    NSInteger count = [self.selectedFiles count];
    BOOL replaceMode = [self.modePopUpButton indexOfSelectedItem] == 1;
    BOOL allM4A = YES;
    for (NSURL *fileURL in self.selectedFiles) {
        if (![[[fileURL pathExtension] lowercaseString] isEqualToString:@"m4a"]) {
            allM4A = NO;
            break;
        }
    }
    self.filesLabel.stringValue = count > 0
        ? [NSString stringWithFormat:(russian ? @"Аудио · %ld шт. · %@" : @"Audio · %ld selected · %@"),
           (long)count, [[self.selectedFiles objectAtIndex:0] lastPathComponent]]
        : (russian ? @"Аудио · файлы не выбраны" : @"Audio · no files selected");
    self.outputLabel.stringValue = replaceMode
        ? (russian
            ? @"Резервная копия · рядом с оригиналом, с пометкой Syncrosa Backup"
            : @"Backup · beside the original, marked Syncrosa Backup")
        : (self.outputDirectory
            ? [NSString stringWithFormat:(russian ? @"Куда · %@" : @"Output · %@"), [self.outputDirectory path]]
            : (russian ? @"Куда · папка не выбрана" : @"Output · no folder selected"));
    self.modePopUpButton.enabled = !self.converting;
    self.selectFilesButton.enabled = !self.converting;
    self.selectOutputButton.enabled = !self.converting && !replaceMode;
    self.convertButton.enabled = self.converting ||
        (count > 0 && (replaceMode ? allM4A : self.outputDirectory != nil));
    self.selectionBox.borderColor = IGThemeControlBorderColor();
    self.selectionBox.fillColor = IGThemePanelColor();
    self.progressBox.borderColor = self.converting ? IGThemeAccentColor() : IGThemeControlBorderColor();
    self.progressBox.fillColor = IGThemePanelColor();
    self.phaseLabel.textColor = self.converting ? IGThemeAccentColor() : IGThemeMutedTextColor();
    self.metricsLabel.textColor = IGThemeMutedTextColor();
    self.profileLabel.textColor = IGThemeMutedTextColor();
    self.profileLabel.stringValue = replaceMode
        ? (russian
            ? @"M4A · метаданные и обложка iTunes сохраняются · оригинал резервируется"
            : @"M4A · iTunes metadata and artwork preserved · original backed up")
        : (russian
            ? @"ALAC → ALAC без потерь · остальные форматы → AAC · оригиналы не меняются"
            : @"ALAC → lossless ALAC · other formats → AAC · originals untouched");
    if (!self.converting && [self.statusLabel.stringValue length] == 0) {
        self.phaseLabel.stringValue = russian ? @"ГОТОВО К ЗАПУСКУ" : @"READY TO CONVERT";
        self.statusLabel.stringValue = replaceMode
            ? (allM4A
                ? (russian ? @"Выберите M4A-файлы, уже добавленные в iTunes"
                           : @"Choose M4A files already present in iTunes")
                : (russian ? @"Для замены в iTunes выберите только M4A-файлы"
                           : @"Replace in iTunes accepts M4A files only"))
            : (russian ? @"Выберите аудио и папку назначения"
                       : @"Choose audio files and an output folder");
        self.percentageLabel.stringValue = @"—";
        self.percentageLabel.hidden = YES;
        self.progressIndicator.hidden = YES;
        self.metricsLabel.stringValue = russian
            ? @"Прогресс и оставшееся время появятся после запуска"
            : @"Progress and remaining time will appear after conversion starts";
    }
    IGApplyThemeToButton(self.selectFilesButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.selectOutputButton, IGThemeButtonRoleSecondary);
    IGApplyThemeToButton(self.convertButton, IGThemeButtonRolePrimary);
}

- (void)selectFilesClicked:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.allowedFileTypes = @[@"mp3", @"m4a", @"mp4", @"aac", @"wav", @"aiff", @"aif", @"caf"];
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        self.selectedFiles = [panel URLs];
        self.statusLabel.stringValue = @"";
        [self updateControls];
    }
}

- (void)selectOutputClicked:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = YES;
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        self.outputDirectory = [panel URL];
        self.statusLabel.stringValue = @"";
        [self updateControls];
    }
}

- (void)convertClicked:(id)sender {
    (void)sender;
    if (self.converting) {
        [[IGIPodCompatibilityService sharedService] cancelConversion];
        return;
    }
    BOOL replaceMode = [self.modePopUpButton indexOfSelectedItem] == 1;
    if ([self.selectedFiles count] == 0 || (!replaceMode && !self.outputDirectory)) {
        return;
    }

    if (replaceMode) {
        BOOL russian = [self isRussian];
        for (NSURL *fileURL in self.selectedFiles) {
            if (![[[fileURL pathExtension] lowercaseString] isEqualToString:@"m4a"]) {
                NSAlert *formatAlert = [[[NSAlert alloc] init] autorelease];
                formatAlert.messageText = russian
                    ? @"Замена поддерживается только для M4A"
                    : @"Replacement supports M4A files only";
                formatAlert.informativeText = russian
                    ? @"Для MP3, WAV и других форматов используйте режим создания отдельной копии."
                    : @"Use Create Copy for MP3, WAV, and other source formats.";
                [formatAlert runModal];
                return;
            }
        }

        if (![[IGiTunesService sharedService] iTunesIsRunning]) {
            NSAlert *launchAlert = [[[NSAlert alloc] init] autorelease];
            launchAlert.messageText = russian ? @"Для замены нужен iTunes" : @"iTunes is required";
            launchAlert.informativeText = russian
                ? @"Syncrosa найдёт исходную запись трека и сохранит её метаданные и обложку."
                : @"Syncrosa uses the existing track entry to preserve its metadata and artwork.";
            [launchAlert addButtonWithTitle:(russian ? @"Открыть iTunes и продолжить" : @"Open iTunes and Continue")];
            [launchAlert addButtonWithTitle:(russian ? @"Отмена" : @"Cancel")];
            if ([launchAlert runModal] != NSAlertFirstButtonReturn ||
                ![[IGiTunesService sharedService] launchITunesForUserActionWithOperation:@"iPod track replacement"]) {
                return;
            }
        }

        NSAlert *confirmAlert = [[[NSAlert alloc] init] autorelease];
        confirmAlert.alertStyle = NSWarningAlertStyle;
        confirmAlert.messageText = russian
            ? @"Заменить выбранные треки?"
            : @"Replace the selected tracks?";
        confirmAlert.informativeText = russian
            ? @"Каждый исходный M4A будет сохранён рядом как «Syncrosa Backup». Путь трека в iTunes останется прежним; название, исполнитель, альбом, номера и обложка будут применены к новому файлу."
            : @"Each original M4A will be saved beside it as “Syncrosa Backup”. Its iTunes path stays the same, and the title, artist, album, numbering, and artwork are reapplied to the new file.";
        [confirmAlert addButtonWithTitle:(russian ? @"Заменить с резервной копией" : @"Replace with Backup")];
        [confirmAlert addButtonWithTitle:(russian ? @"Отмена" : @"Cancel")];
        if ([confirmAlert runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }

    self.converting = YES;
    self.conversionStartDate = [NSDate date];
    self.percentageLabel.hidden = NO;
    self.progressIndicator.hidden = NO;
    self.progressIndicator.doubleValue = 0.0;
    self.progressIndicator.maxValue = 100.0;
    self.statusLabel.stringValue = [self isRussian] ? @"Подготовка аудиодвижка…" : @"Preparing the audio engine…";
    [self updateLocalization];
    self.phaseLabel.stringValue = [self isRussian] ? @"ПОДГОТОВКА" : @"PREPARING";
    self.percentageLabel.stringValue = @"0%";
    self.metricsLabel.stringValue = [self isRussian]
        ? @"Считываем параметры исходного файла…"
        : @"Reading the source audio format…";

    NSURL *conversionDirectory = replaceMode
        ? [[self.selectedFiles objectAtIndex:0] URLByDeletingLastPathComponent]
        : self.outputDirectory;
    [[IGIPodCompatibilityService sharedService] convertFiles:self.selectedFiles
                                                toDirectory:conversionDirectory
                                                       mode:(replaceMode
                                                           ? IGIPodConversionModeReplaceITunesTrack
                                                           : IGIPodConversionModeCreateCopy)
                                                   progress:^(NSInteger completed,
                                                              NSInteger total,
                                                              NSString *filename,
                                                              double fileProgress) {
        [self showProgressWithCompleted:completed
                                  total:total
                               filename:filename
                           fileProgress:fileProgress];
    } completion:^(NSArray *convertedFiles, NSArray *failures, BOOL cancelled) {
        self.converting = NO;
        [self updateLocalization];
        self.percentageLabel.hidden = NO;
        self.progressIndicator.hidden = NO;
        BOOL russian = [self isRussian];
        NSTimeInterval elapsed = self.conversionStartDate ? -[self.conversionStartDate timeIntervalSinceNow] : 0.0;
        self.metricsLabel.stringValue = [NSString stringWithFormat:
            (russian ? @"Общее время: %@" : @"Total time: %@"),
            [self durationStringForSeconds:elapsed]];
        if (cancelled) {
            self.phaseLabel.stringValue = russian ? @"ОСТАНОВЛЕНО" : @"STOPPED";
            self.percentageLabel.stringValue = @"—";
            self.statusLabel.stringValue = [NSString stringWithFormat:
                (russian ? @"Остановлено. Готово файлов: %ld." : @"Stopped. Converted files: %ld."),
                (long)[convertedFiles count]];
        } else if ([failures count] == 0) {
            self.phaseLabel.stringValue = russian ? @"ГОТОВО" : @"COMPLETE";
            self.percentageLabel.stringValue = @"100%";
            self.progressIndicator.doubleValue = 100.0;
            self.statusLabel.stringValue = [NSString stringWithFormat:
                (replaceMode
                    ? (russian
                        ? @"Готово. Заменено треков: %ld. Оригиналы сохранены как Syncrosa Backup."
                        : @"Done. Replaced tracks: %ld. Originals were saved as Syncrosa Backup.")
                    : (russian
                        ? @"Готово. Создано совместимых файлов: %ld."
                        : @"Done. Compatible files created: %ld.")),
                (long)[convertedFiles count]];
        } else {
            self.phaseLabel.stringValue = russian ? @"ЗАВЕРШЕНО С ОШИБКАМИ" : @"COMPLETED WITH ISSUES";
            self.percentageLabel.stringValue = @"!";
            NSDictionary *firstFailure = [failures objectAtIndex:0];
            self.statusLabel.stringValue = [NSString stringWithFormat:
                (russian ? @"Создано: %ld. Не удалось: %ld. %@" : @"Created: %ld. Failed: %ld. %@"),
                (long)[convertedFiles count], (long)[failures count],
                [firstFailure objectForKey:@"message"] ?: @""];
        }
    }];
}

@end

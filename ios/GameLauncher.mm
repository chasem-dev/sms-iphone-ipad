#import "GameLauncher.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>
#include "../native/DiscImage.h"
#include <algorithm>
#include <cstdlib>

static NSURL* DiscURL()
{
    NSURL* documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    return [[documents URLByAppendingPathComponent:@"Game" isDirectory:YES] URLByAppendingPathComponent:@"disc.gcm"];
}

static NSURL* ImportStagingURL()
{
    return [[DiscURL() URLByDeletingLastPathComponent] URLByAppendingPathComponent:@".import-disc.gcm"];
}

NSURL* SMSGameDiscURL(void)
{
    NSURL* installed = DiscURL();
    if ([NSFileManager.defaultManager fileExistsAtPath:installed.path]) return installed;
    NSBundle* bundle = NSBundle.mainBundle;
    if ([[bundle objectForInfoDictionaryKey:@"SMSLocalOnly"] isEqual:@YES]
        && [[bundle objectForInfoDictionaryKey:@"SMSLocalBundledDisc"] isEqual:@"LocalGame/disc.gcm"]) {
        return [bundle.bundleURL URLByAppendingPathComponent:@"LocalGame/disc.gcm"];
    }
    return installed;
}

static UIColor* Navy() { return [UIColor colorWithRed:0.04 green:0.16 blue:0.25 alpha:1]; }
static UIColor* Gold() { return [UIColor colorWithRed:1 green:0.79 blue:0.33 alpha:1]; }

static void RegisterSettings()
{
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"ios.resolution": @1, @"ios.widescreen": @NO, @"ios.frameRate": @60,
        @"ios.volume": @100, @"ios.touchControls": @YES, @"ios.touchOpacity": @0.55,
        @"ios.invertX": @NO, @"ios.invertY": @NO, @"ios.skipIntro": @YES, @"ios.skipMovies": @YES
    }];
}

void SMSApplyGameSettings(void)
{
    RegisterSettings();
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSInteger resolution = std::clamp<NSInteger>([defaults integerForKey:@"ios.resolution"], 1, 4);
    NSInteger rate = [defaults integerForKey:@"ios.frameRate"] == 30 ? 30 : 60;
    NSInteger volume = std::clamp<NSInteger>([defaults integerForKey:@"ios.volume"], 0, 100);
    NSDictionary<NSString*, NSString*>* environment = @{
        @"SMS_GX_SCALE": [@(resolution) stringValue],
        @"SMS_WIDESCREEN": [defaults boolForKey:@"ios.widescreen"] ? @"16:9" : @"off",
        @"SMS_FRAME_RATE": [@(rate) stringValue], @"SMS_VOLUME": [@(volume) stringValue],
        @"SMS_CAMERA_INVERT_X": [defaults boolForKey:@"ios.invertX"] ? @"1" : @"0",
        @"SMS_CAMERA_INVERT_Y": [defaults boolForKey:@"ios.invertY"] ? @"1" : @"0",
        @"SMS_SKIP_INTRO": [defaults boolForKey:@"ios.skipIntro"] ? @"1" : @"0",
        @"SMS_SKIP_MOVIES": [defaults boolForKey:@"ios.skipMovies"] ? @"1" : @"0",
        @"SMS_BUTTON_PROMPTS": @"gamecube", @"SMS_VSYNC": @"on"
    };
    for (NSString* key in environment) setenv(key.UTF8String, environment[key].UTF8String, 1);
    NSMutableDictionary* report = [environment mutableCopy];
    report[@"touchControls"] = [defaults boolForKey:@"ios.touchControls"] ? @"on" : @"off";
    report[@"touchOpacity"] = [@([defaults doubleForKey:@"ios.touchOpacity"]) stringValue];
    NSURL* output = [[DiscURL() URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    NSData* data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToURL:[output URLByAppendingPathComponent:@"launcher-settings.json"] options:NSDataWritingAtomic error:nil];
}

@interface SMSGameSettings : UITableViewController
@end

@implementation SMSGameSettings
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Settings";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView { return 4; }
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 2 : section == 1 ? 5 : section == 2 ? 2 : 1;
}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    return @[@"Graphics", @"Gameplay", @"Controls", @"Audio"][section];
}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section
{
    return @[@"Higher sharpness needs more GPU memory. Metal rendering uses MoltenVK.",
        @"Changes apply when you choose Play. Quit and relaunch the app to return to the launcher.",
        @"GameCube layout: analog stick, C stick, D-pad, A/B/X/Y, L/R/Z and Start. Physical controllers use SDL mappings.",
        @"Audio quality is still experimental on the simulator."][section];
}
- (void)changed:(UIControl*)control
{
    NSString* key = control.accessibilityIdentifier;
    if ([control isKindOfClass:UISwitch.class]) {
        [NSUserDefaults.standardUserDefaults setBool:((UISwitch*)control).on forKey:key];
    } else if ([control isKindOfClass:UISlider.class]) {
        float value = ((UISlider*)control).value;
        if ([key isEqualToString:@"ios.volume"]) [NSUserDefaults.standardUserDefaults setInteger:lroundf(value) forKey:key];
        else [NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    } else {
        NSInteger index = ((UISegmentedControl*)control).selectedSegmentIndex;
        if ([key isEqualToString:@"ios.resolution"]) [NSUserDefaults.standardUserDefaults setInteger:index + 1 forKey:key];
        else if ([key isEqualToString:@"ios.frameRate"]) [NSUserDefaults.standardUserDefaults setInteger:index == 0 ? 30 : 60 forKey:key];
        else [NSUserDefaults.standardUserDefaults setBool:index == 1 forKey:key];
    }
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSInteger section = indexPath.section, row = indexPath.row;
    NSString* title;
    NSString* key;
    NSArray* choices;
    if (section == 0) {
        title = row == 0 ? @"Picture sharpness" : @"Aspect ratio";
        key = row == 0 ? @"ios.resolution" : @"ios.widescreen";
        choices = row == 0 ? @[@"1×", @"2×", @"3×", @"4×"] : @[@"4:3", @"16:9"];
    } else if (section == 1) {
        title = @[@"Frame rate", @"Invert camera X", @"Invert camera Y", @"Skip intro", @"Skip movies"][row];
        key = @[@"ios.frameRate", @"ios.invertX", @"ios.invertY", @"ios.skipIntro", @"ios.skipMovies"][row];
        if (row == 0) choices = @[@"30", @"60"];
    } else if (section == 2) {
        title = row == 0 ? @"Touch screen controls" : @"Touch opacity";
        key = row == 0 ? @"ios.touchControls" : @"ios.touchOpacity";
    } else {
        title = @"Master volume";
        key = @"ios.volume";
    }
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    UIControl* input;
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    if (choices) {
        UISegmentedControl* segments = [[UISegmentedControl alloc] initWithItems:choices];
        segments.selectedSegmentIndex = [key isEqualToString:@"ios.resolution"] ? [defaults integerForKey:key] - 1
            : [key isEqualToString:@"ios.frameRate"] ? ([defaults integerForKey:key] == 30 ? 0 : 1) : [defaults boolForKey:key];
        segments.frame = CGRectMake(0, 0, choices.count * 48, 32);
        [segments addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
        input = segments;
    } else if ([key isEqualToString:@"ios.volume"] || [key isEqualToString:@"ios.touchOpacity"]) {
        UISlider* slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 155, 32)];
        slider.minimumValue = [key isEqualToString:@"ios.volume"] ? 0 : 0.2;
        slider.maximumValue = [key isEqualToString:@"ios.volume"] ? 100 : 1;
        slider.value = [defaults floatForKey:key];
        [slider addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
        input = slider;
    } else {
        UISwitch* toggle = [[UISwitch alloc] init];
        toggle.on = [defaults boolForKey:key];
        [toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
        input = toggle;
    }
    input.accessibilityIdentifier = key;
    input.accessibilityLabel = title;
    cell.accessoryView = input;
    return cell;
}
@end

@interface SMSGameLauncher : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic) BOOL readyToStart;
@property(nonatomic) BOOL importing;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic, strong) UIButton* play;
@property(nonatomic, strong) UIButton* settings;
@property(nonatomic, strong) UIButton* importButton;
@property(nonatomic, strong) CAGradientLayer* gradient;
@end

@implementation SMSGameLauncher
- (UILabel*)label:(NSString*)text size:(CGFloat)size weight:(UIFontWeight)weight
{
    UILabel* label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.numberOfLines = 0;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.65;
    return label;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.gradient = [CAGradientLayer layer];
    self.gradient.colors = @[(id)Navy().CGColor, (id)[UIColor colorWithRed:0.04 green:0.47 blue:0.67 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.03 green:0.69 blue:0.68 alpha:1].CGColor];
    [self.view.layer insertSublayer:self.gradient atIndex:0];
    UILabel* brand = [self label:@"✦  SMS LAUNCHER" size:17 weight:UIFontWeightHeavy];
    UILabel* subtitle = [self label:@"NATIVE iPHONE + iPAD · EXPERIMENTAL" size:11 weight:UIFontWeightSemibold];
    UILabel* title = [self label:@"Super Mario Sunshine" size:34 weight:UIFontWeightHeavy];
    UILabel* detail = [self label:@"Your island. Your settings. Ready when you are." size:16 weight:UIFontWeightMedium];
    self.status = [self label:@"" size:13 weight:UIFontWeightMedium];
    self.status.accessibilityIdentifier = @"launcher.status";
    self.play = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.play setTitle:@"▶  Play" forState:UIControlStateNormal];
    [self.play setTitleColor:Navy() forState:UIControlStateNormal];
    self.play.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightHeavy];
    self.play.backgroundColor = Gold();
    self.play.layer.cornerRadius = 18;
    self.play.accessibilityIdentifier = @"launcher.play";
    [self.play addTarget:self action:@selector(startGame) forControlEvents:UIControlEventTouchUpInside];
    self.settings = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.settings setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    self.settings.tintColor = UIColor.whiteColor;
    self.settings.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.13];
    self.settings.layer.cornerRadius = 18;
    self.settings.accessibilityIdentifier = @"launcher.settings";
    self.settings.accessibilityLabel = @"Settings";
    [self.settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.importButton setTitle:@"Import / replace game image" forState:UIControlStateNormal];
    [self.importButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.importButton.accessibilityIdentifier = @"launcher.import";
    [self.importButton addTarget:self action:@selector(importImage) forControlEvents:UIControlEventTouchUpInside];
    UIStackView* actions = [[UIStackView alloc] initWithArrangedSubviews:@[self.play, self.settings]];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 12;
    [self.settings.widthAnchor constraintEqualToConstant:68].active = YES;
    [actions.heightAnchor constraintEqualToConstant:64].active = YES;
    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[brand, subtitle, title, detail, actions, self.status, self.importButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    [stack setCustomSpacing:12 afterView:subtitle];
    [stack setCustomSpacing:16 afterView:detail];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint* width = [stack.widthAnchor constraintEqualToConstant:820];
    width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor], [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-24],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:8],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-8], width]];
    [self refresh];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.gradient.frame = self.view.bounds; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (void)refresh
{
    if (self.importing) return;
    try {
        const auto image = sms::inspectDiscImage(SMSGameDiscURL().fileSystemRepresentation);
        self.status.text = [NSString stringWithFormat:@"● Ready to play · GMSE01 · %.0f MB · Your disc stays on this device", image.size / 1000000.0];
        self.play.enabled = YES;
        self.play.alpha = 1;
    } catch (const std::exception&) {
        self.status.text = @"Bring your own GMSE01 revision 0 ISO/GCM to begin. No game data is included.";
        self.play.enabled = NO;
        self.play.alpha = 0.5;
    }
}
- (void)openSettings
{
    SMSGameSettings* settings = [[SMSGameSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)startGame
{
    if (self.importing || self.readyToStart) return;
    try {
        sms::inspectDiscImage(SMSGameDiscURL().fileSystemRepresentation);
        SMSApplyGameSettings();
        self.readyToStart = YES;
    } catch (const std::exception&) {
        [self refresh];
    }
}
- (void)importImage
{
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController*)picker didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    NSURL* source = urls.firstObject;
    if (!source || self.importing) return;
    self.importing = YES;
    self.play.enabled = self.importButton.enabled = self.settings.enabled = NO;
    self.status.text = @"Validating and copying your game image… Keep the app open.";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [source startAccessingSecurityScopedResource];
        __block NSString* failure;
        NSError* coordinationError;
        NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:source options:0 error:&coordinationError byAccessor:^(NSURL* readable) {
            NSFileManager* manager = NSFileManager.defaultManager;
            NSURL* directory = [DiscURL() URLByDeletingLastPathComponent];
            NSURL* temporary = ImportStagingURL();
            [manager removeItemAtURL:temporary error:nil];
            NSError* error;
            try {
                sms::inspectDiscImage(readable.fileSystemRepresentation);
                BOOL installed = NO;
                if ([manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]
                    && [manager copyItemAtURL:readable toURL:temporary error:&error]) {
                    sms::inspectDiscImage(temporary.fileSystemRepresentation);
                    installed = [manager fileExistsAtPath:DiscURL().path]
                        ? [manager replaceItemAtURL:DiscURL() withItemAtURL:temporary backupItemName:nil options:0 resultingItemURL:nil error:&error]
                        : [manager moveItemAtURL:temporary toURL:DiscURL() error:&error];
                }
                if (!installed) failure = error.localizedDescription ?: @"Could not install this image.";
                else [DiscURL() setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
            } catch (const std::exception& exception) {
                failure = [NSString stringWithUTF8String:exception.what()];
            }
            [manager removeItemAtURL:temporary error:nil];
        }];
        if (scoped) [source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.importing = NO;
            self.importButton.enabled = self.settings.enabled = YES;
            [self refresh];
            NSString* message = coordinationError.localizedDescription ?: failure;
            if (message) {
                UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Import failed" message:message preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}
@end

void SMSPresentGameLauncher(void)
{
    RegisterSettings();
    [NSFileManager.defaultManager removeItemAtURL:ImportStagingURL() error:nil];
    if (const char* automated = getenv("SMS_IOS_AUTOLAUNCH")) {
        if (!strcmp(automated, "1")) {
            try { sms::inspectDiscImage(SMSGameDiscURL().fileSystemRepresentation); SMSApplyGameSettings(); return; }
            catch (const std::exception&) {}
        }
    }
    SMSGameLauncher* launcher = [[SMSGameLauncher alloc] init];
    UIWindow* window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.rootViewController = launcher;
    [window makeKeyAndVisible];
    while (!launcher.readyToStart) {
        @autoreleasepool { [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
    }
    window.hidden = YES;
    window.rootViewController = nil;
}

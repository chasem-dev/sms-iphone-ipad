#import <GameController/GameController.h>
#import <MetalKit/MetalKit.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "DiscImage.h"
#import "MemoryProbe.h"
#import "MetalRenderer.h"
#include <exception>

static NSURL* GameDirectory()
{
    NSURL* documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    return [documents URLByAppendingPathComponent:@"Game" isDirectory:YES];
}

static NSString* InspectImage(NSURL* url)
{
    try {
        const auto image = sms::inspectDiscImage(url.fileSystemRepresentation);
        return [NSString stringWithFormat:@"GMSE01 imported · %.0f MB", image.size / 1000000.0];
    } catch (const std::exception& error) {
        return [NSString stringWithUTF8String:error.what()];
    }
}

@interface SunshineController : UIViewController <MTKViewDelegate, UIDocumentPickerDelegate>
@property(nonatomic, strong) MTKView* metalView;
@property(nonatomic, strong) SMSMetalRenderer* renderer;
@property(nonatomic, strong) UILabel* imageStatus;
@property(nonatomic, strong) UILabel* controllerStatus;
@property(nonatomic, strong) UIButton* importButton;
@property(nonatomic, strong) UIButton* probeButton;
@property(nonatomic, strong) UILabel* memoryStatus;
@property(nonatomic, strong) UILabel* graphicsStatus;
@property(nonatomic, strong) UIButton* graphicsButton;
@property(nonatomic, copy) NSString* verificationIdentifier;
@end

@implementation SunshineController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"Sunshine · iPhone & iPad";

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    NSError* graphicsError = nil;
    self.renderer = [[SMSMetalRenderer alloc] initWithDevice:device error:&graphicsError];
    self.metalView = [[MTKView alloc] initWithFrame:CGRectZero device:device];
    self.metalView.delegate = self;
    self.metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    self.metalView.sampleCount = 1;
    self.metalView.paused = YES;
    self.metalView.preferredFramesPerSecond = 30;
    self.metalView.clearColor = MTLClearColorMake(0.03, 0.15, 0.22, 1.0);
    self.metalView.translatesAutoresizingMaskIntoConstraints = NO;
    self.metalView.layer.cornerRadius = 18;
    self.metalView.clipsToBounds = YES;
    self.metalView.accessibilityLabel = @"Metal renderer diagnostic, not gameplay";

    UILabel* heading = [self label:@"Native iOS port · development build" style:UIFontTextStyleTitle2];
    UILabel* graphics = [self label:(self.renderer
        ? [NSString stringWithFormat:@"Metal ready · %@", device.name] : graphicsError.localizedDescription)
                             style:UIFontTextStyleBody];
    self.graphicsStatus = [self label:@"Host graphics: verification not run. Color tiles are diagnostics, not gameplay."
        style:UIFontTextStyleBody];
    self.graphicsStatus.accessibilityIdentifier = @"graphicsStatus";
    self.graphicsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.graphicsButton setTitle:@"Verify Metal Graphics" forState:UIControlStateNormal];
    [self.graphicsButton addTarget:self action:@selector(runGraphicsVerification) forControlEvents:UIControlEventTouchUpInside];
    self.imageStatus = [self label:@"Import your own GMSE01 revision 0 ISO or GCM." style:UIFontTextStyleBody];
    self.imageStatus.accessibilityIdentifier = @"discStatus";
    NSURL* installedImage = [GameDirectory() URLByAppendingPathComponent:@"disc.gcm"];
    if ([NSFileManager.defaultManager fileExistsAtPath:installedImage.path]) {
        self.imageStatus.text = InspectImage(installedImage);
    }
    self.controllerStatus = [self label:@"" style:UIFontTextStyleBody];
    UILabel* status = [self label:@"Game engine not connected yet. This build validates Metal, game import, and app distribution; it does not run Sunshine."
                           style:UIFontTextStyleBody];
    status.accessibilityIdentifier = @"engineStatus";
    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.importButton.configuration = [UIButtonConfiguration filledButtonConfiguration];
    [self.importButton setTitle:@"Import Game Image" forState:UIControlStateNormal];
    [self.importButton addTarget:self action:@selector(importImage) forControlEvents:UIControlEventTouchUpInside];
    self.memoryStatus = [self label:@"Engine memory layout: not tested on this device." style:UIFontTextStyleBody];
    self.memoryStatus.accessibilityIdentifier = @"memoryStatus";
    self.probeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.probeButton setTitle:@"Test Engine Memory Layout" forState:UIControlStateNormal];
    [self.probeButton addTarget:self action:@selector(runMemoryProbe) forControlEvents:UIControlEventTouchUpInside];

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        heading, graphics, self.metalView, self.graphicsButton, self.graphicsStatus,
        self.imageStatus, self.controllerStatus, self.importButton,
        self.probeButton, self.memoryStatus, status]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView* scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.centerXAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerXAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [self.metalView.heightAnchor constraintEqualToConstant:160]]];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateControllers)
        name:GCControllerDidConnectNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateControllers)
        name:GCControllerDidDisconnectNotification object:nil];
    [self updateControllers];
}

- (UILabel*)label:(NSString*)text style:(UIFontTextStyle)style
{
    UILabel* label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    return label;
}

- (void)updateControllers
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger count = GCController.controllers.count;
        self.controllerStatus.text = [NSString stringWithFormat:@"Controllers connected: %lu · input mapping pending", (unsigned long)count];
    });
}

- (void)importImage
{
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)runMemoryProbe
{
    self.probeButton.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary* report = SMSRunMemoryProbe();
        NSError* error = nil;
        NSURL* documents = [GameDirectory() URLByDeletingLastPathComponent];
        NSURL* output = [documents URLByAppendingPathComponent:@"memory-probe.json"];
        NSData* json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
        BOOL saved = json && [json writeToURL:output options:NSDataWritingAtomic error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL low = [report[@"lowStackSample"][@"pointerRoundTrip"] boolValue];
            BOOL mem1 = [report[@"mem1"][@"pointerRoundTrip"] boolValue];
            self.memoryStatus.text = [NSString stringWithFormat:@"Low stack sample: %@ · MEM1: %@. %@",
                low ? @"passed" : @"not available", mem1 ? @"passed" : @"not available",
                saved ? @"Report saved to Files → Sunshine → memory-probe.json." : error.localizedDescription];
            self.probeButton.enabled = YES;
        });
    });
}

- (void)runGraphicsVerification
{
    [self loadViewIfNeeded];
    if (!self.graphicsButton.enabled) return;
    self.graphicsButton.enabled = NO;
    self.graphicsStatus.text = @"Comparing GPU pixels with reference images…";
    NSArray<NSString*>* arguments = NSProcessInfo.processInfo.arguments;
    NSUInteger identifierIndex = [arguments indexOfObject:@"--verification-id"];
    NSString* identifier = identifierIndex != NSNotFound && identifierIndex + 1 < arguments.count
        ? arguments[identifierIndex + 1] : NSUUID.UUID.UUIDString;
    self.verificationIdentifier = identifier;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary* report = self.renderer ? [[self.renderer verifyGraphics] mutableCopy]
            : [@{@"schemaVersion": @1, @"scope": @"host-metal-only", @"passed": @NO,
                @"tests": @[], @"error": @"Renderer initialization failed."} mutableCopy];
        report[@"verificationID"] = identifier;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishGraphicsVerification:report attemptsRemaining:100];
        });
    });
}

- (void)finishGraphicsVerification:(NSMutableDictionary*)report attemptsRemaining:(NSUInteger)remaining
{
    NSDictionary* onscreen = [self.renderer onscreenStatistics] ?: @{@"completedFrames": @0, @"errorCount": @1};
    if ([onscreen[@"completedFrames"] unsignedIntegerValue] < 3 && self.renderer && remaining > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [self finishGraphicsVerification:report attemptsRemaining:remaining - 1];
        });
        return;
    }
    report[@"onscreen"] = onscreen;
    report[@"passed"] = @([report[@"passed"] boolValue]
        && [onscreen[@"completedFrames"] unsignedIntegerValue] >= 3
        && [onscreen[@"errorCount"] unsignedIntegerValue] == 0);
    report[@"appearance"] = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? @"dark" : @"light";
    report[@"viewSize"] = @{@"width": @(self.view.bounds.size.width), @"height": @(self.view.bounds.size.height)};
    NSError* error = nil;
    NSURL* output = [[GameDirectory() URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"graphics-verification.json"];
    NSData* json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
    BOOL saved = json && [json writeToURL:output options:NSDataWritingAtomic error:&error];
    self.graphicsStatus.text = [NSString stringWithFormat:@"Host graphics: %@ (%lu tests). %@",
        [report[@"passed"] boolValue] ? @"passed" : @"FAILED", (unsigned long)[report[@"tests"] count],
        saved ? @"Report saved to Files → Sunshine → graphics-verification.json." : error.localizedDescription];
    self.graphicsButton.enabled = YES;
}

- (void)recordRenderState:(NSString*)event
{
    if (!self.verificationIdentifier) return;
    NSDictionary* state = @{@"verificationID": self.verificationIdentifier, @"event": event,
        @"processID": @(NSProcessInfo.processInfo.processIdentifier), @"paused": @(self.metalView.paused),
        @"onscreen": [self.renderer onscreenStatistics] ?: @{@"completedFrames": @0, @"errorCount": @1}};
    NSError* error = nil;
    NSData* json = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:&error];
    NSURL* output = [[GameDirectory() URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"render-state.json"];
    if (!json || ![json writeToURL:output options:NSDataWritingAtomic error:&error]) {
        NSLog(@"Cannot save rendering lifecycle state: %@", error.localizedDescription);
    }
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    (void)controller;
    NSURL* source = urls.firstObject;
    if (!source) return;
    self.importButton.enabled = NO;
    self.imageStatus.text = @"Validating and copying image… Keep the app open.";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [source startAccessingSecurityScopedResource];
        __block NSString* result = nil;
        NSError* coordinationError = nil;
        NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:source options:0 error:&coordinationError byAccessor:^(NSURL* readable) {
            NSURL* directory = GameDirectory();
            NSURL* temporary = [directory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
            NSURL* destination = [directory URLByAppendingPathComponent:@"disc.gcm"];
            NSFileManager* manager = NSFileManager.defaultManager;
            NSError* error = nil;
            try {
                sms::inspectDiscImage(readable.fileSystemRepresentation);
                if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]
                    || ![manager copyItemAtURL:readable toURL:temporary error:&error]) {
                    result = error.localizedDescription;
                } else {
                    sms::inspectDiscImage(temporary.fileSystemRepresentation);
                    BOOL installed;
                    if ([manager fileExistsAtPath:destination.path]) {
                        installed = [manager replaceItemAtURL:destination withItemAtURL:temporary
                            backupItemName:nil options:0 resultingItemURL:nil error:&error];
                    } else {
                        installed = [manager moveItemAtURL:temporary toURL:destination error:&error];
                    }
                    result = installed ? InspectImage(destination) : error.localizedDescription;
                    if (installed) {
                        [destination setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
                    }
                }
            } catch (const std::exception& exception) {
                result = [NSString stringWithUTF8String:exception.what()];
            }
            [manager removeItemAtURL:temporary error:nil];
        }];
        if (scoped) [source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageStatus.text = coordinationError ? coordinationError.localizedDescription : (result ?: @"Import failed.");
            self.importButton.enabled = YES;
        });
    });
}

- (void)drawInMTKView:(MTKView*)view
{
    [self.renderer drawInView:view];
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size
{
    (void)view;
    (void)size;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self updateRenderingState];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self updateRenderingState];
}

- (void)updateRenderingState
{
    self.metalView.paused = !self.renderer || !self.view.window
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    self.metalView.paused = YES;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end

@interface SunshineAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation SunshineAppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options
{
    (void)application;
    (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[[SunshineController alloc] init]];
    [self.window makeKeyAndVisible];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--probe-memory"]) {
        UINavigationController* navigation = (UINavigationController*)self.window.rootViewController;
        [(SunshineController*)navigation.topViewController runMemoryProbe];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-graphics"]) {
        UINavigationController* navigation = (UINavigationController*)self.window.rootViewController;
        [(SunshineController*)navigation.topViewController runGraphicsVerification];
    }
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
    (void)application;
    UINavigationController* navigation = (UINavigationController*)self.window.rootViewController;
    ((SunshineController*)navigation.topViewController).metalView.paused = YES;
    [(SunshineController*)navigation.topViewController recordRenderState:@"background"];
}

- (void)applicationWillResignActive:(UIApplication*)application
{
    (void)application;
    UINavigationController* navigation = (UINavigationController*)self.window.rootViewController;
    ((SunshineController*)navigation.topViewController).metalView.paused = YES;
    [(SunshineController*)navigation.topViewController recordRenderState:@"inactive"];
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
    (void)application;
    UINavigationController* navigation = (UINavigationController*)self.window.rootViewController;
    [(SunshineController*)navigation.topViewController updateRenderingState];
    [(SunshineController*)navigation.topViewController recordRenderState:@"active"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (application.applicationState == UIApplicationStateActive) {
            [(SunshineController*)navigation.topViewController recordRenderState:@"foreground-rendering"];
        }
    });
}

@end

int main(int argc, char* argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SunshineAppDelegate.class));
    }
}

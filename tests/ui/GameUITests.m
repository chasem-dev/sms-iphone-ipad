#import <XCTest/XCTest.h>

@interface GameUITests : XCTestCase
@end

@implementation GameUITests
- (void)setUp
{
    [super setUp];
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
}

- (void)testLauncherPreferencesSurviveRelaunch
{
    self.continueAfterFailure = NO;
    XCUIApplication* game = [[XCUIApplication alloc] initWithBundleIdentifier:@"dev.chasem.sunshine.game"];
    game.launchEnvironment = @{@"SMS_IOS_AUTOLAUNCH": @"0"};
    [game launch];
    XCTAssertTrue([game.buttons[@"launcher.settings"] waitForExistenceWithTimeout:20]);
    [game.buttons[@"launcher.settings"] tap];
    [game.segmentedControls[@"ios.resolution"].buttons[@"2×"] tap];
    [game.segmentedControls[@"ios.widescreen"].buttons[@"16:9"] tap];
    [game.buttons[@"Done"] tap];
    [game terminate];
    [game launch];
    XCTAssertTrue([game.buttons[@"launcher.settings"] waitForExistenceWithTimeout:20]);
    [game.buttons[@"launcher.settings"] tap];
    XCTAssertTrue(game.segmentedControls[@"ios.resolution"].buttons[@"2×"].selected);
    XCTAssertTrue(game.segmentedControls[@"ios.widescreen"].buttons[@"16:9"].selected);
    [game.segmentedControls[@"ios.resolution"].buttons[@"1×"] tap];
    [game.segmentedControls[@"ios.widescreen"].buttons[@"4:3"] tap];
    [game.buttons[@"Done"] tap];
}

- (void)testLauncherSettingsAndPlay
{
    self.continueAfterFailure = NO;
    XCUIApplication* game = [[XCUIApplication alloc] initWithBundleIdentifier:@"dev.chasem.sunshine.game"];
    [game activate];
    XCUIElement* settings = game.buttons[@"launcher.settings"];
    XCTAssertTrue([settings waitForExistenceWithTimeout:20]);
    XCTAssertTrue(game.buttons[@"launcher.play"].enabled);
    [settings tap];
    XCUIElement* sharpness = game.segmentedControls[@"ios.resolution"];
    XCTAssertTrue([sharpness waitForExistenceWithTimeout:5]);
    [sharpness.buttons[@"2×"] tap];
    [game.segmentedControls[@"ios.widescreen"].buttons[@"16:9"] tap];
    [game.buttons[@"Done"] tap];
    [settings tap];
    XCTAssertTrue(sharpness.buttons[@"2×"].selected);
    XCTAssertTrue(game.segmentedControls[@"ios.widescreen"].buttons[@"16:9"].selected);
    [sharpness.buttons[@"1×"] tap];
    [game.segmentedControls[@"ios.widescreen"].buttons[@"4:3"] tap];
    [game.tables.firstMatch swipeUp];
    XCUIElement* volume = game.sliders[@"ios.volume"];
    XCTAssertTrue(volume.exists);
    XCTAssertTrue(volume.hittable);
    for (NSUInteger attempt = 0; attempt < 12 && [volume.value doubleValue] > 0; ++attempt) {
        [volume adjustToNormalizedSliderPosition:0];
    }
    XCTAssertEqualObjects(volume.value, @"0%");
    [game.buttons[@"Done"] tap];
    [settings tap];
    [game.tables.firstMatch swipeUp];
    XCTAssertEqualObjects(game.sliders[@"ios.volume"].value, @"0%");
    [game.buttons[@"Done"] tap];
    XCTAttachment* launcher = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    launcher.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:launcher];
    [game.buttons[@"launcher.play"] tap];
    XCTAssertTrue([game.buttons[@"Game A"] waitForExistenceWithTimeout:60]);
    XCTAssertFalse(game.buttons[@"launcher.play"].exists);
}

- (void)testLauncherMissingDisc
{
    XCUIApplication* game = [[XCUIApplication alloc] initWithBundleIdentifier:@"dev.chasem.sunshine.game"];
    [game activate];
    XCUIElement* play = game.buttons[@"launcher.play"];
    XCTAssertTrue([play waitForExistenceWithTimeout:20]);
    XCTAssertFalse(play.enabled);
    XCTAssertTrue(game.buttons[@"launcher.import"].enabled);
    [game.buttons[@"launcher.import"] tap];
    XCTAssertTrue([game.buttons[@"Cancel"] waitForExistenceWithTimeout:10]);
    [game.buttons[@"Cancel"] tap];
    XCTAssertFalse(play.enabled);
}

- (void)testNativeTouchControls
{
    self.continueAfterFailure = NO;
    XCUIApplication* game = [[XCUIApplication alloc] initWithBundleIdentifier:@"dev.chasem.sunshine.game"];
    [game activate];
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    XCUIElement* action = game.buttons[@"Game A"];
    XCTAssertTrue([action waitForExistenceWithTimeout:30]);
    XCTAssertTrue(action.hittable);
    XCUIElement* stick = game.otherElements[@"Game Stick"];
    XCTAssertTrue(stick.exists);
    XCUICoordinate* stickCenter = [stick coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)];
    XCUICoordinate* stickTop = [stick coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.1)];
    [stickCenter pressForDuration:0.1 thenDragToCoordinate:stickTop withVelocity:50 thenHoldForDuration:0.5];
    [NSThread sleepForTimeInterval:2];
    [action pressForDuration:0.3];
    [NSThread sleepForTimeInterval:2];
    XCUIElement* camera = game.otherElements[@"Game C Stick"];
    XCTAssertTrue(camera.exists);
    XCUICoordinate* cameraCenter = [camera coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)];
    XCUICoordinate* cameraRight = [camera coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [cameraCenter pressForDuration:0.1 thenDragToCoordinate:cameraRight withVelocity:50 thenHoldForDuration:0.5];
    [game.buttons[@"Game Start"] tap];
    [NSThread sleepForTimeInterval:2];
    [game.buttons[@"Game Start"] tap];
    [NSThread sleepForTimeInterval:2];
    XCTAttachment* screenshot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    screenshot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:screenshot];
}
@end

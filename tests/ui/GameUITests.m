#import <XCTest/XCTest.h>

@interface GameUITests : XCTestCase
@end

@implementation GameUITests
- (void)testNativeTouchControls
{
    self.continueAfterFailure = NO;
    XCUIApplication* game = [[XCUIApplication alloc] initWithBundleIdentifier:@"dev.chasem.sunshine.game"];
    [game activate];
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    XCUIElement* action = game.buttons[@"Game A"];
    XCTAssertTrue([action waitForExistenceWithTimeout:30]);
    XCTAssertTrue(action.hittable);
    [game.buttons[@"Game ↑"] pressForDuration:0.5];
    [NSThread sleepForTimeInterval:2];
    [action pressForDuration:0.3];
    [NSThread sleepForTimeInterval:2];
    [game.buttons[@"Game C→"] pressForDuration:0.5];
    [game.buttons[@"Game Start"] tap];
    [NSThread sleepForTimeInterval:2];
    [game.buttons[@"Game Start"] tap];
    [NSThread sleepForTimeInterval:2];
    XCTAttachment* screenshot = [XCTAttachment attachmentWithScreenshot:game.screenshot];
    screenshot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:screenshot];
}
@end

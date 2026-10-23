#define SDL_MAIN_HANDLED
#include <SDL.h>
#include <SDL_main.h>
#include <SDL_syswm.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include "port_platform.h"
#include "port_ext.h"
#include "port_presence.h"
#define BOOL SMSGameBOOL
#include <dolphin/pad.h>
#undef BOOL
#include "os/crash.h"
#include <cstdio>
#include <cstdlib>
#include <unistd.h>

extern void SMS_main(void);
extern float* gpMarioPos;
static unsigned long touchPresses;

@interface SMSGameControls : UIView
@end

@implementation SMSGameControls
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(releaseAll)
        name:UIApplicationWillResignActiveNotification object:nil];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)releaseAll
{
    for (UIView* view in self.subviews) {
        if ([view isKindOfClass:UIButton.class]) [self sendButton:(UIButton*)view down:NO];
    }
}

- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event
{
    UIView* target = [super hitTest:point withEvent:event];
    return target == self ? nil : target;
}

- (void)sendButton:(UIButton*)button down:(BOOL)down
{
    if (down) ++touchPresses;
    SDL_Event event = {};
    event.type = down ? SDL_KEYDOWN : SDL_KEYUP;
    event.key.state = down ? SDL_PRESSED : SDL_RELEASED;
    event.key.keysym.scancode = static_cast<SDL_Scancode>(button.tag);
    event.key.keysym.sym = SDL_GetKeyFromScancode(event.key.keysym.scancode);
    if (SDL_Window* window = SDL_GetKeyboardFocus()) event.key.windowID = SDL_GetWindowID(window);
    SDL_PushEvent(&event);
}

- (void)press:(UIButton*)button { [self sendButton:button down:YES]; }
- (void)release:(UIButton*)button { [self sendButton:button down:NO]; }

- (void)addButton:(NSString*)title scan:(SDL_Scancode)scan left:(CGFloat)left bottom:(CGFloat)bottom rightSide:(BOOL)rightSide
{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = scan;
    button.accessibilityLabel = [@"Game " stringByAppendingString:title];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.4];
    button.layer.cornerRadius = 22;
    button.exclusiveTouch = NO;
    [button addTarget:self action:@selector(press:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(release:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addSubview:button];
    NSLayoutConstraint* horizontal = rightSide
        ? [button.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-left]
        : [button.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:left];
    [NSLayoutConstraint activateConstraints:@[horizontal,
        [button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-bottom],
        [button.widthAnchor constraintEqualToConstant:44], [button.heightAnchor constraintEqualToConstant:44]]];
}
@end

static void InstallControls()
{
    static SMSGameControls* controls;
    SDL_Window* focusedWindow = SDL_GetKeyboardFocus();
    if (controls || !focusedWindow) return;
    SDL_SysWMinfo info = {};
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(focusedWindow, &info)) return;
    UIWindow* window = info.info.uikit.window;
    if (!window) return;
    controls = [[SMSGameControls alloc] initWithFrame:window.bounds];
    controls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [controls addButton:@"↑" scan:SDL_SCANCODE_W left:58 bottom:108 rightSide:NO];
    [controls addButton:@"↓" scan:SDL_SCANCODE_S left:58 bottom:12 rightSide:NO];
    [controls addButton:@"←" scan:SDL_SCANCODE_A left:10 bottom:60 rightSide:NO];
    [controls addButton:@"→" scan:SDL_SCANCODE_D left:106 bottom:60 rightSide:NO];
    [controls addButton:@"L" scan:SDL_SCANCODE_Q left:10 bottom:166 rightSide:NO];
    [controls addButton:@"Start" scan:SDL_SCANCODE_RETURN left:68 bottom:166 rightSide:NO];
    [controls addButton:@"A" scan:SDL_SCANCODE_SPACE left:10 bottom:60 rightSide:YES];
    [controls addButton:@"B" scan:SDL_SCANCODE_C left:58 bottom:12 rightSide:YES];
    [controls addButton:@"X" scan:SDL_SCANCODE_V left:58 bottom:108 rightSide:YES];
    [controls addButton:@"Y" scan:SDL_SCANCODE_F left:106 bottom:60 rightSide:YES];
    [controls addButton:@"R" scan:SDL_SCANCODE_E left:10 bottom:166 rightSide:YES];
    [controls addButton:@"Z" scan:SDL_SCANCODE_Z left:68 bottom:166 rightSide:YES];
    [controls addButton:@"C↑" scan:SDL_SCANCODE_I left:164 bottom:108 rightSide:YES];
    [controls addButton:@"C↓" scan:SDL_SCANCODE_K left:164 bottom:12 rightSide:YES];
    [controls addButton:@"C←" scan:SDL_SCANCODE_J left:212 bottom:60 rightSide:YES];
    [controls addButton:@"C→" scan:SDL_SCANCODE_L left:164 bottom:60 rightSide:YES];
    [window addSubview:controls];
    std::fprintf(stderr, "[ios] touch controls installed\n");
}

static unsigned long gameFrames;
static unsigned long movementTicks;
static unsigned long stagesLoaded;
static unsigned long inputSamples;
static unsigned long stageInputTicks;
static unsigned lastButtons;
static int lastStickX;
static int lastStickY;
static int lastCameraX;
static int lastCameraY;
static unsigned long cameraInputSamples;
static float playerPosition[3];
static bool hasPlayerPosition;
static PortPresence gamePresence;

extern "C" void sms_ios_presence_update(const PortPresence* presence)
{
    gamePresence = *presence;
}

static void WriteGameplayStatus()
{
    FILE* report = std::fopen("gameplay-status.json.tmp", "w");
    if (!report) return;
    std::fprintf(report, "{\"schemaVersion\":1,\"scope\":\"native-game-engine\",\"pid\":%d,"
        "\"gameFrames\":%lu,\"movementTicks\":%lu,\"stagesLoaded\":%lu,\"inputSamples\":%lu,"
        "\"stageInputTicks\":%lu,\"buttons\":%u,\"stickX\":%d,\"stickY\":%d,"
        "\"cameraX\":%d,\"cameraY\":%d,\"cameraInputSamples\":%lu,\"touchPresses\":%lu,"
        "\"applicationState\":%d,\"area\":%d,\"paused\":%d,\"cutscene\":%d,\"playerPosition\":",
        getpid(), gameFrames, movementTicks, stagesLoaded, inputSamples, stageInputTicks, lastButtons, lastStickX, lastStickY,
        lastCameraX, lastCameraY, cameraInputSamples, touchPresses,
        gamePresence.state, gamePresence.area, gamePresence.paused, gamePresence.cutscene);
    if (hasPlayerPosition) std::fprintf(report, "[%.6f,%.6f,%.6f]", playerPosition[0], playerPosition[1], playerPosition[2]);
    else std::fprintf(report, "null");
    std::fprintf(report, "}\n");
    std::fclose(report);
    std::rename("gameplay-status.json.tmp", "gameplay-status.json");
}

static void GameFrame()
{
    ++gameFrames;
    if (gameFrames % 15 == 1) {
        InstallControls();
        WriteGameplayStatus();
    }
}

static void AfterMovement()
{
    ++movementTicks;
    if (lastButtons || lastStickX || lastStickY) ++stageInputTicks;
    if (gpMarioPos) {
        for (unsigned index = 0; index < 3; ++index) playerPosition[index] = gpMarioPos[index];
        hasPlayerPosition = true;
    }
    if (movementTicks % 30 == 1) WriteGameplayStatus();
}

static void StageSetup()
{
    ++stagesLoaded;
    hasPlayerPosition = false;
    stageInputTicks = 0;
    std::fprintf(stderr, "[ios] real game stage loaded: %lu\n", stagesLoaded);
    WriteGameplayStatus();
}

static void ObserveInput(void* rawStatus)
{
    const PADStatus& status = static_cast<PADStatus*>(rawStatus)[0];
    lastButtons = status.button;
    lastStickX = status.stickX;
    lastStickY = status.stickY;
    lastCameraX = status.substickX;
    lastCameraY = status.substickY;
    if (lastCameraX || lastCameraY) ++cameraInputSamples;
    if (lastButtons || lastStickX || lastStickY) ++inputSamples;
}

static int DisableSaveStates() { return 0; }
static const char* SaveStateReason() { return "Cross-launch iOS ASLR save states are not supported."; }

static void EnterGame(void*)
{
    port_crash_thread_init();
    char program[] = "SunshineGame";
    char* arguments[] = {program, nullptr};
    static PortExtension extension = {};
    extension.name = "ios-runtime-verification";
    extension.frame = GameFrame;
    extension.afterMovement = AfterMovement;
    extension.stageSetup = StageSetup;
    extension.padRead = ObserveInput;
    extension.allowSaveStates = DisableSaveStates;
    extension.saveStatesOffReason = SaveStateReason;
    port_ext_register(&extension);
    port_init(1, arguments);
    std::fprintf(stderr, "[ios] entering the real SMS_main\n");
    SMS_main();
    std::fprintf(stderr, "[ios] SMS_main returned\n");
}

static int RunGame(int, char**)
{
    @autoreleasepool {
        NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString* gameDirectory = [documents stringByAppendingPathComponent:@"Game"];
        NSString* saves = [documents stringByAppendingPathComponent:@"Saves"];
        [NSFileManager.defaultManager createDirectoryAtPath:gameDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager createDirectoryAtPath:saves withIntermediateDirectories:YES attributes:nil error:nil];
        NSString* log = [documents stringByAppendingPathComponent:@"game.log"];
        std::freopen(log.fileSystemRepresentation, "w", stderr);
        std::freopen([documents stringByAppendingPathComponent:@"presence.log"].fileSystemRepresentation, "w", stdout);
        setvbuf(stderr, nullptr, _IONBF, 0);
        setenv("SMS_DISC_IMAGE", [gameDirectory stringByAppendingPathComponent:@"disc.gcm"].fileSystemRepresentation, 1);
        setenv("SMS_SAVE_DIR", saves.fileSystemRepresentation, 1);
        setenv("SMS_GX_BACKEND", "vulkan", 1);
        setenv("SMS_SKIP_INTRO", "1", 0);
        setenv("SMS_SKIP_MOVIES", "1", 0);
        setenv("SMS_GX_GL_THREAD", "0", 1);
        setenv("SMS_PRESENCE", "1", 1);
        chdir(documents.fileSystemRepresentation);
        if (access(getenv("SMS_DISC_IMAGE"), R_OK) != 0) {
            std::fprintf(stderr, "[ios] missing Documents/Game/disc.gcm; install your own GMSE01 revision 0 image before launching\n");
            return 1;
        }
        port_install_crash_handlers();
        const unsigned long stackSize = 8ul << 20;
        void* stack = port_low_alloc(stackSize);
        if (!stack) {
            std::fprintf(stderr, "[ios] cannot allocate the rebased game stack\n");
            return 1;
        }
        void* stackTop = static_cast<char*>(stack) + stackSize;
        void (*entry)(void*) = EnterGame;
        __asm__ volatile(
            "mov x19, sp\n\t"
            "mov sp, %0\n\t"
            "mov x0, xzr\n\t"
            "blr %1\n\t"
            "mov sp, x19"
            :
            : "r"(stackTop), "r"(entry)
            : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14",
              "x15", "x16", "x17", "x19", "x30", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7",
              "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30", "v31", "memory", "cc");
        return 0;
    }
}

int main(int argc, char** argv)
{
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    return SDL_UIKitRunApp(argc, argv, RunGame);
}

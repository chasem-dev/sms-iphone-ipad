#import "GameCubeControls.h"
#include <SDL.h>
#include <cmath>

typedef NS_ENUM(NSInteger, SMSControlKind) {
    SMSControlButton, SMSControlTrigger, SMSControlStick, SMSControlDPad
};

@class SMSGameCubeControls;

@interface SMSControlButtonView : UIButton
@property(nonatomic, weak) SMSGameCubeControls* owner;
@end

@interface SMSControlStickView : UIView
@property(nonatomic, weak) SMSGameCubeControls* owner;
@end

@interface SMSGameCubeControl : NSObject
@property(nonatomic) SMSControlKind kind;
@property(nonatomic) NSInteger code;
@property(nonatomic, strong) UIView* view;
@property(nonatomic, strong) UIImageView* image;
@property(nonatomic, strong) UIImageView* knob;
@property(nonatomic) NSUInteger holders;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) CFTimeInterval pressedAt;
@property(nonatomic) CGPoint displacement;
@property(nonatomic) unsigned directions;
@end

@implementation SMSGameCubeControl
@end

@interface SMSGameCubeControls : UIView {
    SDL_Joystick* _joystick;
    SDL_GameController* _controller;
    SDL_JoystickID _instanceID;
    void (*_pressObserver)(void);
    BOOL _active;
    CGFloat _opacity;
}
@property(nonatomic, strong) NSMutableArray<SMSGameCubeControl*>* controls;
@property(nonatomic, strong) NSMapTable<UITouch*, SMSGameCubeControl*>* pointers;
@property(nonatomic, strong) NSTimer* attachmentTimer;
- (instancetype)initWithFrame:(CGRect)frame observer:(void (*)(void))observer;
- (void)releaseAll;
- (void)handleTouches:(NSSet<UITouch*>*)touches phase:(UITouchPhase)phase;
@end

@implementation SMSControlButtonView
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self.owner handleTouches:touches phase:UITouchPhaseBegan]; }
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self.owner handleTouches:touches phase:UITouchPhaseMoved]; }
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self.owner handleTouches:touches phase:UITouchPhaseEnded]; }
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self.owner releaseAll]; }
@end

@implementation SMSControlStickView
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self.owner handleTouches:touches phase:UITouchPhaseBegan]; }
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self.owner handleTouches:touches phase:UITouchPhaseMoved]; }
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self.owner handleTouches:touches phase:UITouchPhaseEnded]; }
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self.owner releaseAll]; }
@end

@implementation SMSGameCubeControls

- (instancetype)initWithFrame:(CGRect)frame observer:(void (*)(void))observer
{
    if (!(self = [super initWithFrame:frame])) return nil;
    _pressObserver = observer;
    _instanceID = -1;
    _active = UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.controls = [NSMutableArray array];
    self.pointers = [NSMapTable strongToStrongObjectsMapTable];
    [self addControl:@"l" label:@"Game L" kind:SMSControlTrigger code:SDL_CONTROLLER_AXIS_TRIGGERLEFT];
    [self addControl:@"r" label:@"Game R" kind:SMSControlTrigger code:SDL_CONTROLLER_AXIS_TRIGGERRIGHT];
    [self addControl:@"z" label:@"Game Z" kind:SMSControlButton code:SDL_CONTROLLER_BUTTON_RIGHTSHOULDER];
    [self addControl:@"stick" label:@"Game Stick" kind:SMSControlStick code:SDL_CONTROLLER_AXIS_LEFTX];
    [self addControl:@"cstick" label:@"Game C Stick" kind:SMSControlStick code:SDL_CONTROLLER_AXIS_RIGHTX];
    [self addControl:@"dpad" label:@"Game D-Pad" kind:SMSControlDPad code:0];
    [self addControl:@"start" label:@"Game Start" kind:SMSControlButton code:SDL_CONTROLLER_BUTTON_START];
    [self addControl:@"y" label:@"Game Y" kind:SMSControlButton code:SDL_CONTROLLER_BUTTON_Y];
    [self addControl:@"x" label:@"Game X" kind:SMSControlButton code:SDL_CONTROLLER_BUTTON_X];
    [self addControl:@"b" label:@"Game B" kind:SMSControlButton code:SDL_CONTROLLER_BUTTON_B];
    [self addControl:@"a" label:@"Game A" kind:SMSControlButton code:SDL_CONTROLLER_BUTTON_A];
    NSNotificationCenter* notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(suspend:) name:UIApplicationWillResignActiveNotification object:nil];
    [notifications addObserver:self selector:@selector(suspend:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [notifications addObserver:self selector:@selector(resume:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [notifications addObserver:self selector:@selector(defaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
    [self applyDefaults];
    [self attachController];
    if (!_joystick) {
        __weak SMSGameCubeControls* weakSelf = self;
        self.attachmentTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer* timer) {
            SMSGameCubeControls* controls = weakSelf;
            if (!controls) { [timer invalidate]; return; }
            [controls attachController];
            if (controls->_joystick) { [timer invalidate]; controls.attachmentTimer = nil; }
        }];
    }
    return self;
}

- (void)addControl:(NSString*)asset label:(NSString*)label kind:(SMSControlKind)kind code:(NSInteger)code
{
    SMSGameCubeControl* control = [SMSGameCubeControl new];
    control.kind = kind;
    control.code = code;
    if (kind == SMSControlButton || kind == SMSControlTrigger) {
        SMSControlButtonView* button = [SMSControlButtonView buttonWithType:UIButtonTypeCustom];
        button.owner = self;
        control.view = button;
    } else {
        SMSControlStickView* stick = [SMSControlStickView new];
        stick.owner = self;
        control.view = stick;
        control.view.accessibilityTraits = UIAccessibilityTraitAllowsDirectInteraction;
        control.view.accessibilityHint = @"Drag to control direction and strength";
    }
    control.view.multipleTouchEnabled = YES;
    control.view.exclusiveTouch = NO;
    control.view.isAccessibilityElement = YES;
    control.view.accessibilityLabel = label;
    control.view.accessibilityIdentifier = label;
    NSURL* url = [NSBundle.mainBundle URLForResource:[@"touch_" stringByAppendingString:asset] withExtension:@"png" subdirectory:@"Controls"];
    UIImage* image = url ? [UIImage imageWithContentsOfFile:url.path] : nil;
    if (!image) NSLog(@"Missing controller artwork: Controls/touch_%@.png", asset);
    control.image = [[UIImageView alloc] initWithImage:image];
    control.image.userInteractionEnabled = NO;
    [control.view addSubview:control.image];
    if (kind == SMSControlStick) {
        control.knob = [[UIImageView alloc] initWithImage:image];
        [control.view addSubview:control.knob];
    }
    [self.controls addObject:control];
    [self addSubview:control.view];
}

- (void)attachController
{
    if (_joystick || !_active || !(SDL_WasInit(SDL_INIT_GAMECONTROLLER) & SDL_INIT_GAMECONTROLLER)) return;
    SDL_LockJoysticks();
    SDL_VirtualJoystickDesc description = {};
    description.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    description.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    description.naxes = SDL_CONTROLLER_AXIS_MAX;
    description.nbuttons = SDL_CONTROLLER_BUTTON_DPAD_RIGHT + 1;
    description.axis_mask = (1u << description.naxes) - 1;
    description.button_mask = (1u << description.nbuttons) - 1;
    description.name = "SMS iOS Touch Controls";
    int deviceIndex = SDL_JoystickAttachVirtualEx(&description);
    if (deviceIndex >= 0) {
        _controller = SDL_GameControllerOpen(deviceIndex);
        if (_controller) {
            _joystick = SDL_GameControllerGetJoystick(_controller);
            _instanceID = SDL_JoystickInstanceID(_joystick);
            [self releaseAll];
        } else {
            SDL_JoystickDetachVirtual(deviceIndex);
        }
    }
    if (!_joystick) SDL_Log("Touch controller attachment failed: %s", SDL_GetError());
    SDL_UnlockJoysticks();
}

- (void)send:(SMSGameCubeControl*)control down:(BOOL)down
{
    if (!_joystick) return;
    SDL_LockJoysticks();
    if (control.kind == SMSControlTrigger)
        SDL_JoystickSetVirtualAxis(_joystick, (int)control.code, down ? SDL_JOYSTICK_AXIS_MAX : SDL_JOYSTICK_AXIS_MIN);
    else
        SDL_JoystickSetVirtualButton(_joystick, (int)control.code, down ? SDL_PRESSED : SDL_RELEASED);
    SDL_JoystickUpdate();
    SDL_UnlockJoysticks();
}

- (void)updateAppearance:(SMSGameCubeControl*)control
{
    CGFloat width = CGRectGetWidth(control.view.bounds), height = CGRectGetHeight(control.view.bounds);
    BOOL held = control.holders > 0;
    control.image.alpha = control.kind == SMSControlStick ? _opacity * 0.5 : (held ? MIN(1, _opacity * 230 / 140) : _opacity);
    control.image.transform = CGAffineTransformIdentity;
    control.image.frame = control.view.bounds;
    if (control.kind == SMSControlStick) {
        control.knob.bounds = CGRectMake(0, 0, width * 0.62, height * 0.62);
        control.knob.center = CGPointMake(width * 0.5 + control.displacement.x * width * 0.25, height * 0.5 + control.displacement.y * width * 0.25);
        control.knob.alpha = held ? MIN(1, _opacity * 230 / 140) : _opacity;
        control.view.accessibilityValue = [NSString stringWithFormat:@"%.2f, %.2f", control.displacement.x, control.displacement.y];
    } else {
        control.image.transform = CGAffineTransformMakeScale(held ? 0.92 : 1, held ? 0.92 : 1);
    }
    if ([control.view isKindOfClass:UIButton.class]) ((UIButton*)control.view).highlighted = held;
}

- (void)place:(NSUInteger)index x:(CGFloat)x y:(CGFloat)y width:(CGFloat)width
{
    SMSGameCubeControl* control = self.controls[index];
    CGSize imageSize = control.image.image.size;
    CGFloat height = imageSize.width > 0 ? width * imageSize.height / imageSize.width : width;
    control.view.bounds = CGRectMake(0, 0, width, height);
    control.view.center = CGPointMake(x, y);
    [self updateAppearance:control];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGFloat scale = MIN(height, width / 1.9), margin = 0.05 * scale;
    CGFloat left = self.safeAreaInsets.left + margin, right = width - self.safeAreaInsets.right - margin;
    CGFloat top = margin, bottom = height - margin;
    [self place:0 x:left + 0.11 * scale y:top + 0.065 * scale width:0.22 * scale];
    [self place:1 x:right - 0.11 * scale y:top + 0.065 * scale width:0.22 * scale];
    [self place:2 x:right - 0.11 * scale y:top + 0.2 * scale width:0.24 * scale];
    [self place:3 x:left + 0.2 * scale y:bottom - 0.45 * scale width:0.36 * scale];
    [self place:4 x:right - 0.55 * scale y:bottom - 0.13 * scale width:0.25 * scale];
    [self place:5 x:left + 0.47 * scale y:bottom - 0.15 * scale width:0.26 * scale];
    [self place:6 x:width / 2 y:bottom - 0.07 * scale width:0.15 * scale];
    CGFloat actionX = right - 0.25 * scale, actionY = bottom - 0.4 * scale;
    [self place:7 x:actionX - 0.02 * scale y:actionY - 0.155 * scale width:0.17 * scale];
    [self place:8 x:actionX + 0.155 * scale y:actionY - 0.03 * scale width:0.15 * scale];
    [self place:9 x:actionX - 0.15 * scale y:actionY + 0.12 * scale width:0.12 * scale];
    [self place:10 x:actionX y:actionY width:0.18 * scale];
}

- (void)safeAreaInsetsDidChange { [super safeAreaInsetsDidChange]; [self setNeedsLayout]; }

- (SMSGameCubeControl*)controlAt:(CGPoint)point
{
    SMSGameCubeControl* best = nil;
    CGFloat bestDistance = 1;
    for (SMSGameCubeControl* control in self.controls) {
        CGFloat reach = MAX(CGRectGetWidth(control.view.bounds), CGRectGetHeight(control.view.bounds)) * (control.kind == SMSControlStick ? 0.62 : 0.58);
        if (reach <= 0) continue;
        CGFloat distance = std::hypot(point.x - control.view.center.x, point.y - control.view.center.y) / reach;
        if (distance < bestDistance) { best = control; bestDistance = distance; }
    }
    return best;
}

- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event
{
    if (self.hidden || !self.userInteractionEnabled || !_active || ![self pointInside:point withEvent:event]) return nil;
    return [self controlAt:point].view;
}

- (BOOL)press:(SMSGameCubeControl*)control
{
    if ((control.kind == SMSControlStick || control.kind == SMSControlDPad) && control.holders) return NO;
    if (control.holders++ == 0) {
        control.generation++;
        control.pressedAt = CACurrentMediaTime();
        if (control.kind == SMSControlButton || control.kind == SMSControlTrigger) [self send:control down:YES];
    }
    if (_pressObserver) _pressObserver();
    [self updateAppearance:control];
    return YES;
}

- (void)move:(SMSGameCubeControl*)control point:(CGPoint)point
{
    if (!_joystick) return;
    CGFloat deltaX = point.x - control.view.center.x, deltaY = point.y - control.view.center.y;
    CGFloat width = CGRectGetWidth(control.view.bounds);
    if (width <= 0) return;
    SDL_LockJoysticks();
    if (control.kind == SMSControlStick) {
        CGFloat full = width * 0.4;
        CGFloat length = MAX(1, std::hypot(deltaX, deltaY) / full);
        control.displacement = CGPointMake(deltaX / length / full, deltaY / length / full);
        SDL_JoystickSetVirtualAxis(_joystick, (int)control.code, (Sint16)std::lround(control.displacement.x * SDL_JOYSTICK_AXIS_MAX));
        SDL_JoystickSetVirtualAxis(_joystick, (int)control.code + 1, (Sint16)std::lround(control.displacement.y * SDL_JOYSTICK_AXIS_MAX));
    } else if (control.kind == SMSControlDPad) {
        CGFloat length = std::hypot(deltaX, deltaY), band = 0.38 * length;
        unsigned directions = 0;
        if (length > 0.12 * width) {
            if (deltaY < -band) directions |= 1; else if (deltaY > band) directions |= 2;
            if (deltaX < -band) directions |= 4; else if (deltaX > band) directions |= 8;
        }
        control.directions = directions;
        for (int direction = 0; direction < 4; ++direction)
            SDL_JoystickSetVirtualButton(_joystick, SDL_CONTROLLER_BUTTON_DPAD_UP + direction, (directions & (1u << direction)) ? SDL_PRESSED : SDL_RELEASED);
    }
    SDL_JoystickUpdate();
    SDL_UnlockJoysticks();
    [self updateAppearance:control];
}

- (void)release:(SMSGameCubeControl*)control
{
    if (!control.holders || --control.holders) return;
    if (control.kind == SMSControlStick || control.kind == SMSControlDPad) {
        [self move:control point:control.view.center];
    } else {
        NSUInteger generation = control.generation;
        CFTimeInterval delay = MAX(0, control.pressedAt + 0.05 - CACurrentMediaTime());
        __weak SMSGameCubeControls* weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!control.holders && control.generation == generation) [weakSelf send:control down:NO];
        });
    }
    [self updateAppearance:control];
}

- (void)handleTouches:(NSSet<UITouch*>*)touches phase:(UITouchPhase)phase
{
    if (!_active || self.hidden) { [self releaseAll]; return; }
    [self attachController];
    if (!_joystick) return;
    for (UITouch* touch in touches) {
        CGPoint point = [touch locationInView:self];
        SMSGameCubeControl* control = [self.pointers objectForKey:touch];
        if (phase == UITouchPhaseBegan) {
            control = [self controlAt:point];
            if (control && [self press:control]) { [self.pointers setObject:control forKey:touch]; [self move:control point:point]; }
        } else if (phase == UITouchPhaseMoved && control) {
            if (control.kind == SMSControlStick || control.kind == SMSControlDPad) [self move:control point:point];
            else {
                SMSGameCubeControl* next = [self controlAt:point];
                if (next && next != control && (next.kind == SMSControlButton || next.kind == SMSControlTrigger)) {
                    [self release:control];
                    [self press:next];
                    [self.pointers setObject:next forKey:touch];
                }
            }
        } else if (phase == UITouchPhaseEnded && control) {
            [self.pointers removeObjectForKey:touch];
            [self release:control];
        }
    }
}

- (void)releaseAll
{
    [self.pointers removeAllObjects];
    for (SMSGameCubeControl* control in self.controls) {
        control.holders = 0;
        control.generation++;
        control.displacement = CGPointZero;
        control.directions = 0;
        [self updateAppearance:control];
    }
    if (!_joystick || !(SDL_WasInit(SDL_INIT_JOYSTICK) & SDL_INIT_JOYSTICK)) return;
    SDL_LockJoysticks();
    for (int axis = 0; axis < SDL_CONTROLLER_AXIS_MAX; ++axis)
        SDL_JoystickSetVirtualAxis(_joystick, axis, axis >= SDL_CONTROLLER_AXIS_TRIGGERLEFT ? SDL_JOYSTICK_AXIS_MIN : 0);
    for (int button = 0; button <= SDL_CONTROLLER_BUTTON_DPAD_RIGHT; ++button)
        SDL_JoystickSetVirtualButton(_joystick, button, SDL_RELEASED);
    SDL_JoystickUpdate();
    SDL_UnlockJoysticks();
}

- (void)applyDefaults
{
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    id opacity = [defaults objectForKey:@"ios.touchOpacity"];
    CGFloat value = opacity ? [defaults floatForKey:@"ios.touchOpacity"] : 0.55;
    _opacity = std::isfinite(value) ? MIN(1, MAX(0, value)) : 0.55;
    self.hidden = [defaults objectForKey:@"ios.touchControls"] && ![defaults boolForKey:@"ios.touchControls"];
    for (SMSGameCubeControl* control in self.controls) [self updateAppearance:control];
}

- (void)defaultsChanged:(NSNotification*)notification
{
    if (NSThread.isMainThread) [self applyDefaults];
    else {
        __weak SMSGameCubeControls* weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf applyDefaults]; });
    }
}

- (void)setHidden:(BOOL)hidden { if (hidden) [self releaseAll]; [super setHidden:hidden]; }
- (void)suspend:(NSNotification*)notification { _active = NO; [self releaseAll]; }
- (void)resume:(NSNotification*)notification { _active = YES; [self applyDefaults]; [self attachController]; }
- (void)didMoveToWindow { [super didMoveToWindow]; if (!self.window) [self releaseAll]; }

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_attachmentTimer invalidate];
    if (_joystick && (SDL_WasInit(SDL_INIT_JOYSTICK) & SDL_INIT_JOYSTICK)) {
        [self releaseAll];
        SDL_LockJoysticks();
        SDL_GameControllerClose(_controller);
        for (int deviceIndex = 0; deviceIndex < SDL_NumJoysticks(); ++deviceIndex) {
            if (SDL_JoystickGetDeviceInstanceID(deviceIndex) == _instanceID) {
                SDL_JoystickDetachVirtual(deviceIndex);
                break;
            }
        }
        SDL_UnlockJoysticks();
    }
}
@end

UIView* SMSCreateGameCubeControls(CGRect frame, void (*pressObserver)(void))
{
    return [[SMSGameCubeControls alloc] initWithFrame:frame observer:pressObserver];
}

void SMSGameCubeControlsReleaseAll(UIView* controls)
{
    if ([controls isKindOfClass:SMSGameCubeControls.class]) [(SMSGameCubeControls*)controls releaseAll];
}

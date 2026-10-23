#import <MetalKit/MetalKit.h>

typedef NS_ENUM(NSUInteger, SMSMetalScene) {
    SMSMetalSceneClear,
    SMSMetalSceneGeometry,
    SMSMetalSceneTexture,
    SMSMetalSceneDepth,
    SMSMetalSceneBlend,
    SMSMetalSceneScissor,
    SMSMetalSceneViewport,
    SMSMetalSceneSRGB
};

@interface SMSMetalRenderer : NSObject
@property(nonatomic, readonly, strong) id<MTLDevice> device;
- (instancetype)initWithDevice:(id<MTLDevice>)device error:(NSError**)error;
- (void)drawInView:(MTKView*)view;
- (NSDictionary*)onscreenStatistics;
- (NSDictionary*)verifyGraphics;
@end

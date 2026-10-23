#import "MetalRenderer.h"
#import <TargetConditionals.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

struct DiagnosticVertex {
    float position[3];
    float color[4];
    float uv[2];
};

static_assert(sizeof(DiagnosticVertex) == 9 * sizeof(float));

static NSError* GraphicsError(NSString* message)
{
    return [NSError errorWithDomain:@"dev.chasem.sunshine.graphics" code:1
        userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface SMSMetalRenderer ()
@property(nonatomic, readwrite, strong) id<MTLDevice> device;
@property(nonatomic, strong) id<MTLCommandQueue> queue;
@property(nonatomic, strong) id<MTLRenderPipelineState> opaquePipeline;
@property(nonatomic, strong) id<MTLRenderPipelineState> blendPipeline;
@property(nonatomic, strong) id<MTLRenderPipelineState> srgbPipeline;
@property(nonatomic, strong) id<MTLDepthStencilState> depthState;
@property(nonatomic, strong) id<MTLSamplerState> sampler;
@property(nonatomic, strong) id<MTLTexture> whiteTexture;
@property(nonatomic, strong) id<MTLTexture> checkerTexture;
@property(nonatomic, strong) id<MTLBuffer> indexBuffer;
@property(nonatomic) NSUInteger completedFrames;
@property(nonatomic) NSUInteger submittedFrames;
@property(nonatomic) NSUInteger errorCount;
@property(nonatomic) NSUInteger drawableWidth;
@property(nonatomic) NSUInteger drawableHeight;
@property(nonatomic, strong) NSMutableArray<NSString*>* errors;
@end

@implementation SMSMetalRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device error:(NSError**)error
{
    self = [super init];
    if (!self) return nil;
    self.device = device;
    self.queue = [device newCommandQueue];
    self.errors = [NSMutableArray array];
    NSURL* shaderURL = [NSBundle.mainBundle URLForResource:@"Diagnostic" withExtension:@"metallib"];
    if (!device || !self.queue || !shaderURL) {
        if (error) *error = GraphicsError(@"Metal device, queue, or bundled shader library is unavailable.");
        return nil;
    }
    id<MTLLibrary> library = [device newLibraryWithURL:shaderURL error:error];
    if (!library) return nil;
    MTLRenderPipelineDescriptor* pipeline = [[MTLRenderPipelineDescriptor alloc] init];
    pipeline.vertexFunction = [library newFunctionWithName:@"diagnosticVertex"];
    pipeline.fragmentFunction = [library newFunctionWithName:@"diagnosticFragment"];
    pipeline.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    pipeline.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.opaquePipeline = [device newRenderPipelineStateWithDescriptor:pipeline error:error];
    if (!self.opaquePipeline) return nil;
    pipeline.colorAttachments[0].blendingEnabled = YES;
    pipeline.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipeline.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeline.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipeline.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    self.blendPipeline = [device newRenderPipelineStateWithDescriptor:pipeline error:error];
    if (!self.blendPipeline) return nil;
    pipeline.colorAttachments[0].blendingEnabled = NO;
    pipeline.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    self.srgbPipeline = [device newRenderPipelineStateWithDescriptor:pipeline error:error];
    if (!self.srgbPipeline) return nil;

    MTLDepthStencilDescriptor* depth = [[MTLDepthStencilDescriptor alloc] init];
    depth.depthCompareFunction = MTLCompareFunctionLess;
    depth.depthWriteEnabled = YES;
    self.depthState = [device newDepthStencilStateWithDescriptor:depth];
    MTLSamplerDescriptor* sampler = [[MTLSamplerDescriptor alloc] init];
    sampler.minFilter = MTLSamplerMinMagFilterNearest;
    sampler.magFilter = MTLSamplerMinMagFilterNearest;
    sampler.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sampler.tAddressMode = MTLSamplerAddressModeClampToEdge;
    self.sampler = [device newSamplerStateWithDescriptor:sampler];

    const std::uint8_t white[] = {255, 255, 255, 255};
    MTLTextureDescriptor* texture = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
        width:1 height:1 mipmapped:NO];
    texture.storageMode = MTLStorageModeShared;
    texture.usage = MTLTextureUsageShaderRead;
    self.whiteTexture = [device newTextureWithDescriptor:texture];
    [self.whiteTexture replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:white bytesPerRow:4];
    const std::uint8_t colors[] = {255, 0, 0, 255, 0, 255, 0, 255,
        0, 0, 255, 255, 255, 255, 0, 255};
    texture.width = 2;
    texture.height = 2;
    self.checkerTexture = [device newTextureWithDescriptor:texture];
    [self.checkerTexture replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:colors bytesPerRow:8];
    const std::uint16_t indices[] = {0, 2, 1, 1, 2, 3};
    self.indexBuffer = [device newBufferWithBytes:indices length:sizeof(indices) options:MTLResourceStorageModeShared];
    if (!self.depthState || !self.sampler || !self.whiteTexture || !self.checkerTexture || !self.indexBuffer) {
        if (error) *error = GraphicsError(@"Cannot allocate Metal diagnostic resources.");
        return nil;
    }
    return self;
}

- (void)quad:(id<MTLRenderCommandEncoder>)encoder extent:(float)extent depth:(float)depth
    color:(const std::array<float, 4>&)color
{
    const DiagnosticVertex vertices[] = {
        {{-extent, extent, depth}, {color[0], color[1], color[2], color[3]}, {0, 0}},
        {{extent, extent, depth}, {color[0], color[1], color[2], color[3]}, {1, 0}},
        {{-extent, -extent, depth}, {color[0], color[1], color[2], color[3]}, {0, 1}},
        {{extent, -extent, depth}, {color[0], color[1], color[2], color[3]}, {1, 1}}
    };
    [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:6 indexType:MTLIndexTypeUInt16
        indexBuffer:self.indexBuffer indexBufferOffset:0];
}

- (id<MTLCommandBuffer>)encodeScene:(SMSMetalScene)scene descriptor:(MTLRenderPassDescriptor*)descriptor
    width:(NSUInteger)width height:(NSUInteger)height error:(NSError**)error
{
    descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    descriptor.depthAttachment.loadAction = MTLLoadActionClear;
    descriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
    descriptor.depthAttachment.clearDepth = 1;
    id<MTLCommandBuffer> buffer = [self.queue commandBuffer];
    buffer.label = @"Sunshine host graphics diagnostic";
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];
    if (!buffer || !encoder) {
        if (error) *error = GraphicsError(@"Cannot create Metal command buffer or render encoder.");
        return nil;
    }
    [encoder setRenderPipelineState:scene == SMSMetalSceneSRGB ? self.srgbPipeline : self.opaquePipeline];
    [encoder setDepthStencilState:self.depthState];
    [encoder setFragmentTexture:scene == SMSMetalSceneTexture ? self.checkerTexture : self.whiteTexture atIndex:0];
    [encoder setFragmentSamplerState:self.sampler atIndex:0];
    const std::array<float, 4> red{1, 0, 0, 1};
    const std::array<float, 4> green{0, 1, 0, 1};
    const std::array<float, 4> white{1, 1, 1, 1};
    switch (scene) {
        case SMSMetalSceneClear: break;
        case SMSMetalSceneGeometry:
            [self quad:encoder extent:1 depth:0.5 color:green];
            break;
        case SMSMetalSceneTexture:
            [self quad:encoder extent:1 depth:0.5 color:white];
            break;
        case SMSMetalSceneDepth:
            [self quad:encoder extent:1 depth:0.8 color:red];
            [self quad:encoder extent:0.5 depth:0.2 color:green];
            [self quad:encoder extent:0.5 depth:0.6 color:std::array<float, 4>{0, 0, 1, 1}];
            break;
        case SMSMetalSceneBlend:
            [self quad:encoder extent:1 depth:0.8 color:red];
            [encoder setRenderPipelineState:self.blendPipeline];
            [self quad:encoder extent:0.5 depth:0.2 color:std::array<float, 4>{0, 0, 1, 0.5}];
            break;
        case SMSMetalSceneScissor:
            [encoder setScissorRect:MTLScissorRect{width / 4, height / 4, width / 2, height / 2}];
            [self quad:encoder extent:1 depth:0.5 color:green];
            break;
        case SMSMetalSceneViewport:
            [encoder setViewport:MTLViewport{double(width / 4), double(height / 4), double(width / 2), double(height / 2), 0, 1}];
            [self quad:encoder extent:1 depth:0.5 color:green];
            break;
        case SMSMetalSceneSRGB:
            [self quad:encoder extent:1 depth:0.5 color:std::array<float, 4>{0.25, 0.5, 0.75, 1}];
            break;
    }
    [encoder endEncoding];
    return buffer;
}

- (void)recordError:(NSString*)message
{
    @synchronized(self) {
        self.errorCount += 1;
        if (self.errors.count < 16) [self.errors addObject:message];
    }
    NSLog(@"Metal diagnostic error: %@", message);
}

- (void)drawInView:(MTKView*)view
{
    MTLRenderPassDescriptor* descriptor = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!descriptor || !drawable) return;
    NSError* error = nil;
    id<MTLCommandBuffer> buffer = [self encodeScene:SMSMetalSceneTexture descriptor:descriptor
        width:drawable.texture.width height:drawable.texture.height error:&error];
    if (!buffer) {
        [self recordError:error.localizedDescription];
        view.paused = YES;
        return;
    }
    @synchronized(self) {
        self.submittedFrames += 1;
        self.drawableWidth = drawable.texture.width;
        self.drawableHeight = drawable.texture.height;
    }
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        if (completed.status != MTLCommandBufferStatusCompleted) {
            [self recordError:completed.error.localizedDescription ?: @"Onscreen command buffer did not complete."];
        } else {
            @synchronized(self) { self.completedFrames += 1; }
        }
    }];
    [buffer presentDrawable:drawable];
    [buffer commit];
}

- (NSDictionary*)onscreenStatistics
{
    @synchronized(self) {
        return @{@"submittedFrames": @(self.submittedFrames), @"completedFrames": @(self.completedFrames),
            @"errorCount": @(self.errorCount), @"errors": [self.errors copy],
            @"drawableWidth": @(self.drawableWidth), @"drawableHeight": @(self.drawableHeight)};
    }
}

static std::array<int, 4> ExpectedPixel(SMSMetalScene scene, NSUInteger column, NSUInteger row,
    NSUInteger width, NSUInteger height)
{
    bool center = column >= width / 4 && column < 3 * width / 4
        && row >= height / 4 && row < 3 * height / 4;
    switch (scene) {
        case SMSMetalSceneGeometry: return {0, 255, 0, 255};
        case SMSMetalSceneTexture:
            if (row < height / 2) return column < width / 2
                ? std::array<int, 4>{0, 0, 255, 255} : std::array<int, 4>{0, 255, 0, 255};
            return column < width / 2 ? std::array<int, 4>{255, 0, 0, 255} : std::array<int, 4>{0, 255, 255, 255};
        case SMSMetalSceneDepth: return center ? std::array<int, 4>{0, 255, 0, 255} : std::array<int, 4>{0, 0, 255, 255};
        case SMSMetalSceneBlend: return center ? std::array<int, 4>{128, 0, 128, 255} : std::array<int, 4>{0, 0, 255, 255};
        case SMSMetalSceneScissor:
        case SMSMetalSceneViewport: return center ? std::array<int, 4>{0, 255, 0, 255} : std::array<int, 4>{0, 0, 0, 255};
        case SMSMetalSceneSRGB: return {225, 188, 137, 255};
        case SMSMetalSceneClear: return {0, 0, 0, 255};
    }
    return {0, 0, 0, 0};
}

- (NSDictionary*)verifyScene:(SMSMetalScene)scene name:(NSString*)name width:(NSUInteger)width height:(NSUInteger)height
{
    MTLTextureDescriptor* colorDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
        scene == SMSMetalSceneSRGB ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm
        width:width height:height mipmapped:NO];
    colorDescriptor.storageMode = MTLStorageModeShared;
    colorDescriptor.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> color = [self.device newTextureWithDescriptor:colorDescriptor];
    MTLTextureDescriptor* depthDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
        width:width height:height mipmapped:NO];
    depthDescriptor.storageMode = MTLStorageModePrivate;
    depthDescriptor.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> depth = [self.device newTextureWithDescriptor:depthDescriptor];
    if (!color || !depth) return @{@"name": name, @"passed": @NO,
        @"width": @(width), @"height": @(height), @"error": @"Offscreen texture allocation failed."};
    MTLRenderPassDescriptor* descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    descriptor.colorAttachments[0].texture = color;
    descriptor.depthAttachment.texture = depth;
    NSError* error = nil;
    id<MTLCommandBuffer> buffer = [self encodeScene:scene descriptor:descriptor width:width height:height error:&error];
    if (!buffer) return @{@"name": name, @"passed": @NO, @"width": @(width), @"height": @(height),
        @"error": error.localizedDescription ?: @"Command encoding failed."};
    [buffer commit];
    [buffer waitUntilCompleted];
    if (buffer.status != MTLCommandBufferStatusCompleted) return @{@"name": name, @"passed": @NO,
        @"width": @(width), @"height": @(height), @"error": buffer.error.localizedDescription ?: @"GPU command failed."};
    std::vector<std::uint8_t> pixels(width * height * 4);
    [color getBytes:pixels.data() bytesPerRow:width * 4 fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];
    NSUInteger mismatched = 0;
    int maximumError = 0;
    for (NSUInteger row = 0; row < height; ++row) {
        for (NSUInteger column = 0; column < width; ++column) {
            const auto expected = ExpectedPixel(scene, column, row, width, height);
            bool matches = true;
            for (NSUInteger channel = 0; channel < 4; ++channel) {
                int difference = std::abs(int(pixels[(row * width + column) * 4 + channel]) - expected[channel]);
                maximumError = std::max(maximumError, difference);
                matches = matches && difference <= 2;
            }
            if (!matches) ++mismatched;
        }
    }
    return @{@"name": name, @"passed": @(mismatched == 0), @"width": @(width), @"height": @(height),
        @"checkedPixels": @(width * height), @"mismatchedPixels": @(mismatched),
        @"maximumChannelError": @(maximumError), @"channelTolerance": @2};
}

- (NSDictionary*)verifyGraphics
{
    NSArray<NSString*>* names = @[@"clear", @"indexed-geometry", @"nearest-texture", @"depth-occlusion",
        @"source-alpha-blending", @"scissor", @"viewport", @"linear-to-srgb"];
    const NSUInteger dimensions[][2] = {{64, 64}, {256, 128}, {128, 256}, {60, 124}};
    NSMutableArray* tests = [NSMutableArray array];
    BOOL passed = YES;
    for (const auto& size : dimensions) {
        for (NSUInteger scene = 0; scene < names.count; ++scene) {
            @autoreleasepool {
                NSDictionary* result = [self verifyScene:static_cast<SMSMetalScene>(scene)
                    name:names[scene] width:size[0] height:size[1]];
                passed = passed && [result[@"passed"] boolValue];
                [tests addObject:result];
            }
        }
    }
    return @{@"schemaVersion": @1, @"scope": @"host-metal-only", @"passed": @(passed),
        @"simulator": @(TARGET_OS_SIMULATOR), @"metalDevice": self.device.name,
        @"system": NSProcessInfo.processInfo.operatingSystemVersionString, @"tests": tests,
        @"limitation": @"This verifies the native host diagnostic pipeline, not Sunshine GX rendering or gameplay."};
}

@end

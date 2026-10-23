#include <metal_stdlib>
using namespace metal;

struct DiagnosticVertex {
    packed_float3 position;
    packed_float4 color;
    packed_float2 uv;
};

struct DiagnosticFragment {
    float4 position [[position]];
    float4 color;
    float2 uv;
};

vertex DiagnosticFragment diagnosticVertex(uint vertexID [[vertex_id]],
    const device DiagnosticVertex* vertices [[buffer(0)]])
{
    DiagnosticFragment output;
    output.position = float4(float3(vertices[vertexID].position), 1.0);
    output.color = float4(vertices[vertexID].color);
    output.uv = float2(vertices[vertexID].uv);
    return output;
}

fragment float4 diagnosticFragment(DiagnosticFragment input [[stage_in]],
    texture2d<float> image [[texture(0)]], sampler imageSampler [[sampler(0)]])
{
    return input.color * image.sample(imageSampler, input.uv);
}

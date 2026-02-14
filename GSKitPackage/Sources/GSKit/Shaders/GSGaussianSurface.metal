#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

[[visible]]
void gskit_gaussian_surface(realitykit::surface_parameters params) {
    const float2 uv = params.geometry().uv0();
    const float radiusSquared = dot(uv, uv);
    const half4 vertexColor = half4(params.geometry().color());

    const half safeAlpha = max(vertexColor.a, half(0.0001));
    const half3 unpremultipliedColor = clamp(vertexColor.rgb / safeAlpha, half3(0.0), half3(1.0));
    const half gaussian = radiusSquared > 6.25f ? half(0.0) : half(exp(-0.5f * radiusSquared));
    const half opacity = saturate(vertexColor.a * gaussian);

    params.surface().set_emissive_color(unpremultipliedColor);
    params.surface().set_opacity(opacity);
}

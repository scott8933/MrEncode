#include <metal_stdlib>
using namespace metal;

inline float3 RGB_FROM_BGRA(float4 bgra) {
    // For MTLPixelFormat.bgra8Unorm, Metal swizzles reads to RGBA in shader space.
    return float3(bgra.x, bgra.y, bgra.z);
}

inline void rgb_to_ycbcr_709_full(float3 rgb, thread float &y, thread float &cb, thread float &cr) {
    y  = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    cb = (rgb.b - y) / (2.0 * (1.0 - 0.0722)) + 0.5;
    cr = (rgb.r - y) / (2.0 * (1.0 - 0.2126)) + 0.5;
}

// Map normalized full-range 0..1 Y' into 10-bit limited range (64..940), then back to 0..1.
inline float toLimitedY10(float y01) {
    const float yMin = 64.0 / 1023.0;
    const float yMax = 940.0 / 1023.0;
    return clamp(yMin + clamp(y01, 0.0, 1.0) * (yMax - yMin), 0.0, 1.0);
}

// Map normalized full-range 0..1 Cb/Cr into 10-bit limited range (64..960), then back to 0..1.
inline float toLimitedC10(float c01) {
    const float cMin = 64.0 / 1023.0;
    const float cMax = 960.0 / 1023.0;
    return clamp(cMin + clamp(c01, 0.0, 1.0) * (cMax - cMin), 0.0, 1.0);
}

// Compute limited-range chroma at (x,y) as normalized 0..1 floats
inline void chroma_limited_at(
    texture2d<float, access::sample> src,
    uint2 p,
    thread float &cbL,
    thread float &crL
) {
    float4 b = src.read(p);
    float3 r = RGB_FROM_BGRA(b);
    float yy, cb, cr;
    rgb_to_ycbcr_709_full(r, yy, cb, cr);
    cbL = toLimitedC10(cb);
    crL = toLimitedC10(cr);
}

kernel void bgra_to_p210_709_fullrange(
    texture2d<float, access::sample> src    [[texture(0)]],
    texture2d<float, access::write>  dstY   [[texture(1)]],  // r16Unorm
    texture2d<float, access::write>  dstUV  [[texture(2)]],  // rg16Unorm
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;

    // Center pixel
    float4 bgra = src.read(gid);
    float3 rgb  = RGB_FROM_BGRA(bgra);

    float y, cb, cr;
    rgb_to_ycbcr_709_full(rgb, y, cb, cr);

    // Limited-range mapping (normalized 0..1, matches VideoRange destination)
    float yL  = toLimitedY10(y);
    float cb0 = toLimitedC10(cb);
    float cr0 = toLimitedC10(cr);

    // Luma full-res
    dstY.write(float4(yL, 0.0, 0.0, 1.0), gid);

    // P210 UV: (w/2, h) full height, write one UV sample per 2 luma pixels (even x)
    if ((gid.x & 1u) == 0u) {
        uint x0  = gid.x;
        uint xm1 = (x0 == 0u) ? 0u : (x0 - 1u);
        uint x1  = min(x0 + 1u, w - 1u);
        uint x2  = min(x0 + 2u, w - 1u);

        float cbm1, crm1;
        float cb1,  cr1;
        float cb2,  cr2;

        chroma_limited_at(src, uint2(xm1, gid.y), cbm1, crm1);
        chroma_limited_at(src, uint2(x1,  gid.y), cb1,  cr1);
        chroma_limited_at(src, uint2(x2,  gid.y), cb2,  cr2);

        // 4-tap horizontal low-pass (left-anchored): [2 4 1 1] / 8
        float cbF = (2.0 * cbm1 + 4.0 * cb0 + 1.0 * cb1 + 1.0 * cb2) * 0.125;
        float crF = (2.0 * crm1 + 4.0 * cr0 + 1.0 * cr1 + 1.0 * cr2) * 0.125;

        uint2 uvCoord = uint2(gid.x >> 1, gid.y);
        dstUV.write(float4(clamp(cbF, 0.0, 1.0), clamp(crF, 0.0, 1.0), 0.0, 1.0), uvCoord);
    }
}

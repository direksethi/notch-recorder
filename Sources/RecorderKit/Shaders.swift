/// Metal source compiled at runtime (the Command Line Tools ship no `metal`
/// compiler). Three compute passes: horizontal Lanczos-3, vertical Lanczos-3,
/// then BT.709 limited-range RGB to NV12 with 2x2 chroma averaging.
enum Shaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct ScaleParams {
        float scale;   // source pixels per destination pixel
        float support; // kernel radius in source pixels
        uint srcLength;
    };

    inline float sinc(float x) {
        if (fabs(x) < 1e-5) return 1.0;
        float px = M_PI_F * x;
        return sin(px) / px;
    }

    inline float lanczos3(float x) {
        x = fabs(x);
        return x < 3.0 ? sinc(x) * sinc(x / 3.0) : 0.0;
    }

    template <bool Horizontal>
    inline float4 resample(texture2d<float, access::read> src, uint2 gid, constant ScaleParams& p) {
        float center = (float(Horizontal ? gid.x : gid.y) + 0.5) * p.scale;
        float filterScale = max(p.scale, 1.0);
        int first = int(floor(center - p.support));
        int last = int(ceil(center + p.support));
        float4 sum = 0.0;
        float weights = 0.0;
        for (int i = first; i <= last; i++) {
            float w = lanczos3((float(i) + 0.5 - center) / filterScale);
            if (w == 0.0) continue;
            int c = clamp(i, 0, int(p.srcLength) - 1);
            uint2 coord = Horizontal ? uint2(c, gid.y) : uint2(gid.x, c);
            sum += src.read(coord) * w;
            weights += w;
        }
        return weights != 0.0 ? sum / weights : sum;
    }

    kernel void scaleHorizontal(texture2d<float, access::read> src [[texture(0)]],
                                texture2d<float, access::write> dst [[texture(1)]],
                                constant ScaleParams& p [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
        dst.write(resample<true>(src, gid, p), gid);
    }

    kernel void scaleVertical(texture2d<float, access::read> src [[texture(0)]],
                              texture2d<float, access::write> dst [[texture(1)]],
                              constant ScaleParams& p [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
        dst.write(resample<false>(src, gid, p), gid);
    }

    inline float lumaOf(float3 rgb) {
        return dot(rgb, float3(0.2126, 0.7152, 0.0722));
    }

    // Writes one 2x2 block: four luma samples and one averaged chroma sample.
    kernel void rgbToNV12(texture2d<float, access::read> src [[texture(0)]],
                          texture2d<float, access::write> lumaTex [[texture(1)]],
                          texture2d<float, access::write> chromaTex [[texture(2)]],
                          uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= chromaTex.get_width() || gid.y >= chromaTex.get_height()) return;
        float cb = 0.0;
        float cr = 0.0;
        for (uint dy = 0; dy < 2; dy++) {
            for (uint dx = 0; dx < 2; dx++) {
                uint2 p = gid * 2 + uint2(dx, dy);
                float3 rgb = clamp(src.read(p).rgb, 0.0, 1.0);
                float y = lumaOf(rgb);
                lumaTex.write(float4((16.0 + 219.0 * y) / 255.0), p);
                cb += (rgb.b - y) / 1.8556;
                cr += (rgb.r - y) / 1.5748;
            }
        }
        cb = (128.0 + 224.0 * (cb * 0.25)) / 255.0;
        cr = (128.0 + 224.0 * (cr * 0.25)) / 255.0;
        chromaTex.write(float4(cb, cr, 0.0, 0.0), gid);
    }
    """
}

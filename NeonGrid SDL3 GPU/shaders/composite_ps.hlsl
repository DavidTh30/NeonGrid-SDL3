// Pass 2 - composite. One invocation per output pixel.
//   * the dot sprite (built with BGRABitmap on the CPU: fill with lens and
//     center cut-out, ring + glow, contact sparks; RGBA16F texture holding the
//     three channel weights) is summed for every nearby dot, tinted with the
//     dot's fill / ring colour and the spark colour - same as the CPU
//     sprite pass, but at sub-pixel dot positions;
//   * haze = hardware bilinear sample of the dot-colour texture;
//   * background, exposure and vignette as in the CPU final pass.
// SDL3 GPU binding rules (D3D12): fragment textures/samplers = space2,
// fragment uniforms = space3.

Texture2D<float4> DotTex : register(t0, space2);
SamplerState DotSmp : register(s0, space2);
Texture2D<float4> SprTex : register(t1, space2);
SamplerState SprSmp : register(s1, space2);

cbuffer CompositeUniforms : register(b0, space3)
{
    float4 Grid;     // cell, originX, originY, time
    float4 Frame;    // width, height, nCols, nRows
    float4 Sprite;   // size N, ext (half size), reach (cells), -
    float4 Ring;     // saturation, white mix, breath amp, breath speed
    float4 HiCol;    // highlight rgb 0..255, boost
    float4 Bg;       // background rgb 0..255, haze intensity (0 = off)
    float4 Spark;    // spark rgb 0..255, -
    float4 Vig;      // strength (0 = off), inner, outer, exposure
};

static const float TwoPi = 6.28318530718;

float SStep(float e0, float e1, float x)
{
    float t = (e1 == e0) ? step(e0, x) : saturate((x - e0) / (e1 - e0));
    return t * t * (3.0 - 2.0 * t);
}

float4 main(float4 pos : SV_Position) : SV_Target
{
    float2 p = pos.xy;
    float cell = Grid.x;
    float2 origin = Grid.yz;
    int2 n = int2(Frame.zw);
    int2 c0 = int2(round((p - origin) / cell));
    int reach = (int)Sprite.z;
    float N = Sprite.x;
    float ext = Sprite.y;

    float3 acc = 0.0;
    for (int dj = -reach; dj <= reach; dj++)
    {
        for (int di = -reach; di <= reach; di++)
        {
            int2 idx = c0 + int2(di, dj);
            if (idx.x < 0 || idx.y < 0 || idx.x >= n.x || idx.y >= n.y) continue;
            float2 center = origin + float2(idx) * cell;
            float2 off = p - center;
            if (abs(off.x) > ext + 1.0 || abs(off.y) > ext + 1.0) continue;
            float3 s = SprTex.SampleLevel(SprSmp, (off + ext + 0.5) / N, 0).rgb;
            if (s.x + s.y + s.z <= 0.0) continue;

            float4 d = DotTex.Load(int3(idx, 0));
            float3 base = d.rgb * 255.0;
            float hl = d.a;
            float3 fill = base + (HiCol.rgb - base) * hl * 0.35;
            float gray = (base.r + base.g + base.b) / 3.0;
            float3 ring = max(0.0, gray + (base - gray) * Ring.x) + 255.0 * Ring.y;
            ring += (HiCol.rgb - ring) * hl;
            float br = 1.0 + Ring.z * sin(TwoPi * Grid.w * Ring.w + (center.y / Frame.y) * 3.0);
            ring = clamp(ring * br * (1.0 + hl * (HiCol.w - 1.0)), 0.0, 1023.0);
            acc += s.x * fill + s.y * ring + s.z * Spark.rgb;
        }
    }

    float3 col = Bg.rgb + acc;
    if (Bg.w > 0.0)
    {
        float2 uv = ((p - origin) / cell + 0.5) / Frame.zw;
        col += DotTex.SampleLevel(DotSmp, uv, 0).rgb * 255.0 * Bg.w;
    }
    col = min(col, 1024.0);
    float2 q = p / Frame.xy * 2.0 - 1.0;
    float vig = 1.0 - Vig.x * SStep(Vig.y, Vig.z, length(q));
    col *= vig * Vig.w;
    return float4(saturate(col / 255.0), 1.0);
}

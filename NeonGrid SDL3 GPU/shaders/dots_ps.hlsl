// Pass 1 - dot states. Rendered into an RGBA16F target with one pixel per
// dot (NCols x NRows). Port of TNeonRenderer.FieldColor + ComputeDot:
// colour field (8 gaussian blobs + ambient), boundary, corner shadow,
// brightness/hue jitter, sparkles, flow trail and highlights.
// Output: rgb = dot colour / 255, a = highlight (0..1).
// SDL3 GPU binding rules (D3D12): fragment uniforms = register(bN, space3).

cbuffer DotUniforms : register(b0, space3)
{
    float4 Grid;          // cell, originX, originY, time
    float4 Frame;         // width, height, shiftI, shiftJ
    float4 Field0;        // ambient weight, brightness, saturation, -
    float4 Ambient;       // rgb 0..255
    float4 BlobPos[8];    // x, y, radius, weight
    float4 BlobAnim[8];   // drift amp, drift speed, enabled, -
    float4 BlobCol[8];    // rgb 0..255
    float4 Bound0;        // top x, bottom x, softness, strength
    float4 Bound1;        // wave amp, wave freq, wave speed, enabled
    float4 BoundCol;      // rgb 0..255
    float4 Shadow;        // x, y, radius, strength (0 = off)
    float4 Jitter;        // brightness, hue, speed, -
    float4 Sparkle;       // enabled, probability, speed, intensity
    float4 Trail0;        // enabled, offset, width, speed
    float4 Trail1;        // intensity, density, -, -
    float4 Highlight;     // enabled, probability, speed, -
    float4 Palette[6];    // rgb 0..255
};

static const float TwoPi = 6.28318530718;

// identical integer hash to uRenderer.Rnd (uint arithmetic wraps like Cardinal)
float Rnd(int a, int b, int s)
{
    uint h = (uint)a * 374761393u + (uint)b * 668265263u + (uint)s * 2246822519u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h = h ^ (h >> 16);
    return (float)(h & 0xFFFFFFu) / 16777216.0;
}

float SStep(float e0, float e1, float x)
{
    float t = (e1 == e0) ? step(e0, x) : saturate((x - e0) / (e1 - e0));
    return t * t * (3.0 - 2.0 * t);
}

float3 MixTo(float3 c, float3 target, float t)
{
    return c + (target - c) * saturate(t);
}

float3 Pal(float r)
{
    return Palette[((uint)(r * 6.0)) % 6u].rgb;
}

float BoundaryX(float v, float t)
{
    return Bound0.x + (Bound0.y - Bound0.x) * v + Bound1.x * sin(v * Bound1.y * TwoPi + t * Bound1.z);
}

float3 FieldColor(float u, float v, float t, float aspect)
{
    float sw = max(Field0.x, 1e-4);
    float3 c = Ambient.rgb * sw;
    [unroll]
    for (int i = 0; i < 8; i++)
    {
        if (BlobAnim[i].z > 0.5)
        {
            float bx = BlobPos[i].x + BlobAnim[i].x * sin(t * BlobAnim[i].y + i * 1.7);
            float by = BlobPos[i].y + BlobAnim[i].x * cos(t * BlobAnim[i].y * 0.83 + i * 2.9);
            float dx = (u - bx) * aspect;
            float dy = v - by;
            float w = BlobPos[i].w * exp(-(dx * dx + dy * dy) / max(1e-4, BlobPos[i].z * BlobPos[i].z));
            c += BlobCol[i].rgb * w;
            sw += w;
        }
    }
    c /= sw;
    float gray = (c.r + c.g + c.b) / 3.0;
    c = (gray + (c - gray) * Field0.z) * Field0.y;
    if (Bound1.w > 0.5)
    {
        float side = SStep(-Bound0.z, Bound0.z, u - BoundaryX(v, t)) * Bound0.w;
        c = MixTo(c, BoundCol.rgb, side);
    }
    if (Shadow.w > 0.0)
    {
        float d = sqrt(pow((u - Shadow.x) * aspect, 2.0) + pow(v - Shadow.y, 2.0)) / max(Shadow.z, 1e-3);
        c *= 1.0 - Shadow.w * (1.0 - SStep(0.0, 1.0, d));
    }
    return c;
}

float4 main(float4 pos : SV_Position) : SV_Target
{
    int i = (int)pos.x;
    int j = (int)pos.y;
    int k = i - (int)Frame.z;
    int l = j - (int)Frame.w;
    float t = Grid.w;
    float X = Grid.y + i * Grid.x;
    float Y = Grid.z + j * Grid.x;
    float u = X / Frame.x;
    float v = Y / Frame.y;
    float3 c = FieldColor(u, v, t, Frame.x / Frame.y);

    // brightness shimmer + hue jitter
    float a = 1.0 + Jitter.x * ((Rnd(k, l, 1) * 2.0 - 1.0) * 0.7 +
        0.3 * sin(TwoPi * t * Jitter.z * (0.5 + Rnd(k, l, 2)) + Rnd(k, l, 3) * TwoPi));
    c *= a;
    float rh = Rnd(k, l, 4);
    c = MixTo(c, Pal(Rnd(k, l, 5)), Jitter.y * rh * rh * 0.6);

    // sparkles
    if (Sparkle.x > 0.5 && Rnd(k, l, 6) < Sparkle.y)
    {
        a = sin(TwoPi * t * Sparkle.z * (0.5 + Rnd(k, l, 7)) + Rnd(k, l, 8) * TwoPi);
        float sp = a > 0.0 ? a * a * Sparkle.w : 0.0;
        c = MixTo(c, Pal(Rnd(k, l, 9)), sp);
    }

    // flow trail along the boundary
    float tw = 0.0;
    if (Trail0.x > 0.5)
    {
        a = (u - BoundaryX(v, t) - Trail0.y) * Frame.x / Grid.x;
        float w0 = max(0.05, Trail0.z);
        tw = exp(-(a / w0) * (a / w0));
        if (tw > 0.01)
        {
            float flow = l - t * Trail0.w;
            int idx = (int)floor(flow);
            float f = flow - idx;
            float p1 = Rnd(k, idx, 10) < Trail1.y ? 1.0 : 0.0;
            float p2 = Rnd(k, idx + 1, 10) < Trail1.y ? 1.0 : 0.0;
            float3 c1 = Pal(Rnd(k, idx, 11));
            float3 c2 = Pal(Rnd(k, idx + 1, 11));
            float3 tc = c1 + (c2 - c1) * f;
            c = MixTo(c, tc, tw * (p1 + (p2 - p1) * f) * Trail1.x);
        }
    }

    // white-hot highlights
    float hl = 0.0;
    if (Highlight.x > 0.5 && Rnd(k, l, 12) < Highlight.y * (1.0 + 4.0 * tw))
    {
        hl = sin(TwoPi * t * Highlight.z * (0.6 + 0.8 * Rnd(k, l, 13)) + Rnd(k, l, 14) * TwoPi);
        hl = hl > 0.0 ? pow(hl, 6.0) : 0.0;
    }

    c = round(clamp(c, 0.0, 255.0));
    return float4(c / 255.0, hl);
}

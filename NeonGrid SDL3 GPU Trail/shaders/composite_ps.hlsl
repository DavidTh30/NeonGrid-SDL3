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
Texture2D<float4> GameFx : register(t2, space2);   // z = offset up, w = offset right (cells), y = flash
SamplerState GameFxSmp : register(s2, space2);

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
    float4 Game;     // max |offset x| (cells), max |offset y| (cells), pop growth, -
    float4 Move0;    // dot motion: mode (0 = off), amount (cells), speed, frequency
    float4 Move1;    // centre x, centre y, push 0 / pull 1 / both 2, beads too
    float4 Shape;    // dot shape: angle (rad), spin (rad/s), variation 0..1, beads too
    float4 Shape2;   // bead shape: angle (rad), spin (rad/s), variation 0..1, own shape (sprite right half)
};

static const float TwoPi = 6.28318530718;

// identical integer hash to dots_ps / uRenderer.Rnd
float Rnd(int a, int b, int s)
{
    uint h = (uint)a * 374761393u + (uint)b * 668265263u + (uint)s * 2246822519u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h = h ^ (h >> 16);
    return (float)(h & 0xFFFFFFu) / 16777216.0;
}

// how far a background dot is moved (cells) - Move0.x = mode
float2 DotMove(int2 idx, float2 home, float t)
{
    int mode = (int)(Move0.x + 0.5);
    float A = Move0.y;
    float sp = Move0.z;
    float fq = max(0.05, Move0.w);
    float2 cpx = Move1.xy * Frame.xy;
    float2 dv = (home - cpx) / Grid.x;            // from the centre, in cells
    float dist = length(dv);
    float2 dir = dist > 1e-3 ? dv / dist : float2(0.0, 0.0);
    float env, ph, s;
    if (mode == 1)
    {
        // shaking with explosion-like bursts
        env = 0.2 + 0.8 * exp(-frac(t * sp * 0.25) * 5.0);
        ph = Rnd(idx.x, idx.y, 41) * TwoPi;
        return A * env * float2(sin(t * 31.0 * fq + ph), cos(t * 27.0 * fq + ph * 1.7));
    }
    if (mode == 2)
    {
        // squeezed back and forth: a compression wave runs through the grid
        return A * float2(sin(idx.x * fq * 0.6 - t * sp * 3.0), 0.35 * sin(idx.y * fq * 0.5 - t * sp * 2.3));
    }
    if (mode == 3)
    {
        // pushed away from / pulled towards a point that circles the centre
        float2 hole = cpx + float2(cos(t * sp * 0.6), sin(t * sp * 0.6)) * min(Frame.x, Frame.y) * 0.25;
        float2 hv = (home - hole) / Grid.x;
        float hd = length(hv);
        float2 hdir = hd > 1e-3 ? hv / hd : float2(0.0, 0.0);
        float w = exp(-(hd * hd) / (fq * fq * 9.0));
        s = Move1.z > 1.5 ? sin(t * sp * 1.7) : (Move1.z > 0.5 ? -1.0 : 1.0);
        return hdir * A * w * s * min(1.0, hd);
    }
    if (mode == 4)
    {
        // blast waves rolling out from the centre
        float ring = frac(t * sp * 0.25) * 30.0 / fq;
        float w = exp(-pow((dist - ring) / 2.0, 2.0));
        return dir * A * w * (1.0 - frac(t * sp * 0.25));
    }
    if (mode == 5)
    {
        // every dot circles its home, phases form a swirl
        ph = t * sp * 3.0 + (idx.x + idx.y) * fq * 0.4 + atan2(dv.y, dv.x);
        return A * float2(cos(ph), sin(ph));
    }
    if (mode == 6)
    {
        // breathing: the grid swells away from the centre and back
        return dv * (A * 0.08 * sin(t * sp * 1.5 - dist * fq * 0.2));
    }
    return float2(0.0, 0.0);
}

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
    // beads drawn away from their cell (moving trail: offsets in any
    // direction, up to Game.x / Game.y cells) can reach this pixel too
    int extra = Move0.x > 0.5 ? (int)ceil(Move0.y * 1.3) + 1 : 0;
    int moreX = (int)Game.x + extra;
    int moreY = (int)Game.y + extra;
    for (int dj = -reach - moreY; dj <= reach + moreY; dj++)
    {
        for (int di = -reach - moreX; di <= reach + moreX; di++)
        {
            int2 idx = c0 + int2(di, dj);
            if (idx.x < 0 || idx.y < 0 || idx.x >= n.x || idx.y >= n.y) continue;
            float4 fx = GameFx.Load(int3(idx, 0));
            float4 d = DotTex.Load(int3(idx, 0));
            bool isBead = d.a > 1.5;
            float hl = isBead ? d.a - 2.0 : d.a;
            float2 home = origin + float2(idx) * cell;
            float2 center = origin + (float2(idx) + float2(fx.w, -fx.z)) * cell;
            if (Move0.x > 0.5 && (!isBead || Move1.w > 0.5))
                center += DotMove(idx, home, Grid.w) * cell;
            float scale = 1.0 + Game.z * fx.y;
            float2 off = (p - center) / scale;
            if (abs(off.x) > ext + 1.0 || abs(off.y) > ext + 1.0) continue;
            // beads with their own shape: the right half of the sprite, their own turn
            bool own = isBead && Shape2.w > 0.5;
            float4 sh = own ? Shape2 : Shape;
            if ((sh.x != 0.0 || sh.y != 0.0) && (!isBead || own || Shape.w > 0.5))
            {
                // turn the shape around its centre
                float dirn = (sh.z > 0.0 && ((idx.x + idx.y) & 1) == 1) ? -1.0 : 1.0;
                float spd = 1.0 + sh.z * (Rnd(idx.x, idx.y, 51) - 0.5);
                float a = sh.x + sh.y * Grid.w * dirn * spd;
                float ca = cos(a), sa = sin(a);
                off = float2(off.x * ca + off.y * sa, -off.x * sa + off.y * ca);
            }
            float2 suv = (off + ext + 0.5) / N;
            if (any(suv < 0.0) || any(suv > 1.0)) continue;   // the two halves must not bleed
            suv.x = (suv.x + (own ? 1.0 : 0.0)) * 0.5;
            float3 s = SprTex.SampleLevel(SprSmp, suv, 0).rgb;
            if (s.x + s.y + s.z <= 0.0) continue;

            float3 base = d.rgb * 255.0;
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

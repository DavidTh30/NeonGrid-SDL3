// Pass 1 - dot states (Neon Beads). Rendered into an RGBA16F target with one
// pixel per dot (NCols x NRows). The animated neon background is computed as
// in the screensaver version and then combined with the game board:
//   GameTex  rgb = bead colour 0..1, a = presence 0..1 (-1 = outside board)
//   GameFx   x = hover 0..1, y = pop flash 0..1 (z, w = offsets, composite) Port of TNeonRenderer.FieldColor + ComputeDot:
// colour field (8 gaussian blobs + ambient), boundary, corner shadow,
// brightness/hue jitter, sparkles, flow trail and highlights.
// Output: rgb = dot colour / 255, a = highlight (0..1).
// SDL3 GPU binding rules (D3D12): fragment uniforms = register(bN, space3).

Texture2D<float4> GameTex : register(t0, space2);
SamplerState GameSmp : register(s0, space2);
Texture2D<float4> GameFx : register(t1, space2);
SamplerState GameFxSmp : register(s1, space2);

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
    float4 Game;          // dim outside board, dim of empty cells, bead shimmer, background highlight scale
    float4 Motion0;       // background motion: mode (0 = still), speed, amount, direction (radians)
    float4 Motion1;       // wave frequency / swirl size, centre x, centre y, -
    float4 Show0;         // colour show: mode (0 = off), strength, speed, size
    float4 Show1;         // rainbow (0 = palette), centre x, centre y, bars / arms
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

// background motion (Motion0.x = mode, 0 = still): moves where the colour
// field is sampled; the dots themselves stay on the board grid. Edges are
// mirrored, so a moving field never shows a seam.
float Mirror(float x)
{
    float f = frac(x * 0.5) * 2.0;
    return f < 1.0 ? f : 2.0 - f;
}

float2 MoveField(float u, float v, float t, float aspect)
{
    int mode = (int)(Motion0.x + 0.5);
    if (mode <= 0) return float2(u, v);
    float sp = Motion0.y;
    float amt = Motion0.z;
    float2 dir = float2(cos(Motion0.w), sin(Motion0.w));
    float2 c = Motion1.yz;                       // centre
    float2 p = float2((u - c.x) * aspect, v - c.y);  // aspect-correct, around the centre
    float a, s, r;
    if (mode == 1)                               // pan: continuous drift
        p += dir * (t * sp * 0.05);
    else if (mode == 2)                          // sway: back and forth
        p += dir * (amt * 0.25 * sin(t * sp));
    else if (mode == 3)                          // orbit: a circle
        p += amt * 0.25 * float2(cos(t * sp), sin(t * sp));
    else if (mode == 4)                          // rotate around the centre
    {
        a = t * sp * 0.2;
        p = float2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
    }
    else if (mode == 5)                          // zoom pulse
        p *= 1.0 + amt * 0.5 * sin(t * sp);
    else if (mode == 6)                          // wave / ripple
    {
        p.x += amt * 0.06 * sin(p.y * Motion1.x * TwoPi + t * sp);
        p.y += amt * 0.06 * sin(p.x * Motion1.x * TwoPi + t * sp * 0.8);
    }
    else if (mode == 7)                          // swirl: turns more near the centre
    {
        r = length(p);
        a = amt * 2.0 * sin(t * sp * 0.5) * exp(-r * r * 4.0 / max(0.05, Motion1.x));
        s = sin(a);
        p = float2(p.x * cos(a) - p.y * s, p.x * s + p.y * cos(a));
    }
    return float2(Mirror(p.x / aspect + c.x), Mirror(p.y + c.y));
}

// ---- colour show: a clearly visible pattern over the background colours
// (Show0.x = mode, 0 = off). Works on the fixed dot positions.
float3 Hue(float h)
{
    float3 k = saturate(abs(frac(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0);
    return k * 255.0;
}

float3 ShowPal(float x)
{
    if (Show1.x > 0.5) return Hue(x);
    return Palette[((uint)floor(abs(x) * 6.0)) % 6u].rgb;
}

// signed distance helpers (aspect-correct space)
float Circle(float2 p, float2 c, float r) { return length(p - c) - r; }

float4 ShowColor(float u, float v, float t, float aspect, int k, int l)
{
    int mode = (int)(Show0.x + 0.5);
    if (mode <= 0) return 0.0;
    float sp = Show0.z;
    float sc = max(0.1, Show0.w);
    float2 p = float2(u * aspect, v);
    float2 c = float2(Show1.y * aspect, Show1.z);
    float2 d = p - c;
    float r = length(d);
    float ang = atan2(d.y, d.x) / TwoPi;           // -0.5 .. 0.5
    float m = 0.0;
    float3 col = 0.0;
    if (mode == 1)
    {
        // audio-visualizer bars rising from the bottom
        float bars = max(3.0, Show1.w);
        float b = floor(u * bars);
        float tt = t * sp;
        float h = 0.42 + 0.25 * sin(tt * 2.1 + b * 0.9) + 0.17 * sin(tt * 3.7 + b * 2.3)
            + 0.12 * sin(tt * 7.3 + b * 5.1) + 0.1 * sin(tt * 1.3 + b * 7.7);
        h = saturate(h) * sc;
        float y = 1.0 - v;
        float gap = frac(u * bars);
        if (y < h && gap > 0.12 && gap < 0.88) m = 1.0;
        // peak caps float above the bars
        if (abs(y - h - 0.03) < 0.012 && gap > 0.12 && gap < 0.88) m = 1.0;
        if (Show1.x > 0.5) col = Hue(b / bars + tt * 0.02);
        else col = y < 0.45 ? float3(60, 255, 90) : (y < 0.72 ? float3(255, 230, 40) : float3(255, 50, 40));
    }
    else if (mode == 2)
    {
        // a spinning colour wheel / pinwheel
        float arms = max(2.0, Show1.w);
        float a = ang + t * sp * 0.15 + r * 0.6 / sc;
        m = 1.0;
        col = ShowPal(frac(a * arms / 6.0) * (Show1.x > 0.5 ? 1.0 : 6.0 / 6.0));
        if (Show1.x < 0.5) col = Palette[((uint)floor(frac(a) * arms)) % 6u].rgb;
    }
    else if (mode == 3)
    {
        // cartoon: a chomping round runner chased by a ghost, left to right
        float run = frac(t * sp * 0.07);
        float R = 0.11 * sc;
        float span = aspect + 6.0 * R;
        float2 pc = float2(-3.0 * R + run * span, c.y + 0.04 * abs(sin(t * sp * 3.0)));
        float mouth = 0.04 + 0.2 * abs(sin(t * sp * 6.0));
        float2 q = p - pc;
        float qa = abs(atan2(q.y, q.x)) / TwoPi;
        if (Circle(p, pc, R) < 0.0 && qa > mouth * 0.5)
        {
            m = 1.0;
            col = float3(255, 220, 30);
            if (Circle(p, pc + float2(0.15 * R, -0.5 * R), 0.13 * R) < 0.0) col = float3(20, 20, 30);
        }
        float2 gc = pc - float2(2.6 * R, 0.0);
        float2 g = p - gc;
        bool body = (g.y < 0.0 && length(g) < R) ||
            (g.y >= 0.0 && abs(g.x) < R && g.y < R * (0.8 + 0.2 * sin(g.x / R * 9.0 + t * sp * 8.0)));
        if (body)
        {
            m = 1.0;
            col = ShowPal(frac(t * sp * 0.05) + 0.3);
            float2 e1 = gc + float2(-0.35 * R, -0.25 * R);
            float2 e2 = gc + float2(0.35 * R, -0.25 * R);
            if (Circle(p, e1, 0.22 * R) < 0.0 || Circle(p, e2, 0.22 * R) < 0.0) col = float3(255, 255, 255);
            if (Circle(p, e1 + float2(0.08 * R, 0.0), 0.1 * R) < 0.0 || Circle(p, e2 + float2(0.08 * R, 0.0), 0.1 * R) < 0.0)
                col = float3(30, 40, 200);
        }
    }
    else if (mode == 4)
    {
        // ripples spreading from the centre
        float w = sin(r * 40.0 / sc - t * sp * 4.0);
        m = SStep(0.35, 0.9, w) * (1.0 - SStep(0.6, 1.3, r));
        col = ShowPal(floor(r * 40.0 / sc / TwoPi - t * sp * 4.0 / TwoPi) / 6.0);
    }
    else if (mode == 5)
    {
        // a spinning spiral that twists the colours
        float arms = max(1.0, Show1.w);
        float a = frac((ang - r * 1.6 / sc + t * sp * 0.12) * arms);
        m = SStep(0.0, 0.08, a) * (1.0 - SStep(0.42, 0.5, a));
        col = ShowPal(ang + t * sp * 0.05);
    }
    else if (mode == 6)
    {
        // plasma waves
        float tt = t * sp;
        float pv = sin(p.x * 9.0 / sc + tt) + sin(p.y * 11.0 / sc - tt * 1.3) +
            sin((p.x + p.y) * 7.0 / sc + tt * 0.7) + sin(r * 13.0 / sc - tt * 1.7);
        m = 1.0;
        col = Show1.x > 0.5 ? Hue(pv * 0.125 + tt * 0.03) : ShowPal(frac(pv * 0.125 + 0.5));
    }
    else if (mode == 7)
    {
        // falling rain / code columns
        float spd = 0.25 + Rnd(k, 0, 31);
        float head = frac(t * sp * spd * 0.25 + Rnd(k, 0, 32)) * 1.4 - 0.2;
        float tail = 0.25 * sc;
        float dy = head - v;
        m = (dy >= 0.0 && dy < tail) ? pow(1.0 - dy / tail, 1.5) : 0.0;
        col = dy < 0.02 ? float3(220, 255, 220) : (Show1.x > 0.5 ? Hue(Rnd(k, 0, 33)) : Palette[0].rgb);
    }
    return float4(col, m);
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
    float2 uv = MoveField(X / Frame.x, Y / Frame.y, t, Frame.x / Frame.y);
    float u = uv.x;
    float v = uv.y;
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

    // colour show over the background (fixed dot positions)
    if (Show0.x > 0.5)
    {
        float4 sh = ShowColor(X / Frame.x, Y / Frame.y, t, Frame.x / Frame.y, k, l);
        c = MixTo(c, sh.rgb, sh.a * Show0.y);
        hl = max(hl, sh.a * Show0.y * 0.25);
    }

    // ---- game board on top of the background
    float4 g = GameTex.Load(int3(i, j, 0));
    float4 fx = GameFx.Load(int3(i, j, 0));
    float pres = max(g.a, 0.0);
    float dim = g.a < -0.5 ? Game.x : Game.y;
    float3 bead = g.rgb * 255.0 * (1.0 + Game.z * sin(TwoPi * t * 0.4 + Rnd(i, j, 21) * TwoPi));
    c = lerp(c * dim, bead, pres);
    hl = max(hl * Game.w * (1.0 - pres), max(fx.y, fx.x * 0.55));

    c = round(clamp(c, 0.0, 255.0));
    // a = highlight; + 2 marks a bead (the composite pass keeps beads still)
    return float4(c / 255.0, hl + (pres > 0.5 ? 2.0 : 0.0));
}

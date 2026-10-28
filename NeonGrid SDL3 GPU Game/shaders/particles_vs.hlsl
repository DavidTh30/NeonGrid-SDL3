// Spark particles: each particle (StructuredBuffer, uploaded every frame) is a
// screen-aligned quad of 6 vertices generated from SV_VertexID.
// SDL3 GPU binding rules (D3D12): vertex storage buffers = register(tN, space0),
// vertex uniforms = register(bN, space1).

struct Particle
{
    float2 Pos;    // window pixels
    float Size;    // radius in pixels
    float Pad;
    float4 Col;    // rgb, alpha
};

StructuredBuffer<Particle> Parts : register(t0, space0);

cbuffer ParticleUniforms : register(b0, space1)
{
    float4 Screen;  // width, height
};

struct VSOut
{
    float4 Pos : SV_Position;
    float2 UV : TEXCOORD0;
    float4 Col : TEXCOORD1;
};

static const float2 Corners[6] =
{
    float2(-1, -1), float2(1, -1), float2(1, 1),
    float2(-1, -1), float2(1, 1), float2(-1, 1)
};

VSOut main(uint id : SV_VertexID)
{
    Particle p = Parts[id / 6];
    float2 q = Corners[id % 6];
    float2 px = p.Pos + q * p.Size;
    VSOut o;
    o.Pos = float4(px.x / Screen.x * 2.0 - 1.0, 1.0 - px.y / Screen.y * 2.0, 0.0, 1.0);
    o.UV = q;
    o.Col = p.Col;
    return o;
}

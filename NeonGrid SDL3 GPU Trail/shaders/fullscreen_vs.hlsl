// Full-screen triangle without vertex buffers: vertex ids 0,1,2 cover the
// whole render target. Fragment shaders work with SV_Position (pixel
// centres at .5, origin top-left, y down) - the same pixel grid as the CPU.

struct VSOut
{
    float4 Pos : SV_Position;
};

VSOut main(uint id : SV_VertexID)
{
    VSOut o;
    float2 uv = float2((id << 1) & 2, id & 2);
    o.Pos = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return o;
}

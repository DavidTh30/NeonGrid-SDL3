// HUD overlay: the BGRABitmap/SDL3_ttf HUD texture (same size as the
// swapchain) blended over the frame with straight alpha.
Texture2D<float4> HudTex : register(t0, space2);
SamplerState HudSmp : register(s0, space2);

float4 main(float4 pos : SV_Position) : SV_Target
{
    return HudTex.Load(int3(int2(pos.xy), 0));
}

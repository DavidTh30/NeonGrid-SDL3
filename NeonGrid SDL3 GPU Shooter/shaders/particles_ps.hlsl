// Spark particle: hot core + soft halo, premultiplied for additive blending.
struct PSIn
{
    float4 Pos : SV_Position;
    float2 UV : TEXCOORD0;
    float4 Col : TEXCOORD1;
};

float4 main(PSIn i) : SV_Target
{
    float d2 = dot(i.UV, i.UV);
    if (d2 > 1.0) discard;
    float a = (exp(-d2 * 9.0) + 0.45 * exp(-d2 * 2.5)) * (1.0 - d2) * i.Col.a;
    return float4(i.Col.rgb * a, a);
}

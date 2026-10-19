#ifndef BASIC_LIT_FORWARD_INCLUDED
#define BASIC_LIT_FORWARD_INCLUDED

// Unity includes
#include "UnityLightingCommon.cginc"
#include "AutoLight.cginc"

// Material properties
fixed4 _Color;
sampler2D _MainTex;
float4 _MainTex_ST;
sampler2D _BumpMap;
fixed4 _SpecularColor;
sampler2D _SpecularMap;
fixed3 _EmissionColor;
sampler2D _EmissionMap;

// appdata
struct appdata_basiclit
{
    float2 uv                   : TEXCOORD0;
    float4 vertex               : POSITION;  // Object-space position
    float3 normalOS             : NORMAL;    // Object-space normal
    float4 tangentOS            : TANGENT;   // Object-space tangent

    UNITY_VERTEX_INPUT_INSTANCE_ID
};

// v2f
struct v2f_basiclit
{
    float4 pos           : SV_POSITION; // Clip-space position
    
    float2 uv                   : TEXCOORD0;
    
    float3 positionWS           : TEXCOORD1;  // World-space position
    fixed3 normalWS             : TEXCOORD2;  // World-space normal
    fixed3 tangentWS            : TEXCOORD3;  // World-space tangent
    fixed3 bitangentWS          : TEXCOORD4;  // World-space bitangent
    
    UNITY_SHADOW_COORDS(5)
    UNITY_FOG_COORDS(6)
};

// Lighting functions
    
// Diffuse
fixed3 LightingDiffuse(UnityLight light, float distanceAttenuation, float shadowAttenuation, float3 normalWS)
{
    fixed3 lightColor = light.color * distanceAttenuation * shadowAttenuation;

    // Diffuse
    float NDL = saturate(dot(normalWS, light.dir));
    fixed3 diffuseColor = lightColor * NDL;

    return diffuseColor;
}

// Specular
fixed3 LightingSpecular(UnityLight light, float distanceAttenuation, float shadowAttenuation, float3 normalWS, float3 viewDirectionWS, fixed3 specular, float smoothness)
{
    fixed3 lightColor = light.color * distanceAttenuation * shadowAttenuation;

    // Specular
    float3 fixedVector = normalize(light.dir + viewDirectionWS);
    float NDH = saturate(dot(normalWS, fixedVector));
    float specularFactor = pow(NDH, smoothness);
    fixed3 specularColor = lightColor * specular * specularFactor;

    return specularColor;
}

// Get lit color
fixed4 Lighting(fixed3 albedo, fixed alpha, UnityLight light, float distanceAttenuation, float shadowAttenuation, float3 normalWS, float3 viewDirectionWS, fixed3 specular, float smoothness, fixed3 emission, fixed3 ambient)
{
    // Basic BlinnPhong lighting

    smoothness = exp2(11 * smoothness);
    
    // Lighting
    fixed3 diffuseColor = LightingDiffuse(light, distanceAttenuation, shadowAttenuation, normalWS);
    fixed3 specularColor = LightingSpecular(light, distanceAttenuation, shadowAttenuation, normalWS, viewDirectionWS, specular, smoothness);

    // Final color
    fixed3 finalColor = (diffuseColor + ambient) * albedo + emission;
    finalColor += specularColor;
    
    return fixed4(finalColor, alpha);
}

// Vertex function
v2f_basiclit LitForwardVert(appdata_basiclit input)
{
    v2f_basiclit output;

    UNITY_INITIALIZE_OUTPUT(v2f_basiclit, output);

    // For GPU instancing
    UNITY_SETUP_INSTANCE_ID(input);

    // Transformations
    float3 positionWS = mul(unity_ObjectToWorld, input.vertex).xyz;
    half3 normalWS = UnityObjectToWorldNormal(input.normalOS);
    half3 tangentWS = UnityObjectToWorldDir(input.tangentOS.xyz);
    half3 bitangentWS = cross(normalWS, tangentWS) * input.tangentOS.w;
    float4 positionCS = UnityObjectToClipPos(input.vertex);

    // Set output
    output.uv = TRANSFORM_TEX(input.uv, _MainTex);
    output.pos = positionCS;
    output.normalWS = normalWS;
    output.tangentWS = tangentWS;
    output.bitangentWS = bitangentWS;
    output.positionWS = positionWS;
    UNITY_TRANSFER_SHADOW(output, input.uv);
    UNITY_TRANSFER_FOG(output, positionCS);

    return output;
}

// Fragment function
fixed4 LitForwardFrag(v2f_basiclit input) : SV_Target
{
    fixed4 color;
    
    float2 uv = input.uv;
    
    // Sample main tex + color
    fixed4 mainTex = tex2D(_MainTex, uv);
    color = mainTex * _Color;
    
    // Sample normal map
    half3 normalTS = UnpackNormal(tex2D(_BumpMap, uv));
    half3 normalWS = normalize(mul(normalTS, float3x3(input.tangentWS, input.bitangentWS, input.normalWS)));
    
    // Sample emission map
    fixed3 emission = tex2D(_EmissionMap, uv).rgb * _EmissionColor;
    
    // Sample specular map
    fixed4 specular = tex2D(_SpecularMap, uv) * _SpecularColor;
    
    // Construct light data
    UnityLight light;
    light.color = _LightColor0;
    #if defined(POINT) || defined(SPOT)
    light.dir = normalize(_WorldSpaceLightPos0.xyz - input.positionWS);  // Direction to light source
    #else
    light.dir = _WorldSpaceLightPos0.xyz;  // Pos is direction for directional lights
    #endif
    UNITY_LIGHT_ATTENUATION(distanceAttenuation, input, input.positionWS);  // Distance attenuation
    float shadowAttenuation = UNITY_SHADOW_ATTENUATION(input, input.positionWS);  // Shadow attenuation
    float3 viewDirectionWS = normalize(_WorldSpaceCameraPos - input.positionWS);
    
    // Ambient light (only ForwardBase pass)
    #ifdef SAMPLE_AMBIENT
    fixed3 ambient = max(0, ShadeSH9(half4(normalWS, 1)));
    #else
    fixed3 ambient = 0;
    #endif
    
    // Lighting
    color = Lighting(color.rgb, color.a, light, distanceAttenuation, shadowAttenuation, normalWS, viewDirectionWS, specular.rgb, specular.a, emission, ambient);
    
    // Fog
    UNITY_APPLY_FOG(input.fogCoord, color);
    
    return color;
}

#endif

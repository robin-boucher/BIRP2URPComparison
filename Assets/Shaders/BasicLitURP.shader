Shader "Sample/BasicLitURP"
{
    Properties
    {
        // Main Texture, color
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        // Normal map
        [Normal] _BumpMap("Normal Map", 2D) = "bump" {}

        // Specular map
        [HDR] _SpecularColor("Specular Color (RGB: Color, A: Smoothness)", Color) = (1, 1, 1, 1)
        _SpecularMap("Specular Map", 2D) = "white" {}

        // Emission map
        [HDR] _EmissionColor("Emission Color", Color) = (0, 0, 0)
        _EmissionMap("Emission Map", 2D) = "white" {}
        
        // Toggle manual light distance attenuation quadratic falloff
        [Toggle] _MANUAL_BIRP_QUADRATIC_FALLOFF ("Manual Quadratic Light Falloff", Integer) = 0
        
        // Toggle manual light distance attenuation quadratic falloff
        [Toggle] _ANGLE_ATTENUATION_BIRP_COOKIE ("Angle Attenuation BIRP Cookie", Integer) = 0
    }
    
    SubShader
    {
        Tags
        {
            "Queue" = "Geometry"
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }
        LOD 200

        // Forward pass
        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }
            
            Blend Off
            ZWrite On
            Cull Back
            ZTest LEqual

            HLSLPROGRAM
            
            #pragma target 2.0

            // Vertex/fragment functions
            #pragma vertex LitForwardVert
            #pragma fragment LitForwardFrag

            // Keywords from URP settings
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN // Main light shadows
            #pragma multi_compile _ SHADOWS_SHADOWMASK                              // Shadow mask
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS    // Additional light support (includes vertex lighting option)
            #pragma multi_compile _ _LIGHT_FALLOFF_QUADRATIC                        // Quadratic light falloff mode to match BIRP lighting
            #pragma multi_compile _ _MANUAL_BIRP_QUADRATIC_FALLOFF_ON               // Manual qudratic light falloff override
            #pragma multi_compile _ _ANGLE_ATTENUATION_BIRP_COOKIE_ON               // Angle attenuation override to match BIRP "Soft" spot cookie texture
            #pragma multi_compile_fragment _ _LIGHT_COOKIES                         // Light cookies
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS              // Additional light shadow support
            #pragma multi_compile_fragment _ _SHADOWS_SOFT                          // Soft shadow support
            #pragma multi_compile _ _LIGHT_LAYERS                                   // Light Layer support
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX            // SH evaluation mode
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP                             // For Forward+
            
            // GPU Instancing
            #pragma multi_compile_instancing

            // URP includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Fog.hlsl"
            
            // Material properties, in cbuffer for SRP compatibility
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half3 _EmissionColor;
                half4 _SpecularColor;
            CBUFFER_END
            
            // Texture samplers
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            TEXTURE2D(_EmissionMap);
            SAMPLER(sampler_EmissionMap);
            TEXTURE2D(_SpecularMap);
            SAMPLER(sampler_SpecularMap);

            // Attributes
            struct Attributes
            {
                float2 uv                   : TEXCOORD0;
                float4 positionOS           : POSITION;  // Object-space position
                float3 normalOS             : NORMAL;    // Object-space normal
                float4 tangentOS            : TANGENT;   // Object-space tangent

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // Varyings
            struct Varyings
            {
                float2 uv                   : TEXCOORD0;
                
                float3 positionWS           : TEXCOORD1;   // World-space position
                half3 normalWS              : TEXCOORD2;   // World-space normal
                half3 tangentWS             : TEXCOORD3;   // World-space tangent
                half3 bitangentWS           : TEXCOORD4;   // World-space bitangent

                half3 vertexSH              : TEXCOORD5;   // GI SH
                
#ifdef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
                float4 shadowCoord          : TEXCOORD6;   // Vertex shadow coords if required
#endif
                half fogFactor              : TEXCOORD7;   // Fog Factor 
                
#if _ADDITIONAL_LIGHTS_VERTEX
                half4 vertexLighting        : TEXCOORD8;   // Vertex lighting 
#endif
                float4 positionCS           : SV_POSITION; // Clip-space position

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            // Vertex function
            Varyings LitForwardVert(Attributes input)
            {
                Varyings output;

                // GPU instancing
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // Transformations
                // See Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariablesFunctions.hlsl for helper functions
                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                float4 positionCS = positionInputs.positionCS;
                float3 positionWS = positionInputs.positionWS;
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);
                float3 normalWS = normalInputs.normalWS;
                float3 tangentWS = normalInputs.tangentWS;
                float3 bitangentWS = normalInputs.bitangentWS;

                // Set output
                OUTPUT_SH(normalWS, output.vertexSH);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.positionCS = positionCS;
                output.positionWS = positionWS;
                output.normalWS = normalWS;
                output.tangentWS = tangentWS;
                output.bitangentWS = bitangentWS;
#ifdef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
                // Vertex shadow coords if required
                output.shadowCoord = TransformWorldToShadowCoord(positionWS);
#endif

                // Fog
                output.fogFactor = ComputeFogFactor(positionCS.z);;

                // Vertex lighting if enabled
#if _ADDITIONAL_LIGHTS_VERTEX

#if _LIGHT_LAYERS
                // Get rendering layer if feature is enabled
                uint renderingLayer = GetMeshRenderingLayer();
#endif

                half3 vertexLight = 0;
                // Loop through additional lights to get vertex lighting
                uint additionalLightCount = GetAdditionalLightsCount();
                
                // Macro provided by URP to loop through additional lights
                LIGHT_LOOP_BEGIN(additionalLightCount)
                    Light light = GetAdditionalLight(lightIndex, positionWS);

#if _LIGHT_LAYERS
                    // If rendering layers are enabled, only process light if renderer's layer is included
                    if (IsMatchingLightLayer(light.layerMask, renderingLayer))
#endif
                    {
                        vertexLight += LightingDiffuse(light, normalWS);
                    }
                LIGHT_LOOP_END

                // Output fogFactor + vertexLight variable
                output.vertexLighting = vertexLighting;
#endif
                
                return output;
            }

            // Lighting functions
            
            // Diffuse
            half3 LightingDiffuse(Light light, float3 normalWS)
            {
                half3 lightColor = light.color * light.distanceAttenuation * light.shadowAttenuation;

                // Diffuse
                float NDL = saturate(dot(normalWS, light.direction));
                half3 diffuseColor = (lightColor * NDL);

                return diffuseColor;
            }

            // Specular
            half3 LightingSpecular(Light light, float3 normalWS, float3 viewDirectionWS, half3 specular, float smoothness)
            {
                half3 lightColor = light.color * light.distanceAttenuation * light.shadowAttenuation;

                // Specular
                float3 halfVector = normalize(light.direction + viewDirectionWS);
                float NDH = saturate(dot(normalWS, halfVector));
                float specularFactor = pow(NDH, smoothness);
                half3 specularColor = lightColor * specular * specularFactor;

                return specularColor;
            }
            
            // Get lit color
            half4 Lighting(InputData inputData, SurfaceData surfaceData)
            {
                // Basic BlinnPhong lighting

                float smoothness = exp2(11 * surfaceData.smoothness);
                
                // Get rendering layer if feature is enabled
#if _LIGHT_LAYERS
                uint renderingLayer = GetMeshRenderingLayer();
#endif

                // Main light
                half3 mainLightDiffuseColor = 0;
                half3 mainLightSpecularColor = 0;
                Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, inputData.shadowMask);
                MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);
#if _LIGHT_LAYERS
                // If rendering layers are enabled, only process light if renderer's layer is included
                if (IsMatchingLightLayer(mainLight.layerMask, renderingLayer))
#endif
                {
                    // Diffuse
                    mainLightDiffuseColor += LightingDiffuse(mainLight, inputData.normalWS) + inputData.vertexLighting;
                    // Specular
                    mainLightSpecularColor += LightingSpecular(mainLight, inputData.normalWS, inputData.viewDirectionWS, surfaceData.specular, smoothness);
                }

                // Additional lights
                half3 additionalLightsDiffuseColor = 0;
                half3 additionalLightsSpecularColor = 0;
#if _ADDITIONAL_LIGHTS
                // In URP, additional lights are handled in same pass with loop

#if USE_CLUSTER_LIGHT_LOOP // (USE_CLUSTER_LIGHT_LOOP is defined when _CLUSTER_LIGHT_LOOP keyword is enabled)
                // Loop through additional directional lights used Forward+
                for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                {
                    CLUSTER_LIGHT_LOOP_SUBTRACTIVE_LIGHT_CHECK

                    Light light = GetAdditionalLight(lightIndex, inputData.positionWS, inputData.shadowMask);

#if _LIGHT_LAYERS
                    // If rendering layers are enabled, only process light if renderer's layer is included
                    if (IsMatchingLightLayer(light.layerMask, renderingLayer))
#endif
                    {
                        // Diffuse
                        additionalLightsDiffuseColor += LightingDiffuse(light, inputData.normalWS) + inputData.vertexLighting;
                        // Specular
                        additionalLightsSpecularColor += LightingSpecular(light, inputData.normalWS, inputData.viewDirectionWS, surfaceData.specular, smoothness);
                    }
                }
#endif

                // Additional light count (returns 0 in Forward+)
                uint additionalLightCount = GetAdditionalLightsCount();

                // Macro provided by URP to loop through additional lights (point, spot, etc) in
                // both standard Forward and Forward+ (additionalLightCount is only used in Forward)
                // Provides lightIndex to fetch light with GetAdditionalLight
                // Forward: Loops through found additional lights
                // Forward+: Iterates through clusters to fetch lights
                // See RealtimeLights.hlsl for implementation
                LIGHT_LOOP_BEGIN(additionalLightCount)
                    Light light = GetAdditionalLight(lightIndex, inputData.positionWS, inputData.shadowMask);

#if _LIGHT_LAYERS
                    // If rendering layers are enabled, only process light if renderer's layer is included
                    if (IsMatchingLightLayer(light.layerMask, renderingLayer))
#endif
                    {
                        // Diffuse
                        additionalLightsDiffuseColor += LightingDiffuse(light, inputData.normalWS) + inputData.vertexLighting;
                        // Specular
                        additionalLightsSpecularColor += LightingSpecular(light, inputData.normalWS, inputData.viewDirectionWS, surfaceData.specular, smoothness);
                    }
                LIGHT_LOOP_END
#endif

                // Final color
                half3 finalColor = (mainLightDiffuseColor + additionalLightsDiffuseColor + inputData.vertexLighting + inputData.bakedGI) * surfaceData.albedo + surfaceData.emission;
                finalColor += (mainLightSpecularColor + additionalLightsSpecularColor);

                return half4(finalColor, surfaceData.alpha);
            }

            // Fragment function
            half4 LitForwardFrag(Varyings input) : SV_Target0
            {
                // Instancing
                UNITY_SETUP_INSTANCE_ID(input);
                
                half4 color;

                float2 uv = input.uv;

                // Sample base map + color
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv);
                color = baseMap * _BaseColor;

                // Sample normal map
                half3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv));
                half3 normalWS = normalize(mul(normalTS, float3x3(input.tangentWS, input.bitangentWS, input.normalWS)));

                // Sample emission map
                half3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionColor;

                // Sample specular map
                half4 specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv) * _SpecularColor;

                // Shadow coord
#ifdef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
                // Use vertex shadow coords if required
                float4 shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS) // MAIN_LIGHT_CALCULATE_SHADOWS = defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE) || defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                // Otherwise, set up for per-pixel shadow coords
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
#else
                float4 shadowCoord = 0;
#endif

                // Perform lighting
                // Built-in lighting functions can be found in Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl
                
                // URP's InputData is useful for holding data
                InputData inputData = (InputData)0;
                inputData.positionCS = input.positionCS;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = normalize(GetWorldSpaceViewDir(input.positionWS));
                inputData.shadowCoord = shadowCoord;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
                // Fog
                inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactor);
                // GI (SH)
                inputData.bakedGI = SAMPLE_GI(0, input.vertexSH, normalWS);
                // Vertex lighting
#if _ADDITIONAL_LIGHTS_VERTEX
                inputData.vertexLighting = input.vertexLighting;
#else 
                inputData.vertexLighting = 0;
#endif
                
                // URP's SurfaceData can be used hold data
                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = color.rgb;
                surfaceData.alpha = color.a;
                surfaceData.emission = emission;
                surfaceData.smoothness = specular.a;
                surfaceData.specular = specular.rgb;
                surfaceData.normalTS = normalTS;
                
                // Lighting
                color = Lighting(inputData, surfaceData);

                // Mix fog
                color.rgb = MixFog(color.rgb, inputData.fogCoord);

                return color;
            }

            ENDHLSL
        }

        // Shadow caster pass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            
            #pragma target 2.0

            // Vertex/fragment functions used by ShadowCasterPass.hlsl
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            // Keywords
            // Required by URP ShadowCasterPass.hlsl (used for normal bias differentiation)
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            // GPU Instancing
            #pragma multi_compile_instancing

            // URP includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Common properties, in cbuffer for SRP compatibility
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half3 _EmissionColor;
                half4 _SpecularColor;
            CBUFFER_END

            // Properties required by URP ShadowCasterPass.hlsl
            // NOTE: This shader does not support alpha cutout, but URP's pass
            //       requires this property, so we must define it
            //       This property should be exposed in Properties block and
            //       included in a CBUFFER if your shader supports alpha cutout functionality
            half _Cutoff;

            // URP's standard ShadowCasterPass
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            ENDHLSL
        }

        // DepthOnly pass
        // Used to render to _CameraDepthTexture
        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            Cull Back
            ColorMask R

            HLSLPROGRAM
            
            #pragma target 2.0

            // Vertex/fragment functions used in URP's DepthOnlyPass
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // GPU Instancing
            #pragma multi_compile_instancing

            // URP includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // Common properties, in cbuffer for SRP compatibility
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half3 _EmissionColor;
                half4 _SpecularColor;
            CBUFFER_END

            // Properties required by URP DepthOnlyPass.hlsl
            // NOTE: This shader does not support alpha cutout, but URP's pass
            //       requires this property, so we must define it
            //       This property should be exposed in Properties block and
            //       included in a CBUFFER if your shader supports alpha cutout functionality
            half _Cutoff;

            // URP's standard DepthOnlyPass
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"

            ENDHLSL
        }

        // DepthNormals pass
        // Used to render to _CameraNormalsTexture
        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On
            Cull Back

            HLSLPROGRAM

            // Target
            #pragma target 2.0

            // Vertex/fragment functions used in URP's DepthNormalsPass
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // GPU Instancing
            #pragma multi_compile_instancing

            // URP includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Common properties, in cbuffer for SRP compatibility
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half3 _EmissionColor;
                half4 _SpecularColor;
            CBUFFER_END

            // Properties required by URP DepthNormalsPass.hlsl
            // NOTE: This shader does not support alpha cutout, but URP's pass
            //       requires this property, so we must define it
            //       This property should be exposed in Properties block and
            //       included in a CBUFFER if your shader supports alpha cutout functionality
            half _Cutoff;

            // URP's SimpleLit DepthNormalsPass
            #include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitDepthNormalsPass.hlsl"

            ENDHLSL
        }
    }
}

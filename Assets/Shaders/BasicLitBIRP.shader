Shader "Sample/BasicLitBIRP"
{
    Properties
    {
        // Main Texture, color
        _Color("Main Color", Color) = (1, 1, 1, 1)
        _MainTex("Main Texture", 2D) = "white" {}

        // Normal map
        [Normal] _BumpMap("Normal Map", 2D) = "bump" {}

        // Specular map
        [HDR] _SpecularColor("Specular Color (RGB: Color, A: Smoothness)", Color) = (1, 1, 1, 1)
        _SpecularMap("Specular Map", 2D) = "white" {}

        // Emission map
        [HDR] _EmissionColor("Emission Color", Color) = (0, 0, 0)
        _EmissionMap("Emission Map", 2D) = "white" {}
    }
    
    SubShader
    {
        Tags
        {
            "Queue" = "Geometry"
            "RenderType" = "Opaque"
        }
        
        LOD 200
            
        // Forward base pass (main light)
        Pass
        {
            Name "ForwardBase"
            Tags { "LightMode" = "ForwardBase" }
            
            Blend Off
            ZWrite On
            Cull Back
            ZTest LEqual

            CGPROGRAM
            
            #pragma target 2.0

            // Vertex/fragment functions
            #pragma vertex LitForwardVert
            #pragma fragment LitForwardFrag

            // Keywords (skip lightmaps for sample purposes)
            #pragma multi_compile_fwdbase
            #pragma skip_variants LIGHTMAP_ON DYNAMICLIGHTMAP_ON DIRLIGHTMAP_COMBINED LIGHTMAP_SHADOW_MIXING
            
            // GPU Instancing
            #pragma multi_compile_instancing

            // Fog
            #pragma multi_compile_fog
            
            // Indicate that we want ambient light for this pass (only for ForwardBase)
            #define SAMPLE_AMBIENT
            
            // Unity includes
            #include "UnityCG.cginc"

            // Include shared forward pass
            #include "BIRPInc/BasicLitForward.cginc"
            
            ENDCG
        }

        // Forward add pass (additional lights)
        Pass
        {
            Name "ForwardAdd"
            Tags { "LightMode" = "ForwardAdd" }

            Blend One One
            ZWrite Off  // Don't write to depth twice

            CGPROGRAM

            #pragma target 2.0

            // Vertex/fragment functions
            #pragma vertex LitForwardVert
            #pragma fragment LitForwardFrag
            
            // Keywords (skip cookies and lightmaps for sample purposes)
            #pragma multi_compile_fwdadd_fullshadows
            #pragma skip_variants DIRECTIONAL_COOKIE POINT_COOKIE SPOT_COOKIE LIGHTMAP_SHADOW_MIXING
            
            // GPU Instancing
            #pragma multi_compile_instancing
            // Fog
            #pragma multi_compile_fog
            
            // Unity includes
            #include "UnityCG.cginc"

            // Include shared forward pass
            #include "BIRPInc/BasicLitForward.cginc"
            
            ENDCG
        }

        // ShadowCaster pass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual

            CGPROGRAM

            #pragma target 2.0

            // Vertex/fragment functions
            #pragma vertex ShadowCasterVert
            #pragma fragment ShadowCasterFrag

            // GPU Instancing
            #pragma multi_compile_instancing
            
            // Unity includes
            #include "UnityCG.cginc"

            // Vert input
            struct appdata
            {
                float4 vertex       : POSITION;   // Object-space position
                float3 normalOS     : NORMAL;     // Object-space normal

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // Vert output/Frag input
            struct v2f
            {
                float4 pos  : SV_POSITION; // Clip-space position
            };

            // Vertex function
            v2f ShadowCasterVert(appdata input)
            {
                v2f output;

                UNITY_SETUP_INSTANCE_ID(input);

                // Transformations and shadow bias
                float4 positionCS = UnityClipSpaceShadowCasterPos(input.vertex.xyz, input.normalOS);
                positionCS = UnityApplyLinearShadowBias(positionCS);

                // Set output
                output.pos = positionCS;

                return output;
            }

            // Fragment function
            fixed4 ShadowCasterFrag(v2f input) : SV_Target
            {
                return 0;
            }

            ENDCG
        }
    }
}

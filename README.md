# BIRP to URP Comparison

A sample Unity project showing how to migrate from the Built-in Render Pipeline (BIRP) to the Universal Render Pipeline (URP), and how to make URP match BIRP's look where the two pipelines differ by default.

Each topic has a BIRP reference scene and one or more URP scenes that try to reproduce it. All scenes use the same setup: the Chomper character and some cubes, lit by a directional light plus point and spot lights. That makes it easy to switch between scenes and compare them.

## Requirements

- Unity **6000.7**
- URP and Core RP are embedded as **modified local packages** in `LocalPackages/` (referenced from `Packages/manifest.json`). Most of the BIRP-matching changes live there. Search for `BIRP` in the package source to find them.

## Switching between BIRP and URP

BIRP scenes must be viewed with the Built-in Render Pipeline, and URP scenes with URP. To switch, go to **Project Settings > Graphics > Default Render Pipeline** and select:

- **None** for scenes prefixed `BIRP`
- `Assets/URP/URP.asset` for scenes prefixed `URP`

## Sample scenes

All scenes are under `Assets/Scenes/`, grouped by topic.

### Attenuation (`Assets/Scenes/Attenuation/`)

Light distance attenuation and spot light angle attenuation. These scenes use simple custom Blinn-Phong shaders (one per pipeline) so the lighting differences come from the pipeline and not from the shading model.

| Scene | Pipeline | Description |
|---|---|---|
| `BIRPLitShaderScene` | BIRP | Reference scene. Uses `Shaders/BasicLitBIRP.shader` (ForwardBase/ForwardAdd passes, shared code in `Shaders/BIRPInc/BasicLitForward.cginc`). |
| `URPLitShaderScene` | URP | URP port of the same shader (`Shaders/BasicLitURP.shader`), single pass with an additional-lights loop that supports Forward and Forward+. Matches BIRP light falloff with the built-in **Light Falloff Mode = Quadratic** setting (URP asset > Lighting). The shader must declare the `_LIGHT_FALLOFF_QUADRATIC` keyword. One spot light uses the extracted BIRP default cookie (see below) to match BIRP's spot shape. |
| `URPLitShader_ManualQuadraticLightFalloffScene` | URP | For **Unity 6.6 and earlier**, where Light Falloff Mode doesn't exist. Overrides `DistanceAttenuation()` in URP's `ShaderLibrary/RealtimeLights.hlsl` to reproduce BIRP's quadratic falloff (`1 / (1 + 25·d²)` with a fade to zero at the light range). Enabled per material with the `_MANUAL_BIRP_QUADRATIC_FALLOFF_ON` keyword (the "Manual Quadratic Light Falloff" toggle on `BasicLitURP`). |
| `URPLitShader_AngleAttenuationBIRPSpotCookie` | URP | Matches BIRP's spot light edge **without a cookie texture**. Overrides `AngleAttenuation()` in `RealtimeLights.hlsl` to calculate the normalized cone radius BIRP uses to sample its default "Soft" spot cookie, then approximates the cookie with a smoothstep. Enabled with the `_ANGLE_ATTENUATION_BIRP_COOKIE_ON` keyword (the "Angle Attenuation BIRP Cookie" toggle on `BasicLitURP`). |

#### Spot cookie extractor

BIRP spot lights without a cookie use a built-in default cookie (`Soft.psd`) that shapes their angular falloff. URP has no equivalent. To use it in URP:

1. Run **Tools > BIRP to URP > Extract Default Spot Cookie...** (`Assets/Editor/BIRPSpotCookieExtractor.cs`). It writes the built-in texture to a PNG imported as a cookie. A pre-extracted copy is at `Assets/URP/Cookies/BIRP_DefaultSpotCookie.png`.
2. Assign it as the URP spot light's **Cookie**.
3. Set **Inner Spot Angle** equal to the outer angle, so the cookie alone shapes the edge.

### PBR (`Assets/Scenes/PBR/`)

Matching the BIRP **Standard** shader with the URP **Lit** shader.

| Scene | Pipeline | Description |
|---|---|---|
| `BIRPLitPBRScene` | BIRP | Reference scene using the BIRP Standard shader, with an HDR cubemap skybox (`Art/Textures/OasisSunset_T_Cube.exr`). |
| `URPLitPBRScene` | URP | Same scene and skybox, with `Universal Render Pipeline/Lit` materials that enable the **BIRP Standard BRDF** option (Lit material > Advanced Options, keyword `_BIRP_STANDARD_BRDF_ON`). |

The BIRP Standard BRDF option is a port of BIRP's `BRDF1_Unity_PBS` into the local URP package:

- **Diffuse:** Disney diffuse instead of Lambert for direct lights (`ShaderLibrary/BRDF.hlsl`, `Lighting.hlsl`).
- **Specular:** GGX NDF × Smith-joint GGX visibility × Schlick Fresnel, with BIRP's epsilons, its 0.002 roughness clamp, and no specular for a black specular color (`DirectBRDFSpecular_BIRP`).
- **Metallic:** the slider is converted sRGB → linear in Linear color space, to match BIRP's `[Gamma] _Metallic` property (`Shaders/LitInput.hlsl`).
- **Reflections off:** uses `unity_IndirectSpecColor` (the average skybox color, like BIRP) instead of `_GlossyEnvironmentColor` (`ShaderLibrary/GlobalIllumination.hlsl`).
- **Gamma color space:** uses BIRP's gamma-space dielectric specular (0.04 converted to sRGB), surface reduction approximation and square-rooted specular term.

### PostProcess (`Assets/Scenes/PostProcess/`)

Matching BIRP Post Processing Stack v2 (PPv2) color grading with URP post-processing.

| Scene | Pipeline | Description |
|---|---|---|
| `BIRPColorGradingScene` | BIRP | Reference scene with PPv2 color grading in **LDR** mode (profile in `BIRPColorGradingScene_Profiles/Profile.asset`). |
| `URPColorGradingScene` | URP | Same grading with a URP Volume (`URPColorGradingScene/VolumeProfile.asset`) and the URP asset set to **LDR** grading. PPv2 applies its LDR LUT in gamma space, so `ApplyColorGrading()` in URP's `Shaders/PostProcessing/Common.hlsl` converts to sRGB before the internal LUT lookup and back to linear afterwards. |

## Project layout

| Path | Contents |
|---|---|
| `Assets/Scenes/` | The sample scenes described above |
| `Assets/Shaders/` | `BasicLitBIRP` / `BasicLitURP` custom Blinn-Phong shaders used by the Attenuation samples |
| `Assets/Art/` | Chomper model, textures, and the per-sample BIRP/URP materials; environment materials and skybox |
| `Assets/URP/` | URP asset, renderer, global settings, default volume profile (bloom disabled), and the extracted BIRP spot cookie |
| `Assets/Editor/` | `BIRPSpotCookieExtractor` editor tool |
| `LocalPackages/` | Modified `com.unity.render-pipelines.universal` and `com.unity.render-pipelines.core` packages with the BIRP-matching changes |

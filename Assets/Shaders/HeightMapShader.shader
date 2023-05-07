Shader "Custom/HeightMapShader"
{
	Properties
	{
		_Color ("Color", Color) = (1,1,1,1)
		_MainTexture ("Albedo (RGB)", 2D) = "white" {}
		_Metallic ("Metallic", Range(0,1)) = 0.0
		_Glossiness ("Smoothness", Range(0,1)) = 0.5

		[NoScaleOffset] _NormalMap("Normal map", 2D) = "white" {}
		_NormalStrength("Normal strength", Float) = 1

		_HeightFactor("Scale", Float) = 0.005
		_HeightMap("Height Map", 2D) = "black" {}

		[HDR] _EmissionColor("Color", Color) = (0,0,0)
		_TessellationUniform("Tesselation Uniform", Range(1, 64)) = 1
	}
	SubShader
	{
		Tags
		{
			"RenderType" = "Opaque"
			"Queue" = "Geometry"
			"RenderPipeline" = "UniversalPipeline"
		}
		LOD 200

		HLSLINCLUDE
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#if UNITY_VERSION >= 202120
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
			#pragma multi_compile _ _SHADOWS_SOFT

			#define UNITY_PI 3.14159265359f
			#define UNITY_TWO_PI 6.28318530718f

			TEXTURE2D(_MainTexture); SAMPLER(sampler_MainTexture);
			TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
			TEXTURE2D(_HeightMap); SAMPLER(sampler_HeightMap);

			CBUFFER_START(UnityPerMaterial)
				float4 _Color;
				float4 _MainTexture_ST;
				float _Glossiness;
				float _Metallic;

				float _NormalStrength;

				float _HeightFactor;

				float4 _EmissionColor;
				float _TessellationUniform;

				float _Cutoff;
			CBUFFER_END

			float3 GetViewDirectionFromPosition(float3 positionWS) {
				return normalize(GetCameraPositionWS() - positionWS);
			}

			float4 GetShadowCoord(float3 positionWS, float4 positionCS) {
				// Calculate the shadow coordinate depending on the type of shadows currently in use
#if SHADOWS_SCREEN
				return ComputeScreenPos(positionCS);
#else
				return TransformWorldToShadowCoord(positionWS);
#endif
			}

			struct VSInput
			{
				float4 positionOS : POSITION;
				float3 normalOS   : NORMAL;
				float4 tangentOS  : TANGENT;
				float2 uv         : TEXCOORD0;

				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct VSOutput
			{
				float3 positionWS : INTERNALTESSPOS;
				float4 positionCS : SV_POSITION;
				float3 normalWS   : NORMAL;
				float4 tangentWS  : TANGENT;
				float2 uv         : TEXCOORD0;
			};

			struct HSOutput
			{
				float edge[3] : SV_TessFactor;
				float inside  : SV_InsideTessFactor;
			};

			struct DSOutput
			{
				float2 uv                      : TEXCOORD0;
				float3 normalWS                : TEXCOORD1;
				float3 positionWS              : TEXCOORD2;
				float4 tangentWS               : TEXCOORD3;
				DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 4); // Lightmap UVs or light probe color
				float4 fogFactorAndVertexLight : TEXCOORD5;
				float4 positionCS              : SV_POSITION;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			HSOutput PatchMain(InputPatch<VSOutput, 3> patch)
			{
				UNITY_SETUP_INSTANCE_ID(patch[0]); // Set up instancing
				HSOutput output = (HSOutput)0;
				output.edge[0] = _TessellationUniform;
				output.edge[1] = _TessellationUniform;
				output.edge[2] = _TessellationUniform;
				output.inside = _TessellationUniform;
				return output;
			}

			[domain("tri")]
			[outputcontrolpoints(3)]
			[outputtopology("triangle_cw")]
			[partitioning("integer")]
			[patchconstantfunc("PatchMain")]
			VSOutput HSMain(InputPatch<VSOutput, 3> patch, uint id: SV_OutputControlPointID)
			{
				return patch[id];
			}

			[domain("tri")]
			DSOutput DSMain(HSOutput input, OutputPatch<VSOutput, 3> patch, float3 barycentricCoords : SV_DomainLocation)
			{
				DSOutput output;

				UNITY_SETUP_INSTANCE_ID(patch[0]);
				UNITY_TRANSFER_INSTANCE_ID(patch[0], output);

				#define BARYCENTRIC_INTERPOLATE(fieldname) \
					patch[0].fieldname * barycentricCoords.x + \
					patch[1].fieldname * barycentricCoords.y + \
					patch[2].fieldname * barycentricCoords.z;

				float3 positionWS = BARYCENTRIC_INTERPOLATE(positionWS);
				float3 normalWS = BARYCENTRIC_INTERPOLATE(normalWS);
				float3 tangentWS = BARYCENTRIC_INTERPOLATE(tangentWS.xyz);

				float2 uv = BARYCENTRIC_INTERPOLATE(uv);
				// Sample the height map and offset position along the normal vector accordingly
				float height = SAMPLE_TEXTURE2D_LOD(_HeightMap, sampler_HeightMap, uv, 0).r * _HeightFactor;
				positionWS += normalWS * height;

				output.uv = uv;
				output.positionCS = TransformWorldToHClip(positionWS);
				output.normalWS = normalWS;
				output.positionWS = positionWS;
				output.tangentWS = float4(tangentWS, patch[0].tangentWS.w);

				float fogFactor = ComputeFogFactor(output.positionCS.z);
				float3 vertexLight = VertexLighting(output.positionWS, output.normalWS);
				output.fogFactorAndVertexLight = float4(fogFactor, vertexLight);

				return output;
			}
		ENDHLSL

		Pass
		{
			Name "GeometryPass"
			Tags { "LightMode" = "UniversalForward" }

			ZWrite On
			ZTest LEqual

			HLSLPROGRAM
			#pragma target 5.0 // 5.0 required for tessellation

			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
			#pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
			#pragma multi_compile_fragment _ _SHADOWS_SOFT
			#pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
			#pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
			#pragma multi_compile _ SHADOWS_SHADOWMASK
			#pragma multi_compile _ DIRLIGHTMAP_COMBINED
			#pragma multi_compile _ LIGHTMAP_ON
			#pragma multi_compile_fog
			#pragma multi_compile_instancing

			// Material keywords
			#pragma shader_feature_local _PARTITIONING_INTEGER _PARTITIONING_FRAC_EVEN _PARTITIONING_FRAC_ODD _PARTITIONING_POW2
			#pragma shader_feature_local _TESSELLATION_SMOOTHING_FLAT _TESSELLATION_SMOOTHING_PHONG _TESSELLATION_SMOOTHING_BEZIER_LINEAR_NORMALS _TESSELLATION_SMOOTHING_BEZIER_QUAD_NORMALS
			#pragma shader_feature_local _TESSELLATION_FACTOR_CONSTANT _TESSELLATION_FACTOR_WORLD _TESSELLATION_FACTOR_SCREEN _TESSELLATION_FACTOR_WORLD_WITH_DEPTH
			#pragma shader_feature_local _TESSELLATION_SMOOTHING_VCOLORS
			#pragma shader_feature_local _TESSELLATION_FACTOR_VCOLORS
			#pragma shader_feature_local _GENERATE_NORMALS_MAP _GENERATE_NORMALS_HEIGHT

			#pragma require tessellation tessHW

			#pragma vertex VSMain
			#pragma hull HSMain
			#pragma domain DSMain
			#pragma fragment PSMain

			VSOutput VSMain(in VSInput input)
			{
				VSOutput output;
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_TRANSFER_INSTANCE_ID(input, output);

				VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
				VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

				output.positionWS = posnInputs.positionWS;
				output.positionCS = posnInputs.positionCS;
				output.normalWS = normalInputs.normalWS;
				output.tangentWS = float4(normalInputs.tangentWS, input.tangentOS.w);
				output.uv = TRANSFORM_TEX(input.uv, _MainTexture);
				return output;
			}

			float4 PSMain(in DSOutput input) : SV_Target
			{
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

				float4 mainSample = SAMPLE_TEXTURE2D(_MainTexture, sampler_MainTexture, input.uv);

				float3x3 tangentToWorld = CreateTangentToWorld(input.normalWS, input.tangentWS.xyz, input.tangentWS.w);
				// Calculate a tangent space normal either from the normal map or the height map
			#if defined(_GENERATE_NORMALS_MAP)
				float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv), _NormalStrength);
			#elif defined(_GENERATE_NORMALS_HEIGHT)
				float3 normalTS = GenerateNormalFromHeightMap(input.uv);
			#else
				float3 normalTS = float3(0, 0, 1);
			#endif
				float3 normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld)); // Convert to world space

				// Fill the various lighting and surface data structures for the PBR algorithm
				InputData lightingInput = (InputData)0; // Found in URP/Input.hlsl
				lightingInput.positionWS = input.positionWS;
				lightingInput.normalWS = normalWS;
				lightingInput.viewDirectionWS = GetViewDirectionFromPosition(lightingInput.positionWS);
				lightingInput.shadowCoord = GetShadowCoord(lightingInput.positionWS, input.positionCS);
				lightingInput.fogCoord = input.fogFactorAndVertexLight.x;
				lightingInput.vertexLighting = input.fogFactorAndVertexLight.yzw;
				lightingInput.bakedGI = SAMPLE_GI(input.lightmapUV, input.vertexSH, lightingInput.normalWS);
				lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
				lightingInput.shadowMask = SAMPLE_SHADOWMASK(input.lightmapUV);

				SurfaceData surface = (SurfaceData)0; // Found in URP/SurfaceData.hlsl
				surface.albedo = mainSample.rgb * _Color.rgb;
				surface.alpha = mainSample.a * _Color.a;
				surface.metallic = _Metallic;
				surface.smoothness = _Glossiness;
				surface.normalTS = normalTS;
				surface.occlusion = 1;

				return UniversalFragmentPBR(lightingInput, surface);
			}
			ENDHLSL
		}

		Pass
		{
			Name "ShadowCaster"
			Tags { "LightMode" = "ShadowCaster" }

			ZWrite On
			ZTest LEqual

			HLSLPROGRAM
			#pragma target 5.0 // 5.0 required for tessellation

			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
			#pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
			#pragma multi_compile_fragment _ _SHADOWS_SOFT
			#pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
			#pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
			#pragma multi_compile _ SHADOWS_SHADOWMASK
			#pragma multi_compile _ DIRLIGHTMAP_COMBINED
			#pragma multi_compile _ LIGHTMAP_ON
			#pragma multi_compile_fog
			#pragma multi_compile_instancing

			// Material keywords
			#pragma shader_feature_local _PARTITIONING_INTEGER _PARTITIONING_FRAC_EVEN _PARTITIONING_FRAC_ODD _PARTITIONING_POW2
			#pragma shader_feature_local _TESSELLATION_SMOOTHING_FLAT _TESSELLATION_SMOOTHING_PHONG _TESSELLATION_SMOOTHING_BEZIER_LINEAR_NORMALS _TESSELLATION_SMOOTHING_BEZIER_QUAD_NORMALS
			#pragma shader_feature_local _TESSELLATION_FACTOR_CONSTANT _TESSELLATION_FACTOR_WORLD _TESSELLATION_FACTOR_SCREEN _TESSELLATION_FACTOR_WORLD_WITH_DEPTH
			#pragma shader_feature_local _TESSELLATION_SMOOTHING_VCOLORS
			#pragma shader_feature_local _TESSELLATION_FACTOR_VCOLORS
			#pragma shader_feature_local _GENERATE_NORMALS_MAP _GENERATE_NORMALS_HEIGHT

			#pragma require tessellation tessHW

			#pragma vertex VSMain
			#pragma hull HSMain
			#pragma domain DSMain
			#pragma fragment PSMain

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

			float3 _LightDirection;
			float3 _LightPosition;

			float4 GetShadowPositionHClip(VSInput input)
			{
				float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
				float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

#if _CASTING_PUNCTUAL_LIGHT_SHADOW
				float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
				float3 lightDirectionWS = _LightDirection;
#endif

				float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

#if UNITY_REVERSED_Z
				positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
				positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif

				return positionCS;
			}

			// Custom vertex shader to apply shadow bias.
			VSOutput VSMain(VSInput input)
			{
				VSOutput output;
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_TRANSFER_INSTANCE_ID(input, output);

				VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
				VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

				output.positionWS = GetShadowPositionHClip(input);
				output.positionCS = posnInputs.positionCS;
				output.normalWS = normalInputs.normalWS;
				output.tangentWS = float4(normalInputs.tangentWS, input.tangentOS.w);
				output.uv = TRANSFORM_TEX(input.uv, _MainTexture);
				return output;
			}

			float4 PSMain(VSOutput i) : SV_Target
			{
				Alpha(SampleAlbedoAlpha(i.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a, _Color, _Cutoff);
				return 0;
			}
			ENDHLSL
		}
	}
	FallBack "Diffuse"
}

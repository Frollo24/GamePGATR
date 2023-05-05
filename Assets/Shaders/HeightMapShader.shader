Shader "Custom/HeightMapShader"
{
	Properties
	{
		_Color ("Color", Color) = (1,1,1,1)
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
		_Glossiness ("Smoothness", Range(0,1)) = 0.5
		_Metallic ("Metallic", Range(0,1)) = 0.0

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

			CBUFFER_START(UnityPerMaterial)
				float4 _Color;
				sampler2D _MainTex;
				float4 _MainTex_ST;
				float _Glossiness;
				float _Metallic;

				float4 _EmissionColor;
				float _TessellationUniform;

				float _Cutoff;
			CBUFFER_END

			struct VSInput
			{
				float4 position : POSITION;
				float3 normal   : NORMAL;
				float4 tangent  : TANGENT;
				float2 uv       : TEXCOORD0;
			};

			struct VSOutput
			{
				float4 position : SV_POSITION;
				float3 normal   : NORMAL;
				float4 tangent  : TANGENT;
				float2 uv       : TEXCOORD0;
				float3 worldPos : TEXCOORD1;
			};

			struct HSOutput
			{
				float edge[3] : SV_TessFactor;
				float inside  : SV_InsideTessFactor;
			};

			HSOutput PatchMain(InputPatch<VSOutput, 3> patch)
			{
				HSOutput output;
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
			VSOutput DSMain(HSOutput input, OutputPatch<VSOutput, 3> patch, float3 barycentricCoords : SV_DomainLocation)
			{
				VSOutput output;

				#define INTERPOLATE(fieldname) output.fieldname = \
					patch[0].fieldname * barycentricCoords.x + \
					patch[1].fieldname * barycentricCoords.y + \
					patch[2].fieldname * barycentricCoords.z;

				INTERPOLATE(position)
				INTERPOLATE(normal)
				INTERPOLATE(tangent)
				INTERPOLATE(uv)

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
			#pragma require tesselation tessHW

			#pragma vertex VSMain
			#pragma hull HSMain
			#pragma domain DSMain
			#pragma fragment PSMain

			VSOutput VSMain(in VSInput input)
			{
				VSOutput output;
				output.position = TransformObjectToHClip(input.position.xyz);
				output.worldPos = float4(TransformObjectToWorld(input.position.xyz), 1.0f);
				output.normal = input.normal;
				output.tangent = input.tangent;
				output.uv = input.uv;
				return output;
			}

			float4 PSMain(in VSOutput input) : SV_Target
			{
				float4 bladeTint = tex2D(_MainTex, input.uv);

#ifdef MAIN_LIGHT_CALCULATE_SHADOWS
				// Shadow receiving
				VertexPositionInputs vertexInput = (VertexPositionInputs)0;
				vertexInput.positionWS = input.worldPos;

				float4 shadowCoord = GetShadowCoord(vertexInput);
				half shadowAttenuation = saturate(MainLightRealtimeShadow(shadowCoord) + 0.25f);
				float4 shadowColor = lerp(0.0f, 1.0f, shadowAttenuation);
				bladeTint *= shadowColor;

				Light light = GetMainLight();
				bladeTint *= float4(max(light.color.xyz, 0.01), 1);
#endif
				return _Color * bladeTint + _EmissionColor;
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
			#pragma vertex VSMain
			#pragma fragment PSMain

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

			float3 _LightDirection;
			float3 _LightPosition;

			float4 GetShadowPositionHClip(VSInput input)
			{
				float3 positionWS = TransformObjectToWorld(input.position.xyz);
				float3 normalWS = TransformObjectToWorldNormal(input.normal);

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
			VSOutput VSMain(VSInput v)
			{
				VSOutput o;

				o.normal = TransformObjectToWorldNormal(v.normal);
				o.tangent = v.tangent;
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.position = GetShadowPositionHClip(v);

				return o;
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

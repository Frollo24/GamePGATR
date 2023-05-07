Shader "Custom/CellShade"
{
	Properties
	{
		_Color("Color", Color) = (1,1,1,1)
		_MainTex("Albedo (RGB)", 2D) = "white" {}
		_Glossiness("Smoothness", Range(0,100)) = 50
		_Metallic("Metallic", Range(0,1)) = 0.0

		[HDR] _EmissionColor("Color", Color) = (0,0,0)
		[HDR] _AmbientColor("Ambient Color", Color) = (0.4, 0.4, 0.4, 1)
		[HDR] _SpecularColor("Specular Color", Color) = (0.9, 0.9, 0.9, 1)
		[HDR] _RimColor("Rim Color", Color) = (1,1,1,1)

		_RimAmount("Rim Amount", Range(0, 1)) = 0.7
		_RimThreshold("Rim Threshold", Range(0, 1)) = 0.1
	}
		SubShader
		{
			Tags
			{
				"RenderType" = "Opaque"
				"RenderPipeline" = "UniversalPipeline"
				"PassFlags" = "OnlyDirectional"
			}
			LOD 200
			Cull Off

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
					float _Glossiness;
					float _Metallic;

					float4 _MainTex_ST;
					float4 _EmissionColor;
					float4 _AmbientColor;
					float4 _SpecularColor;
					float4 _RimColor;

					float _RimAmount;
					float _RimThreshold;
				CBUFFER_END

				struct VSInput
				{
					float4 position : POSITION;
					float3 normal   : NORMAL;

					float2 uv       : TEXCOORD0;
				};

				struct VSOutput
				{
					float4 position : SV_POSITION;
					float3 wNormal   : NORMAL;
					float2 uv       : TEXCOORD0;
					float3 viewDir	: TEXCOORD1;
					float3 worldPos : TEXCOORD2;

				};

			ENDHLSL

			Pass
			{
				Tags { "LightMode" = "UniversalForward" }

				ZWrite On
				ZTest LEqual

				HLSLPROGRAM
				#pragma require geometry

				#pragma vertex VSMain
				#pragma fragment PSMain

				VSOutput VSMain(in VSInput input)
				{
					VSOutput output;
					//output.position = TransformObjectToHClip(input.position.xyz);
					output.position = TransformObjectToHClip(input.position.xyz);
					output.wNormal = TransformObjectToWorldNormal(input.normal); 
					output.worldPos = TransformObjectToWorld(input.position.xyz);

					output.uv = TRANSFORM_TEX(input.uv, _MainTex);

					output.viewDir = GetWorldSpaceViewDir(input.position.xyz);


					return output;
				}

				float4 PSMain(in VSOutput input) : SV_Target
				{
					float4 text = tex2D(_MainTex, input.uv);
					float4 light = (1.0, 1.0, 1.0, 1.0);
					float4 specular = (0.0, 0.0, 0.0, 0.0);
					float4 rim = (0.0, 0.0, 0.0, 0.0);
					float4 shadowColor = (0.0, 0.0, 0.0, 0.0);
					Light mainlight = GetMainLight();

	#ifdef MAIN_LIGHT_CALCULATE_SHADOWS
					// Shadow receiving
					VertexPositionInputs vertexInput = (VertexPositionInputs)0;
					vertexInput.positionWS = input.worldPos;

					float4 shadowCoord = GetShadowCoord(vertexInput);
					half shadowAttenuation = saturate(MainLightRealtimeShadow(shadowCoord) + 0.25f);
					shadowColor = lerp(0.0f, 1.0f, shadowAttenuation);


	#endif

					float3 N = normalize(input.wNormal);
					float3 L = mainlight.direction;
					float3 viewDir = normalize(input.viewDir);
					float4 mainlightColor = float4(mainlight.color, 1);

					float NdotL = max(0, dot(N, L));
					float intensity = smoothstep(0, 0.1, NdotL * shadowColor.x);
					light = intensity * mainlightColor;


					float3 H = normalize(L + viewDir);
					float NdotH = max(0, dot(N, H));
					float specFactor = pow(NdotH * intensity, _Glossiness * _Glossiness);
					float smoothSpecFactor = smoothstep(0.005, 0.01, specFactor);
					specular = smoothSpecFactor * _SpecularColor;

					float4 rimDot = 1 - dot(viewDir, N);
					float rimFactor = rimDot * pow(NdotL, _RimThreshold);
					float smoothRimFactor = smoothstep(_RimAmount - 0.01, _RimAmount + 0.01, rimFactor);
					rim = rimFactor * _RimColor;



					return _Color * text * (light + _AmbientColor + specular + rim) + _EmissionColor;
				}
				ENDHLSL
			}
		}
		FallBack "Diffuse"
}
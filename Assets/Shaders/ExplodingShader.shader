Shader "Custom/ExplodeShader"
{
	Properties
	{
		_Color ("Color", Color) = (1,1,1,1)
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
		_Glossiness ("Smoothness", Range(0,1)) = 0.5
		_Metallic ("Metallic", Range(0,1)) = 0.0
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
			};

			struct GSOutput
			{
				float4 position : SV_POSITION;
				float2 uv       : TEXCOORD0;
				float3 worldPos : TEXCOORD1;
			};

			GSOutput VertexTransformWorldToClip(float3 pos, float2 uv)
			{
				GSOutput o;
				o.position = TransformObjectToHClip(pos);
				o.uv = uv;
				o.worldPos = pos;
				return o;
			}

			[maxvertexcount(3)]
			void GSMain(triangle VSOutput input[3], inout TriangleStream<GSOutput> triStream)
			{
				triStream.Append(VertexTransformWorldToClip(input[0].position, input[0].uv));
				triStream.Append(VertexTransformWorldToClip(input[1].position, input[1].uv));
				triStream.Append(VertexTransformWorldToClip(input[2].position, input[2].uv));
			}
		ENDHLSL

		Pass
		{
			Name "GrassPass"
			Tags { "LightMode" = "UniversalForward" }

			ZWrite On
			ZTest LEqual

			HLSLPROGRAM
			#pragma require geometry

			#pragma vertex VSMain
			#pragma geometry GSMain
			#pragma fragment PSMain

			VSOutput VSMain(in VSInput input)
			{
				VSOutput output;
				//output.position = TransformObjectToHClip(input.position.xyz);
				output.position = float4(TransformObjectToWorld(input.position.xyz), 1.0f);
				//output.position = input.position;
				output.normal = input.normal;
				output.tangent = input.tangent;
				output.uv = input.uv;
				return output;
			}

			float4 PSMain(in GSOutput input) : SV_Target
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

				return _Color * bladeTint;
			}
			ENDHLSL
		}
	}
	FallBack "Diffuse"
}

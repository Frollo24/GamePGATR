Shader "Custom/ExplodeShader"
{
	Properties
	{
		_Color ("Color", Color) = (1,1,1,1)
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
		_Glossiness ("Smoothness", Range(0,1)) = 0.5
		_Metallic ("Metallic", Range(0,1)) = 0.0

		_StartTime ("Start Time", Float) = 0.0

		[HDR] _EmissionColor("Color", Color) = (0,0,0)
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

				float _StartTime;

				float4 _EmissionColor;
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

			// Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
			// Extended discussion on this function can be found at the following link:
			// https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
			// Returns a number in the 0...1 range.
			float rand(float3 co)
			{
				return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
			}

			float3 rand3(float3 co)
			{
				float x = frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539) * 1.5)) * 43758.5453);
				float y = frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539) * 2.5)) * 43758.5453);
				float z = frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539) * 4.5)) * 43758.5453);
				return float3(x, y, z);
			}

			GSOutput VertexTransformWorldToClip(float3 pos, float2 uv)
			{
				GSOutput o;
				o.position = TransformObjectToHClip(pos);
				o.uv = uv;
				o.worldPos = pos;
				return o;
			}

			float3 GetTriangleNormal(float3 pos0, float3 pos1, float3 pos2)
			{
				float3 a = pos2 - pos1;
				float3 b = pos0 - pos1;
				return normalize(cross(a, b));
			}

			float3 DisplaceVertex(float3 position, float3 normal)
			{
				float magnitude = 2.0;
				float displacement = ((_Time.y - _StartTime) / 2.0) * magnitude;
				float3 direction = normal * displacement; 
				direction += normalize(rand3(normal)) * displacement * 0.5;
				return position + direction;
			}

			GSOutput ExplodeVertex(VSOutput vertex, float3 normal)
			{
				float3 position = vertex.position;
				float3 newPos = DisplaceVertex(position, normal);
				return VertexTransformWorldToClip(newPos, vertex.uv);
			}

			[maxvertexcount(6)]
			void GSMain(triangle VSOutput input[3], inout TriangleStream<GSOutput> triStream)
			{
				float3 triNormal = GetTriangleNormal(input[0].position, input[1].position, input[2].position);

				triStream.Append(ExplodeVertex(input[0], -triNormal));
				triStream.Append(ExplodeVertex(input[1], -triNormal));
				triStream.Append(ExplodeVertex(input[2], -triNormal));

				triStream.RestartStrip();

				triStream.Append(ExplodeVertex(input[0], triNormal));
				triStream.Append(ExplodeVertex(input[1], triNormal));
				triStream.Append(ExplodeVertex(input[2], triNormal));
			}
		ENDHLSL

		Pass
		{
			Name "GeometryPass"
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

				return _Color * bladeTint + _EmissionColor;
			}
			ENDHLSL
		}
	}
	FallBack "Diffuse"
}

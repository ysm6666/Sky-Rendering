Shader "Custom/RadialBlur"
{
    SubShader
    {
        Tags { "RenderType"="Opaque"  "RenderPipeline"="UniversalPipeline" }
        Cull Off
        ZWrite Off
        ZTest Always
        Pass
        {
           HLSLPROGRAM

                #pragma vertex vertex
                #pragma fragment frag
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
               struct v2f
               {
                   float2 uv:TEXCOORD0;
                   float4 positionCS:SV_POSITION; 
               };

                v2f vertex(uint id:SV_VertexID)
                {
                    v2f output;
                    output.positionCS=GetFullScreenTriangleVertexPosition(id);
                    output.uv=GetFullScreenTriangleTexCoord(id);
                    return output;
                }

                TEXTURE2D(_BlitTexture);
                SAMPLER(sampler_BlitTexture);
                TEXTURE2D(_CloudRT);
                SAMPLER(sampler_CloudRT);
                float _LightThreshold;
                float _LightRadius;
                float4 _sunPositionVS;
                float GetLuminance(float3 color)
                {
                    return dot(color,float3(0.299,0.527,0.114));
                }
                
                float4 frag(v2f input):SV_Target
                {
                    float4 cloudColor=SAMPLE_TEXTURE2D(_CloudRT,sampler_CloudRT,input.uv);
                    float depth=Linear01Depth(SampleSceneDepth(input.uv),_ZBufferParams);
                    float2 blurDir=_sunPositionVS.xy-input.uv;
                    blurDir.y*=_ScreenParams.y/_ScreenParams.x;
                    float  fade=saturate(1-length(blurDir)/_LightRadius)*depth;
                    float luminace=GetLuminance(cloudColor.rgb);
                    luminace*=step(0.99,depth)*step(_LightThreshold,luminace);
                    return float4(fade,fade,fade,luminace);
                }
            
           ENDHLSL 
        }

        Pass
        {
              Blend One One
            //Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM

                #pragma vertex vertex
                #pragma fragment frag
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
               struct v2f
               {
                   float2 uv:TEXCOORD0;
                   float4 positionCS:SV_POSITION; 
               };

                TEXTURE2D(_BlitTexture);
                SAMPLER(sampler_BlitTexture);
                TEXTURE2D(_CloudRT);
                SAMPLER(sampler_CloudRT);
                int _BlurAmount;
                float4 _sunPositionVS;
                float  _LightStrength;

                v2f vertex(uint id:SV_VertexID)
                {
                    v2f output;
                    output.positionCS=GetFullScreenTriangleVertexPosition(id);
                    output.uv=GetFullScreenTriangleTexCoord(id);
                    return output;
                }

                
                
                float4 frag(v2f input):SV_Target
                {
                    float3 col=SAMPLE_TEXTURE2D(_CloudRT,sampler_CloudRT,input.uv).rgb;
                    float2 stepDir=_sunPositionVS-input.uv;
                    stepDir=stepDir/_BlurAmount;
                    float3 sumColor=0;
                    for (int i=0;i<_BlurAmount;i++)
                    {
                        float4 maskVal=SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,saturate(input.uv));
                        sumColor+=maskVal.rgb*maskVal.a;
                        input.uv+=stepDir;
                    }
                    sumColor/=_BlurAmount;
                    sumColor*=_LightStrength*GetMainLight().color;
                    float3 finalCol=col*sumColor;
                    return float4(finalCol,1);
                }
            
            ENDHLSL
        }
    }
}

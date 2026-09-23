Shader "Custom/AtmosphereTest"
{
    Properties
    {
        _EarthRadius("Earth Radius", Float) = 6371000.0
        _AtmosphereHeight("Atmosphere Height", Float) = 80000
        _AtmosphereDensity("Atmosphere Density", Range(0.01, 5.0)) = 1.0
        _ToSunStepNum("To Sun Step Number", Int) = 8
        _SampleCount("Sample Count", Int) = 16
        _DensityScaleHeight("Density Scale Height", Vector) = (7994.0 , 1200.0, 0, 0)
        _ExtinctionR("Extinction Rayleigh", Vector) = (5.8, 13.5, 33.1, 0.0)
        _ExtinctionM("Extinction Mie", Vector) = (2.0, 2.0, 2.0, 0)
        _MieG("Mie G", Float) = 0.76
        _Exposure("Exposure",Float) = 30
        _TerminatorFade("Terminator Fade (m)", Float) = 2000
        _StepPower("Step Distribution Power", Range(1.0, 4.0)) = 2.0
        _GroundColor("Ground Color", Color) = (0.2, 0.2, 0.2, 1)
        [Header(Night Setting)]
        _MoonColor("Moon Scatter Color", Color) = (0.41, 0.5, 0.75, 1)
        _MoonIntensity("Moon Scatter Intensity", Range(0, 1)) = 0.15
        _NightAmbient("Night Ambient (zenith)", Color) = (0.008, 0.014, 0.035, 1)
        _NightHorizonAmbient("Night Ambient (horizon)", Color) = (0.02, 0.03, 0.055, 1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            CBUFFER_START(UnityPerMaterial)
              float _EarthRadius;
              float _AtmosphereHeight;
              float _AtmosphereDensity;
              int _ToSunStepNum;
              int _SampleCount;
              float4 _DensityScaleHeight;
              float4 _ExtinctionM;
              float4 _ExtinctionR;
              float _MieG;
              float _Exposure;
              float _TerminatorFade;
              float _StepPower;
              float4 _GroundColor;
              float4 _MoonColor;
              float _MoonIntensity;
              float4 _NightAmbient;
              float4 _NightHorizonAmbient;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = GetFullScreenTriangleVertexPosition(IN.vertexID);
                OUT.uv = GetFullScreenTriangleTexCoord(IN.vertexID);
                return OUT;
            }

            float Hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            float3 GetSphereIntersection(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
            {
                rayOrigin -= sphereCenter;
                float a = dot(rayDir, rayDir);
                float b = 2.0 * dot(rayOrigin, rayDir);
                float c = dot(rayOrigin, rayOrigin) - sphereRadius * sphereRadius;
                float d = b * b - 4.0 * a * c;
                if (d < 0) return 0;
                float sqrt_d = sqrt(d);
                return float3((-b - sqrt_d) / (2.0 * a), (-b + sqrt_d) / (2.0 * a), 1);
            }

            float2 DensityAtHeight(float h)
            {
                h = max(h, 0.0);
                return exp(-(h.xx / _DensityScaleHeight.xy));
            }

            float2 SegmentDensityIntegral(float h0, float h1, float L)
            {
                float fAbove;
                if (h0 >= 0 && h1 >= 0) fAbove = 1.0;
                else if (h0 < 0 && h1 < 0) fAbove = 0.0;
                else fAbove = max(h0, h1) / (max(h0, h1) - min(h0, h1));

                float hAbove0 = max(h0, 0.0);
                float hAbove1 = max(h1, 0.0);
                float LAbove = L * fAbove;

                float2 k = (hAbove1 - hAbove0).xx / _DensityScaleHeight.xy;
                float2 f;
                f.x = abs(k.x) < 1e-4 ? 1.0 - 0.5 * k.x : (1.0 - exp(-k.x)) / k.x;
                f.y = abs(k.y) < 1e-4 ? 1.0 - 0.5 * k.y : (1.0 - exp(-k.y)) / k.y;
                return LAbove * DensityAtHeight(hAbove0) * f + (L - LAbove);
            }

            float2 lightSampleing(float3 position, float3 lightDir)
            {
                float3 earthCenter = float3(0, -_EarthRadius, 0);
                float3 rayOrigin = position;
                float3 rayDir = normalize(lightDir);

                float3 earthIntersection = GetSphereIntersection(rayOrigin, rayDir, earthCenter, _EarthRadius);
                if (earthIntersection.z > 0 && (earthIntersection.x != earthIntersection.y) && earthIntersection.y > 0)
                {
                    float tPeri = -dot(rayOrigin - earthCenter, rayDir);
                    float periH = length(rayOrigin - earthCenter + rayDir * tPeri) - _EarthRadius;
                    float k = saturate(-periH / _TerminatorFade);
                    float2 tauGrazing = sqrt(2.0 * PI * _EarthRadius * _DensityScaleHeight.xy);
                    return tauGrazing + k * 1.0e6;
                }

                float3 intersectionInfo = GetSphereIntersection(rayOrigin, rayDir, earthCenter, _EarthRadius + _AtmosphereHeight);
                if (intersectionInfo.y < 0) return float2(1e9, 1e9);

                float stepSize = intersectionInfo.y / _ToSunStepNum;
                float2 density = 0;
                for (float s = 0.5; s < _ToSunStepNum; s += 1)
                {
                    float3 stepPosition = rayOrigin + rayDir * stepSize * s;
                    float height = length(stepPosition - earthCenter) - _EarthRadius;
                    density += DensityAtHeight(height) * stepSize;
                }
                return density;
            }

            float2 getPhaseFunc(float VdotL)
            {
                float phaseR = (3.0 / (16.0 * PI)) * (1 + (VdotL * VdotL));
                float g2 = _MieG * _MieG;
                float phaseM = (1.0 / (4.0 * PI)) * ((3.0 * (1.0 - g2)) / (2.0 * (2.0 + g2))) * ((1 + VdotL * VdotL) / (pow((1 + g2 - 2 * _MieG * VdotL), 3.0 / 2.0)));
                return float2(phaseR, phaseM);
            }

            float3 computeAtmosphereScattering(float3 rayOrigin, float3 viewDirWS, float viewDirLength, Light light, float jitter)
            {
                viewDirWS = normalize(viewDirWS);
                float3 lightDir = normalize(light.direction);
                float3 earthCenter = float3(0, -_EarthRadius, 0);

                float3 scatterR = 0;
                float3 scatterM = 0;
                float2 opticalDepthCam = 0;

                float tPrev = 0.0;
                float hPrev = length(rayOrigin - earthCenter) - _EarthRadius;
                float N = (float)_SampleCount;

                // 密度倍增器预乘
                float3 extR = _ExtinctionR.rgb * _AtmosphereDensity * 0.000001f;
                float3 extM = _ExtinctionM.rgb * _AtmosphereDensity * 0.00001f;

                for (float i = 1; i <= N; i += 1)
                {
                    float stepRatio = (viewDirLength < _AtmosphereHeight) ? (i / N) : pow(i / N, _StepPower);
                    float tNext = viewDirLength * stepRatio;
                    float tMid = lerp(tPrev, tNext, jitter);

                    float hMid  = length(rayOrigin + viewDirWS * tMid  - earthCenter) - _EarthRadius;
                    float hNext = length(rayOrigin + viewDirWS * tNext - earthCenter) - _EarthRadius;

                    float2 odMid = opticalDepthCam + SegmentDensityIntegral(hPrev, hMid, tMid - tPrev);
                    float2 odSun = lightSampleing(rayOrigin + viewDirWS * tMid, lightDir);
                    float2 odTotal = odMid + odSun;

                    float3 extinction = exp(-(odTotal.x * extR + odTotal.y * extM));
                    
                    float2 segDensity = SegmentDensityIntegral(hPrev, hNext, tNext - tPrev);
                    scatterR += extinction * segDensity.x;
                    scatterM += extinction * segDensity.y;

                    opticalDepthCam += segDensity;
                    tPrev = tNext;
                    hPrev = hNext;
                }

                float2 phaseRM = getPhaseFunc(dot(lightDir, viewDirWS));
                scatterR *= phaseRM.x * extR;
                scatterM *= phaseRM.y * extM;

                // 纯散射输出；夜间兜底与地面环境光由 frag 统一叠加（避免月亮二次调用时重复）
                return (scatterR + scatterM) * light.color * _Exposure;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float depth = SampleSceneDepth(IN.uv);
                float3 worldPos = ComputeWorldSpacePosition(IN.uv, depth, UNITY_MATRIX_I_VP);
                float3 viewDirWS = normalize(worldPos - _WorldSpaceCameraPos);
                float3 blitColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.uv);

                float3 earthCenter = float3(0, -_EarthRadius, 0);
                float3 atmIntersection = GetSphereIntersection(_WorldSpaceCameraPos, viewDirWS, earthCenter, _AtmosphereHeight + _EarthRadius);
                
                if (atmIntersection.z == 0 || atmIntersection.x == atmIntersection.y) return float4(blitColor, 1);
                
                float viewDirLength = atmIntersection.y; 
                float3 groundIntersection = GetSphereIntersection(_WorldSpaceCameraPos, viewDirWS, earthCenter, _EarthRadius);
                
                float isHitGround = 0;
                
                // 更稳定健壮的检测天空（解决各种平台和Game视图下可能的精度或1/0配置差异）
                bool isSky = false;
                #if UNITY_REVERSED_Z
                    if(depth <= 0.000001) isSky = true;
                #else
                    if(depth >= 0.999999) isSky = true;
                #endif

                if (groundIntersection.z > 0 && isSky) 
                {
                    if (groundIntersection.x > 0)
                    {
                        viewDirLength = groundIntersection.x;
                        float sunElevation = saturate(dot(float3(0,1,0), GetMainLight().direction));
                        float3 sunlit = GetMainLight().color * sunElevation;
                        float3 moonlight = float3(0.02, 0.04, 0.08); // 黑夜星月补光
                        blitColor = _GroundColor.rgb * (sunlit + moonlight) * _Exposure;
                        isHitGround = 1;
                    }
                }

                if (!isSky) 
                {
                    viewDirLength = min(viewDirLength, length(worldPos - _WorldSpaceCameraPos));
                }

                float jitter = Hash12(IN.positionHCS.xy + frac(_Time.y) * 289.0);
                Light light = GetMainLight();
                
                float N = (float)_SampleCount;
                float tPrev = 0.0;
                float hPrev = length(_WorldSpaceCameraPos - earthCenter) - _EarthRadius;
                float2 totalOpticalDepth = 0;

                for (float i = 1; i <= N; i += 1)
                {
                    float stepRatio = (viewDirLength < _AtmosphereHeight) ? (i / N) : pow(i / N, _StepPower);
                    float tNext = viewDirLength * stepRatio;
                    
                    float hNext = length(_WorldSpaceCameraPos + viewDirWS * tNext - earthCenter) - _EarthRadius;
                    totalOpticalDepth += SegmentDensityIntegral(hPrev, hNext, tNext - tPrev);
                    tPrev = tNext;
                    hPrev = hNext;
                }
                
                float3 extR = _ExtinctionR.rgb * _AtmosphereDensity * 0.000001f;
                float3 extM = _ExtinctionM.rgb * _AtmosphereDensity * 0.00001f;
                float3 transmittance = exp(-(totalOpticalDepth.x * extR + totalOpticalDepth.y * extM));

                float3 inscatterColor = computeAtmosphereScattering(_WorldSpaceCameraPos, viewDirWS, viewDirLength, light, jitter);

                // ===== Phase C3 夜间联动 =====
                float3 sunDir = normalize(light.direction);
                float sunBelowHorizon = saturate(-sunDir.y * 5.0);

                // 月亮散射：月亮挂在太阳对立面（与 skybox 一致），冷蓝低强度，仅夜间计算
                if (sunBelowHorizon > 0.001)
                {
                    Light moon = light;
                    moon.direction = -sunDir;
                    moon.color = _MoonColor.rgb * _MoonIntensity;
                    float3 moonScatter = computeAtmosphereScattering(_WorldSpaceCameraPos, viewDirWS, viewDirLength, moon, jitter);
                    inscatterColor += moonScatter * sunBelowHorizon;
                }

                // 深夜色兜底：天顶深蓝 → 地平线微亮的垂直渐变，避免夜空死黑
                float horizonT = pow(1.0 - saturate(viewDirWS.y), 3.0);
                float3 nightAmbient = lerp(_NightAmbient.rgb, _NightHorizonAmbient.rgb, horizonT) * sunBelowHorizon;

                // 地面环境补光（白天原逻辑保留）
                float downwardGradient = smoothstep(0.1, -0.4, viewDirWS.y);
                float3 groundAmbient = float3(0.15, 0.25, 0.4) * downwardGradient * max(0.2, light.color.g) * saturate(dot(float3(0,1,0), sunDir));

                inscatterColor += nightAmbient + groundAmbient;
                
                float3 finalColor = blitColor * transmittance + inscatterColor;
                
                finalColor = 1.0 - exp(-finalColor);
                finalColor += (jitter - 0.5) * (1.0 / 255.0);

                return float4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
Shader "Custom/skybox"
{
    Properties
    {
        [Header(Sun Setting)]
        _SunRadius("Sun Size",Float)=0.1
        _SunIntensityMulti("SunIntensityMulti",Float)=20
        [Header(Moon Setting)]
        _MoonTex("Moon Texture",2D)="white"{}
        [HDR]_MoonColor("Moon Custom Color (HDR)", Color) = (1,1,1,1)
        _MoonRadius("Moon Size",Float)=0.1
        _MoonIntensityMulti("_MoonIntensityMulti",Float)=20
        [Header(Stars Setting)]
        _StarTex("Star Texture",2D)="white"{}
        [HDR]_StarColor("Star Custom Color (HDR)", Color) = (1,1,1,1)
        _StarSkyHeight("StarSkyHeight",Float)=0.5
        _StarIntensityMulti("Star Intensity Multiplier",Float)=1.0
        _TwinkleSpeed("Twinkle Speed", Float) = 5.0
        _TwinkleIntensity("Twinkle Intensity", Range(0, 1)) = 0.8
    }
    SubShader
    {
        Tags { "RenderType"="Background" "PreviewType"="Skybox" "Queue"="Background" "RenderPipeline"="UniversalPipeline"}
        
        Pass
        {
            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #pragma vertex vertex
            #pragma fragment fragment
            
            struct a2v
            {
                float4 positionOS:POSITION;
                float3 uv:TEXCOORD0;
            };

            struct v2f
            {
                float4 positonCS:SV_POSITION;
                float3 uv:TEXCOORD0;
            };

            float _SunRadius;
            float _MoonRadius;
            
            TEXTURE2D(_MoonTex);
            SAMPLER(sampler_MoonTex);
            float4 _MoonTex_ST;

            float4x4 _MainLight_ObjToWorld;

            float _SunIntensityMulti;
            float _MoonIntensityMulti;
            float4 _MoonColor;

            TEXTURE2D(_StarTex);
            SAMPLER(sampler_StarTex);
            float4 _StarTex_ST;
            float _StarSkyHeight;
            float _StarIntensityMulti;
            float4 _StarColor;
            float _TwinkleSpeed;
            float _TwinkleIntensity;
            
            v2f vertex(a2v input)
            {
                v2f output;
                output.positonCS=TransformObjectToHClip(input.positionOS.xyz);
                output.uv=input.uv;
                return output;
            }

            float4 fragment(v2f input):SV_Target
            {
                Light mainlight= GetMainLight();
                float3 lightDir=normalize(mainlight.direction);
                input.uv=normalize(input.uv);
                
                // --- 1. 星空 (添加闪烁动画) ---
                float3 skyColor=0;
                float2 skyUV = input.uv.xz / clamp(input.uv.y, 0.0001, 100) * _StarSkyHeight;
                // 白天平滑隐藏星星，黑夜透出
                float mixFade = smoothstep(0.1, -0.1, lightDir.y);
                
                // --- 忽明忽灭的闪烁算法重构 ---
                // 1. 划分三维网格，同一网格共用噪点。修复星星内单像素高频噪点碎裂问题
                float3 grid = floor(input.uv * 50.0);
                float noise = frac(sin(dot(grid, float3(12.9898, 78.233, 45.164))) * 43758.5453);
                
                // 2. 构造陡峭的闪烁曲线 (忽明忽灭)
                // 打乱不同星区的初始时间与闪烁频率
                float timeMod = _Time.y * _TwinkleSpeed * (0.8 + noise * 0.4) + noise * 100.0;
                float wave = sin(timeMod);
                // 用6次方压暗波谷：维持底亮度，爆发锐利高光 (突闪)
                float blink = pow(wave * 0.5 + 0.5, 6.0);
                // 叠加低频错位波打破周期单调感
                blink *= (sin(timeMod * 0.37) * 0.5 + 0.5) * 1.5 + 0.2;
                blink = saturate(blink);

                float3 starTex = SAMPLE_TEXTURE2D(_StarTex, sampler_StarTex, skyUV * _StarTex_ST.xy + _StarTex_ST.zw).rgb;
                // 去色叠加自定义HDR。利用灰度值保留星图密度，HDR爆发强度
                float starMask = dot(starTex, float3(0.299, 0.587, 0.114));
                
                // 调节插值：0.2暗度 <-> 1.0最高亮度突发
                float twinkleMultiplier = lerp(1.0, blink, _TwinkleIntensity);
                
                skyColor += starMask * _StarColor.rgb * mixFade * twinkleMultiplier * _StarIntensityMulti * step(0, input.uv.y);

                // --- 2. 太阳 ---
                float sun = distance(input.uv, lightDir);
                // 锐利小日盘（真实太阳视直径仅0.5°）+ 微弱外围柔光；大气Mie散射负责大范围光晕
                float sunIntensity = pow(saturate(1.0 - sun/_SunRadius), 3.0) * _SunIntensityMulti;
                sunIntensity += pow(saturate(1.0 - sun/(_SunRadius*8.0)), 6.0) * _SunIntensityMulti * 0.05;
                
                // --- 3. 月亮 (修改计算方式，锁定在太阳的绝对反方向) ---
                // 不再依赖 _MainLight_ObjToWorld，这样月亮到了夜晚（太阳下山面朝下）就一定会挂在天上！
                float3 moonDir = -lightDir; // 反向光照作为月亮方向
                
                // 手动构建月亮的切线空间
                float3 up = abs(moonDir.y) < 0.999 ? float3(0,1,0) : float3(1,0,0);
                float3 right = normalize(cross(up, moonDir));
                up = normalize(cross(moonDir, right));

                float2 moonUV = float2(dot(input.uv, right), dot(input.uv, up)) / _MoonRadius;
                float rSq = dot(moonUV, moonUV);
                
                float3 moonTexColor = 0;
                // 限定只能在月亮面朝我们的一侧且在半径范围内渲染
                if (rSq <= 1.0 && dot(input.uv, moonDir) > 0)
                {
                    float2 localuv = moonUV * 0.5 + 0.5;
                    localuv = localuv * _MoonTex_ST.xy + _MoonTex_ST.zw;
                    moonTexColor = SAMPLE_TEXTURE2D(_MoonTex, sampler_MoonTex, localuv).rgb;
                    
                    // 提纯辉光：保留贴图原有明暗层次（灰度），乘上自定义HDR光色
                    float moonGray = dot(moonTexColor, float3(0.299, 0.587, 0.114));
                    moonTexColor = moonTexColor * (1.0 - _MoonColor.a) + moonGray * _MoonColor.rgb * _MoonColor.a;
                    
                    moonTexColor *= saturate(1.0 - rSq) * _MoonIntensityMulti; // 边缘柔和过渡
                }
                
                float3 finalColor = (float3)(sunIntensity) + moonTexColor + skyColor;
                return float4(finalColor, 1);
            }
            
            ENDHLSL
        }
    }
}
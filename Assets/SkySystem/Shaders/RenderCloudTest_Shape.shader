Shader "RayMarching/RenderCloudTest_Shape"
{
     Properties
    {
        [Toggle(_Sphere_Box_Mode)]_SphereBoxMode("Is Sphere Box Mode",Float)=0
        _FarPlaneMax("FarPlaneMax",Float)=1000000
        [Header(Sphere Box Setting)]
        [Space(10)]
        _EarthRadius("Earth Radius",Float)=6471000
        _CloudHeightMin("Cloud Layer Min Height",Float)=1500
        _CloudHeightMax("Cloud Layer Max Height",Float)=4000
        [Header(AABB Setting)]
        [Space(10)]
        _BoxCenter("Box Center",Vector)=(0,0,0,0)
        _BoxSize("Box Size",Vector)=(100,100,100,0)
        [Space(10)]
        [Header(Step Setting)]
        [Space(10)]
        _BlueTex("Blue Noise (Jitter)",2D)="gray"{}
        _StepSize("Step Size",Range(0.1,80))=40
        _MaxStepCount("Max Step Count",Int)=128
        _MaxTotalStepDis("Max Total Step Distance",Float)=8000
        _HorizonFadeParams("Horizon Fade (x:全隐仰角sin y:全显仰角sin)",Vector)=(0.03,0.18,0,0)
        _AerialParams("Aerial Perspective (x:起始距离 y:密度系数)",Vector)=(6000,0.00008,0,0)
        _NightLightColor("Night Light Color (月光色)",Color)=(0.45,0.55,0.8,1)
        _NightLightIntensity("Night Light Intensity",Range(0,1))=0.3
        [Header(Base Shape Setting)]
        _NoiseTex("3D Noise Tex",3D)="white"{}
        _NoiseScale("Noise Scale",Float)=0.001
        _BaseNoiseWeight("Base Noise Weight (yzw:WorleyFBM三档权重)",Vector)=(0.625,0.25,0.125,0)
        _DensityMuti("_Density Muti",Range(0,2))=1
        [Header(Detail Shape Setting)]
        _DetailNoiseTex("Detail NoiseTex",3D)="white"{}
        _DetailNoiseWeight("Carve Amount (x:塑形抬升强度 y:高频侵蚀量)",Vector)=(0.55,0.35,0,0)
        _DetailNoiseStrength("Detail Noise Strength",Float)=5
        _DetailScale("Detail Scale",Float)=15
        _CurlTex("Curl Noise",2D)="gray"{}
        _CurlStrength("Curl Strength",Range(0,2))=0.3
        [Header(Weather Setting)]
        _WeatherMap("Weather Map",2D)="white"{}
        _WeatherScale("Weather Scale",Float)=1
        _CloudType("Cloud Type (层云0——浓积云1)",Range(0,1))=1
        _CloudTypeVariance("Cloud Type Variance (云型区域差异)",Range(0,1))=0.6
        _CoverageRange("Coverage Range (x:最少云量 y:最多云量)",Vector)=(0.15,0.75,0,0)
        _ShapeCarve("Shape Carve (x:顶部收敛起点 y:收敛强度 z:平底厚度)",Vector)=(0.2,1.0,0.2,0)
        _EdgeSoftness("Edge Softness (边缘柔化混合,0=硬边)",Range(0,1))=0.75
        _BaseShapeScale("Base Shape Scale (塑形噪声相对尺度)",Range(0.05,1))=0.2
        [Header(Flow Setting)]
        _FlowSpeed_Shape_And_Weather("FlowSpeed Shape (x,y) And Weather (z,w)",Vector)=(1,0,1,0)
        [Header(Physically Based Lighting)]
        _Extinction("Extinction (消光系数 m^-1 @density=1)",Range(0.001,0.2))=0.05
        _SunIntensity("Sun Radiance Scale (太阳辐射标定)",Range(1,30))=8
        _SunTint("Sun Tint (云受光色温,0=纯白 1=全阳光色)",Range(0,1))=0.55
        _AmbientWeight("Ambient Weight (天光环境强度)",Range(0,2))=1.0
        _PhaseParams("Phase Params (x:前向g y:后向g z:混合权w)",Vector)=(0.5,-0.5,0.2,0)
        [Header(Silver Lining And Powder Debug)]
        [Space(10)]
        _SilverIntensity("Silver Lining Intensity (银边/火烧云强度,0=关)",Range(0,4))=1.5
        _SilverSpread("Silver Lining Spread (银边亮斑g值,越大越尖锐)",Range(0.5,0.999))=0.88
        _PowderStrength("Powder Strength (糖粉暗边强度倍率,0=关)",Range(0,2))=1.0
        [Header(Ambient Trace Debug)]
        [Space(10)]
        [Toggle(_AmbientTrace_ON)] _AmbientTraceToggle("Enable Ambient Trace (向上追踪背光细节)",Float)=1
        _AmbientTraceDistance("Ambient Trace Distance (向上追踪距离,米)",Range(50,2000))=600
        _AmbientTraceStrength("Ambient Trace Strength (背光细节强度)",Range(0,1))=0.6
    }
    SubShader
    {
        Tags {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
        }
        Cull Off
        ZWrite Off
        ZTest Always
        
        Pass
        {
             Tags
             {
                 "LightMode"="UniversalForward"
             }
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.5
            #pragma shader_feature_local  _Sphere_Box_Mode
            #pragma shader_feature _Division_Rendering
            #pragma shader_feature_local _AmbientTrace_ON
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
           // #define PI 3.14159
            struct Atrributes
            {
                float4 positionOS:POSITION;
                float2 uv:TEXCOORD0;
                 uint vertexID:SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS:SV_POSITION;
                float2 uv:TEXCOORD0;
            };

            
             TEXTURE2D(_BlitTexture);
             SAMPLER(sampler_BlitTexture);
             TEXTURE3D(_NoiseTex);
             SAMPLER(sampler_NoiseTex);
            TEXTURE2D(_WeatherMap);
            SAMPLER(sampler_WeatherMap);
            TEXTURE3D(_DetailNoiseTex);
            SAMPLER(sampler_DetailNoiseTex);
            TEXTURE2D(_CloudBackBuffer);
            SAMPLER(sampler_CloudBackBuffer);
            TEXTURE2D(_BlueTex);
            SAMPLER(sampler_BlueTex);
            float4 _BlueTex_TexelSize;
            TEXTURE2D(_CurlTex);
            SAMPLER(sampler_CurlTex);
          
            
            CBUFFER_START(UnityPerMaterial)
            float4 _BoxCenter;
            float4 _BoxSize;
            float _StepSize;
            int _MaxStepCount;
            float _NoiseScale;
            float4 _PhaseParams;
            float _Extinction;
            float _SunIntensity;
            float  _WeatherScale;
            float _CloudType;
            float _CloudTypeVariance;
            float4 _CoverageRange;
            float4 _ShapeCarve;
            float _EdgeSoftness;
            float _BaseShapeScale;
            float _SunTint;
            float4 _BaseNoiseWeight;
            float4 _DetailNoiseWeight;
            float _DetailScale;
            float _DetailNoiseStrength;
            float _DensityMuti;
            float _EarthRadius;
            float _CloudHeightMin;
            float _CloudHeightMax;
            float _AmbientWeight;
            float _MaxTotalStepDis;
            float4 _FlowSpeed_Shape_And_Weather;
            int _FrameIndex;
            float4x4 _PreVPMatrix;
            float _FarPlaneMax;
            float _CurlStrength;
            float4 _HorizonFadeParams;
            float4 _AerialParams;
            float4 _NightLightColor;
            float _NightLightIntensity;
            float _SilverIntensity;
            float _SilverSpread;
            float _PowderStrength;
            float _AmbientTraceDistance;
            float _AmbientTraceStrength;
            CBUFFER_END

            Varyings Vert(Atrributes input)
            {
                Varyings output;
                // output.positionCS=TransformObjectToHClip(input.positionOS);
                // output.uv=input.uv;
                output.positionCS=GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv=GetFullScreenTriangleTexCoord(input.vertexID);
                return  output;
            }

            float remap(float original_val,float original_min,float original_max,float new_min,float new_max)
            {
                return new_min+(((original_val-original_min)/(original_max-original_min))*(new_max-new_min));
            }

            float Random(float2 uv)
            {
                return frac(sin(dot(uv, float2(12.9898f, 78.233f))) * 43758.5453f);
            }

            // 无饱和的线性重映射，用作"柔和阈值裁剪"：低频云量当高频噪声的下限
            float linear_step(float edge0, float edge1, float x)
            {
                return saturate((x - edge0) / max(edge1 - edge0, 1e-5));
            }

            float sqr(float x) { return x * x; }
            
            float2 RaySphereDst(float3 sphereCenter,float sphereRadius,float3 pos,float3 rayDir)
            {
                float3 centerToPosVector=pos-sphereCenter;
                float b=dot(rayDir,centerToPosVector); //b`=2*dot(rayDir,centerToPosVector)  b=dot(rayDir,centerToPosVector=b`/2
                float c=dot(centerToPosVector,centerToPosVector)-sphereRadius*sphereRadius;
                float delta=b*b-c; //delta=b`*b`-4*a*c 判别公式  b`=2b  a=1 c=co²-r²     
                if (delta<0) //delta<0   射线与球没有交点
                {
                    return float2(0,0);
                }
                float d=sqrt(delta);
                float disToSphere=max(0,-b-d);
                float disInSphere=max(-b+d-disToSphere,0);
                return float2(disToSphere,disInSphere);
            }

            float2 RaySphereCloudLayerDst(float3 sphereCenter,float earthRadius,float heightMin,float heightMax,float3 pos,float3 rayDir)
            {
                float2 cloudDstMin=RaySphereDst(sphereCenter,earthRadius+heightMin,pos,rayDir);
                float2 cloudDstMax=RaySphereDst(sphereCenter,earthRadius+heightMax,pos,rayDir);
                float disToCloudLayer=0;
                float disInCloudLayer=0;
                if (pos.y<=heightMin)
                {
                    float3 startPos=pos+rayDir*cloudDstMin.y;
                    if (startPos.y>=0)  //防止rayDir看向地面
                    {
                        disToCloudLayer=cloudDstMin.y;
                        disInCloudLayer=cloudDstMax.y-cloudDstMin.y;
                    }
                }
                else if (pos.y>heightMin&&pos.y<=heightMax)
                {
                    disToCloudLayer=0;
                    disInCloudLayer=cloudDstMin.y>0?cloudDstMin.x:cloudDstMax.y;
                }
                else
                {
                    disToCloudLayer=cloudDstMax.x;
                    disInCloudLayer=cloudDstMin.x>0?cloudDstMin.x-cloudDstMax.x:cloudDstMax.y;
                }
                return float2(disToCloudLayer,disInCloudLayer);
            }
            
            // 云量场（单次采样）：R=低频天气团(区域云量) G=高频云朵轮廓(烘焙时已与R大型对齐)
            // B=云型。对齐保证"云长在天气团内部"，高频不再游离于低频之外
            float2 SampleCoverageField(float2 posXZ, float2 flowOffset)
            {
                float2 uv = posXZ * _WeatherScale + flowOffset;
                float4 w = SAMPLE_TEXTURE2D_LOD(_WeatherMap, sampler_WeatherMap, uv, 0);

                // 把区域云量压到一个中间区间，避免出现"整屏没云"或"整屏糊死"的极值
                float regionalCov = lerp(_CoverageRange.x, _CoverageRange.y, w.r);
                // 柔和阈值裁剪：regionalCov 越大，阈值越低，越多高频云朵能存活并连成片
                float coverage = linear_step(1.0 - regionalCov, 1.0, w.g);

                float cloudType = saturate(_CloudType + (w.b - 0.5) * _CloudTypeVariance);
                return float2(coverage, cloudType);
            }

            // 三种云型的层内相对顶高（占云层总厚度的比例）。
            // 层云贴着底部铺开，浓积云能顶到层顶 —— 云顶高度差是"垂直形状变化"的来源
            float CloudTypeTopFraction(float cloudType)
            {
                float stratus       = 0.14;
                float stratocumulus = 0.42;
                float cumulus       = 1.0;
                float g1 = lerp(stratus, stratocumulus, saturate(cloudType * 2.0));
                float g2 = lerp(stratocumulus, cumulus, saturate((cloudType - 0.5) * 2.0));
                return lerp(g1, g2, cloudType);
            }
            
            float SampleDensity(float3 pos, float distToCam)
            {
                float2 weather_flow_offset = _Time.y * _WeatherScale * _FlowSpeed_Shape_And_Weather.zw;
                float flowUpSpeed = length(_FlowSpeed_Shape_And_Weather.xy) * 0.7;
                float3 shape_offset = float3(_FlowSpeed_Shape_And_Weather.x, flowUpSpeed, _FlowSpeed_Shape_And_Weather.y) * _Time.y * _NoiseScale;
                
                // ---- 1) 双尺度云量场：疏密聚散 + 区域云型 ----
                float2 cov2 = SampleCoverageField(pos.xz, weather_flow_offset);
                float coverage = cov2.x;
                float cloudTypeLocal = cov2.y;

                // 只在逼近步进极限时才消隐，避免中景被过早削薄
                coverage *= smoothstep(_MaxTotalStepDis, _MaxTotalStepDis * 0.75, distToCam);
                if (coverage < 0.01) return 0;

                float heightPercent = 0;
                #ifndef _Sphere_Box_Mode
                    float3 boundsMin = _BoxCenter.xyz - _BoxSize.xyz * 0.5;
                    heightPercent = (pos.y - boundsMin.y) / _BoxSize.y;
                #else
                    float3 sphereCenter = float3(_WorldSpaceCameraPos.x, -_EarthRadius, _WorldSpaceCameraPos.z);
                    float disToCenter = length(pos - sphereCenter);
                    heightPercent = (disToCenter - _EarthRadius - _CloudHeightMin) / (_CloudHeightMax - _CloudHeightMin);
                #endif
                heightPercent = saturate(heightPercent);

                // ---- 2) 低频塑形 + 覆盖率裁剪（UE复刻文/Nubis 管线）----
                // 低频塑形 Remap(L, -(H·S), 1, 0, 1) ≡ (L+H·S)/(1+H·S)：
                // 高频 Worley FBM 是"抬升"低频 Perlin-Worley 而非从密度里扣——
                // 细节强度与覆盖率解耦，调细节不再连带云量变化。
                // Worley 不取反（保持晶胞结构=亮团块），这是"圆润包络"而非"丝丝缕缕"的关键
                // 基础塑形用独立低频尺度：_NoiseScale 是为"侵蚀细节"调的(数百米级)，
                // 直接拿来做塑形门控会把每朵云打碎成上百米的渣块——
                // 塑形噪声一个起伏要罩住整朵云(公里级)，所以再乘 _BaseShapeScale(≈0.2)
                float3 shapePos = pos * _NoiseScale * _BaseShapeScale + shape_offset;
                // 显式 LOD0：raymarch 动态分支下隐式导数 mip 选择是未定义行为
                float4 shapeNoiseData = SAMPLE_TEXTURE3D_LOD(_NoiseTex, sampler_NoiseTex, shapePos, 0);
                float4 bw = _BaseNoiseWeight;
                bw.yzw /= max(0.0001, dot(bw.yzw, 1));
                float hiFbm = dot(shapeNoiseData.gba, bw.yzw);
                float lift = hiFbm * _DetailNoiseWeight.x;
                float baseShape = saturate((shapeNoiseData.r + lift) / (1.0 + lift));

                // 覆盖率裁剪 cloud_with_coverage = Remap(noise, 1-coverage, 1, 0, 1)（Nubis 原式）
                float density = linear_step(1.0 - coverage, 1.0, baseShape);
                if (density <= 0.0) return 0;

                // ---- 3) 减法雕刻垂直形态 ----
                // 顶高 = 云型基准高 × 云量加成。pow(coverage,1.5) 让垂直发展对云量更"挑剔"——
                // 只有云量足、水平成片的区域才能长高，小碎云自动摊成低平的碎片云(fractus)
                float topFrac = CloudTypeTopFraction(cloudTypeLocal) * lerp(0.10, 1.0, pow(coverage, 1.5));
                float hpNorm = heightPercent / max(topFrac, 0.06); // 归一到该点自己的顶高
                // 顶部收敛：越接近该云型顶高扣得越多，形成圆蓬穹顶
                density -= smoothstep(_ShapeCarve.x, 1.0, hpNorm) * _ShapeCarve.y;
                // 平底：积云特有的锐利水平底面，用乘法才能切得干净
                density *= smoothstep(0.0, _ShapeCarve.z, heightPercent);
                if (density <= 0.0) return 0;

                // ---- 4) 高频 Remap 阈值裁剪侵蚀 ----
                // Remap(density, erosion*strength, 1, 0, 1)：阈值以下整块归零，边界陡峭出团块。
                // 侵蚀噪声同样不取反——UE复刻文实测：取反(1-x)=边缘丝丝缕缕，不取反=圆润包络
                float3 detailPos = pos.yzx * _NoiseScale * _DetailScale + float3(13.73, 7.19, 31.41) + shape_offset * 1.5;
                float2 curl = SAMPLE_TEXTURE2D_LOD(_CurlTex, sampler_CurlTex, pos.xz * _NoiseScale * 3.0, 0).rg * 2.0 - 1.0;
                detailPos.xy += curl * _CurlStrength * (1.0 - heightPercent);
                float3 detailNoise = SAMPLE_TEXTURE3D_LOD(_DetailNoiseTex, sampler_DetailNoiseTex, detailPos, 0).rgb;
                // sqr 聚拢：晶胞亮斑分布太广，直接用会全域碎渣化；
                // 平方后只有晶胞最亮的芯部侵蚀显著——稀疏的圆形"咬口"，圆润包络的来源
                float erosionNoise = sqr(saturate(dot(detailNoise, float3(0.5, 0.3, 0.2))));

                float detail_fade = 0.20 * smoothstep(0.85, 1.0, 1.0 - heightPercent)
                                  - 0.35 * smoothstep(0.05, 0.5, heightPercent) + 0.6;
                float threshold1 = saturate(_DetailNoiseWeight.y * erosionNoise * detail_fade * _DetailNoiseStrength);
                density = saturate((density - threshold1) / max(1.0 - threshold1, 1e-3));

                // 边缘柔化：Remap 裁剪的代价是密度在边界从 0 直接跳上来，边缘生硬。
                // 用 Hermite S 曲线代替幂函数——幂函数会连中段(0.5→0.33)一起压掉，云整体缩水；
                // S 曲线只压低段过渡带(0.2→0.10)，中段不动(0.5→0.5)，芯部微增，质量基本守恒
                float softened = density * density * (3.0 - 2.0 * density);
                density = lerp(density, softened, _EdgeSoftness);

                return density * _DensityMuti;
            }
            
            float4 RestructWorldPos(float2 uv)
            {
                float depth=SampleSceneDepth(uv);
                
                #ifndef  UNITY_UV_STARTS_AT_TOP
                depth=depth*2-1;
                #endif
               
                float2 ndc_uv=uv*2-1;
                float4 ndcPos=float4(ndc_uv,depth,1.0);
                 
                 ndcPos.y*=_ProjectionParams.x;
                
                //viewPortPos=ClipPos/ClipPos.w
                float4 worldPos=mul(unity_MatrixInvVP,ndcPos);
                //worldPos.w=1/ClipPos.w
                worldPos=worldPos/worldPos.w;
                return float4(worldPos.xyz,depth);
                
            }

            float2 RayBoxDst(float3 boundsMin,float3 boundsMax,float3 rayOrigin,float3 invRayDir)
            {
                float3 t0=(boundsMin-rayOrigin)*invRayDir;
                float3 t1=(boundsMax-rayOrigin)*invRayDir;
                float3 tmin=min(t0,t1);
                float3 tmax=max(t0,t1);
                float disIn=max(max(tmin.x,tmin.y),tmin.z);
                float disOut=min(min(tmax.x,tmax.y),tmax.z);
                float disToBox=max(0,disIn);
                float disInBox=max(0,disOut-disToBox);
                return float2(disToBox,disInBox);
            }

            // Phase C4 TOD联动：云的有效光源。白天=太阳；夜晚=月亮(太阳对立面,与skybox/大气一致)
            // 过渡期(太阳贴地平线)亮度下凹，掩盖光源方向翻转的跳变
            void GetCloudLight(out float3 lightDir, out float3 lightCol)
            {
                Light l = GetMainLight();
                float3 sunDir = normalize(l.direction);
                float night = saturate(-sunDir.y * 5.0);
                lightDir = night > 0.5 ? -sunDir : sunDir;
                lightCol = lerp(l.color, _NightLightColor.rgb * _NightLightIntensity, night);
                lightCol *= abs(night * 2.0 - 1.0) * 0.7 + 0.3;
            }

            // 太阳可见度（qiutang98/寒霜式）：从采样点向太阳短程 raymarch，
            // 返回透射率 Π exp(-σt·d)。短程(≤1400m)：太阳光衰减主要发生在云表面几百米内，
            // 全层长程会让 8 步欠采样且整云死黑
            float SunVisibility(float3 pos)
            {
                float3 dirToLight;
                float3 lightColUnused;
                GetCloudLight(dirToLight, lightColUnused);
                float disInBox=0;
                #ifndef _Sphere_Box_Mode
                    float3 boundsMin=_BoxCenter-_BoxSize.xyz*0.5;
                    float3 boundsMax=_BoxCenter+_BoxSize.xyz*0.5;
                    disInBox=RayBoxDst(boundsMin,boundsMax,pos,1/(dirToLight.xyz+1e-5)).y;
               #else
                    float3 sphereCenter=float3(_WorldSpaceCameraPos.x,-_EarthRadius,_WorldSpaceCameraPos.z);
                    disInBox=RaySphereCloudLayerDst(sphereCenter,_EarthRadius,_CloudHeightMin,_CloudHeightMax,pos,dirToLight).y;
                #endif
                disInBox=min(disInBox,1400.0);
                float stepSize=disInBox/8;
                float opticalDepth=0;
                for (int i=0;i<8;i++)
                {
                    pos+=stepSize*dirToLight;
                    opticalDepth+=SampleDensity(pos, 0.0)*_Extinction*stepSize;
                }
                return exp(-opticalDepth);
            }
            

            // Ambient Trace（qiutang98）：从采样点向正上方短程 raymarch，取头顶云体的自遮蔽透射率。
            // 用途：垂直高度插值的环境光(ambUp/ambDown)是整层统一的，没有局部起伏；
            // 云团上方还压着别的云团时，这里应该更暗——这条 trace 就是补这个局部细节，
            // 让背光面（顺光看不到、逆光/侧光才露出来的那部分）层次更丰富，不再是一块死平的灰
            #ifdef _AmbientTrace_ON
            float AmbientTrace(float3 pos)
            {
                float3 upDir=float3(0,1,0);
                float disInBox=0;
                #ifndef _Sphere_Box_Mode
                    float3 boundsMin=_BoxCenter.xyz-_BoxSize.xyz*0.5;
                    float3 boundsMax=_BoxCenter.xyz+_BoxSize.xyz*0.5;
                    disInBox=RayBoxDst(boundsMin,boundsMax,pos,1/(upDir+1e-5)).y;
                #else
                    float3 sphereCenter=float3(_WorldSpaceCameraPos.x,-_EarthRadius,_WorldSpaceCameraPos.z);
                    disInBox=RaySphereCloudLayerDst(sphereCenter,_EarthRadius,_CloudHeightMin,_CloudHeightMax,pos,upDir).y;
                #endif
                disInBox=min(disInBox,_AmbientTraceDistance);
                float stepSize=disInBox/6;
                float opticalDepth=0;
                for (int i=0;i<6;i++)
                {
                    pos+=stepSize*upDir;
                    opticalDepth+=SampleDensity(pos, 0.0)*_Extinction*stepSize;
                }
                return exp(-opticalDepth);
            }
            #endif

            //HG相函数用于模拟米氏散射，计算结果用于描述采样点处光有多少能量进行内散射
            //g为各向异性系数,cosTheta为光源方向与观察方向的夹角余弦值
            float HGPhaseFunc(float cosTheta,float g)
            {
                float g2=g*g;
                float denom=1+g2-2*g*cosTheta;
                return (1-g2)/(4*PI*pow(max(denom,1e-4),1.5));
            }

            // 地平线 Powder Effect 的 qiutang98 改版：
            // depth=深度概率(局部密度越薄越暗，糖粉暗边)，height=垂直概率(云底收光少)，
            // VoL 顺光看时(r→1)削弱垂直压暗——逆光轮廓保暗、顺光云底不至于死黑
            float PowderEffectNew(float depth, float height, float VoL)
            {
                float r = VoL * 0.5 + 0.5;
                r = r * r;
                height = height * (1.0 - r) + r;
                return depth * height;
            }

            // 采样点在云层内的归一化高度
            float GetHeightPercent(float3 pos)
            {
                #ifndef _Sphere_Box_Mode
                    float3 boundsMin=_BoxCenter.xyz-_BoxSize.xyz*0.5;
                    return saturate((pos.y-boundsMin.y)/_BoxSize.y);
                #else
                    float3 sphereCenter=float3(_WorldSpaceCameraPos.x,-_EarthRadius,_WorldSpaceCameraPos.z);
                    return saturate((length(pos-sphereCenter)-_EarthRadius-_CloudHeightMin)/(_CloudHeightMax-_CloudHeightMin));
                #endif
            }

            static  const int OrderMaxtrix[16]={
                0,8,2,10,
                12,4,14,6,
                3,11,1,9,
                15,7,13,5
            };

            bool IsSky(float d)
            {
                bool isSky=false;
                 #ifdef UNITY_REVERSED_Z
                    isSky=d<1e-5;
                #else
                    isSky=d>0.99;
                #endif
                return isSky;
            }
            
            float4 Frag(Varyings input):SV_Target
            {
                #ifdef _Division_Rendering
                    float2 pixelPos=float2(input.positionCS.xy);
                    #if UNITY_UV_STARTS_AT_TOP
                        pixelPos.y=_ScreenParams.y-pixelPos.y;
                    #endif
                    int2 groupPos=int2((uint)pixelPos.x%4, (uint)pixelPos.y%4);
                    int pixelIndex=groupPos.y*4+groupPos.x;
                    pixelIndex=OrderMaxtrix[pixelIndex];
                    if (pixelIndex != _FrameIndex)
                    {
                      
                        float4 currentworldPos_And_Depth=RestructWorldPos(input.uv);
                        
                        float3 cameraPos = _WorldSpaceCameraPos;                    
                        float3 worldRayDir = normalize(currentworldPos_And_Depth.xyz - cameraPos);
                        float disToPixel=distance(currentworldPos_And_Depth.xyz,cameraPos);
                        disToPixel=IsSky(currentworldPos_And_Depth.w)?max(_ProjectionParams.z,_FarPlaneMax):disToPixel;
                        float reprojectionDist =max(_ProjectionParams.z,_FarPlaneMax);
                        #ifndef _Sphere_Box_Mode
                            float3 boundsMin = _BoxCenter.xyz - _BoxSize.xyz * 0.5;
                            float3 boundsMax = _BoxCenter.xyz + _BoxSize.xyz * 0.5;
                            float2 boxInfo = RayBoxDst(boundsMin, boundsMax, cameraPos, 1 / (worldRayDir.xyz + 1e-5));
                            if (boxInfo.y > 0) reprojectionDist = boxInfo.x;
                           
                        #else
                            float3 sphereCenter = float3(cameraPos.x, -_EarthRadius, cameraPos.z);
                            float2 sphereInfo = RaySphereCloudLayerDst(sphereCenter, _EarthRadius, _CloudHeightMin, _CloudHeightMax, cameraPos, worldRayDir);
                            if (sphereInfo.y > 0) reprojectionDist = sphereInfo.x;
                        #endif
                        if (disToPixel<reprojectionDist)
                        {
                            return float4(0,0,0,1);
                        }
                        
                        // 这是云层的真正虚拟物理位置！
                        float3 cloudAnchorPos = cameraPos + worldRayDir * reprojectionDist;
                        float4 preClipPos=mul(_PreVPMatrix,float4(cloudAnchorPos,1));
                        
                        float4 preNdcPos=preClipPos/preClipPos.w;
                        float2 preUV=preNdcPos.xy*0.5+0.5;
                        bool isOutOfBounds = (preUV.x < 0.0 || preUV.x > 1.0 || preUV.y < 0.0 || preUV.y > 1.0);
                        if (!isOutOfBounds)
                        {
                            float4 backBufferCol = SAMPLE_TEXTURE2D(_CloudBackBuffer,sampler_CloudBackBuffer,preUV);
                            return backBufferCol;
                        }
                    }
                
                #endif
                
                float3 cameraPos=_WorldSpaceCameraPos;
                float4 worldPosAndDepth=RestructWorldPos(input.uv);
                float3 worldPos=worldPosAndDepth.xyz;
                float depth=worldPosAndDepth.w;
                bool isSky=IsSky(depth);
                float3 worldRayDir=normalize(worldPos-cameraPos);
                float  distanceToPixel=isSky?max(_ProjectionParams.z,_FarPlaneMax):distance(worldPos,cameraPos);
                float2 disInfo=float2(0,0);
                #ifndef _Sphere_Box_Mode
                    float3 boundsMin=_BoxCenter.xyz-_BoxSize.xyz*0.5;
                    float3 boundsMax=_BoxCenter.xyz+_BoxSize.xyz*0.5;
                    float3 invRayDir=1/(worldRayDir.xyz+1e-5);
                    disInfo=RayBoxDst(boundsMin,boundsMax,cameraPos,invRayDir);
                #else
                    float3 sphereCenter=float3(cameraPos.x,-_EarthRadius,cameraPos.z);
                    disInfo=RaySphereCloudLayerDst(sphereCenter,_EarthRadius,_CloudHeightMin,_CloudHeightMax,cameraPos,worldRayDir);
                #endif
                
                float disToBox=disInfo.x;
                float disInBox=disInfo.y;
                
                float3 lightDir;
                float3 cloudLightCol;
                GetCloudLight(lightDir, cloudLightCol);
                float cosTheta = dot(worldRayDir, lightDir);
                
                if (disInBox<=0||disToBox>=distanceToPixel)
                {
                    return float4(0,0,0,1);
                }
                float3 currentPos=cameraPos+worldRayDir*disToBox;

                // 蓝噪声抖动替换白噪声：能量分布均匀，消除步进 banding 与颗粒碎感
                float offset = SAMPLE_TEXTURE2D(_BlueTex, sampler_BlueTex, input.positionCS.xy * _BlueTex_TexelSize.xy).r;
                
                float totalStepDis=min(disInBox,distanceToPixel-disToBox);
                totalStepDis=min(totalStepDis,_MaxTotalStepDis);//防止步长太大，在计算光照时，因为步长太大而使得lightenerge爆炸
                _StepSize=max(_StepSize,totalStepDis/float(_MaxStepCount));
                currentPos += worldRayDir *_StepSize* offset;
                
                float trans_strength=1;
                float travledDis=_StepSize*offset;

                // 背景大气散射色（前移到 march 之前，兼作天光环境源）：
                // 水平三点取最暗剔除日盘亮斑；侧点须过"是天空"深度检验防止采到前景物体
                float3 bgColor;
                {
                    float3 s0=SAMPLE_TEXTURE2D_LOD(_BlitTexture,sampler_BlitTexture,input.uv,0).rgb;
                    float3 lumW=float3(0.299,0.587,0.114);
                    bgColor=s0;
                    float bl=dot(s0,lumW);
                    float2 uv1=saturate(input.uv+float2( 0.1,0));
                    float2 uv2=saturate(input.uv+float2(-0.1,0));
                    if (IsSky(RestructWorldPos(uv1).w))
                    {
                        float3 s1=SAMPLE_TEXTURE2D_LOD(_BlitTexture,sampler_BlitTexture,uv1,0).rgb;
                        float l1=dot(s1,lumW); if(l1<bl){bl=l1;bgColor=s1;}
                    }
                    if (IsSky(RestructWorldPos(uv2).w))
                    {
                        float3 s2=SAMPLE_TEXTURE2D_LOD(_BlitTexture,sampler_BlitTexture,uv2,0).rgb;
                        float l2=dot(s2,lumW); if(l2<bl){bl=l2;bgColor=s2;}
                    }
                    // 压掉背景中的 HDR 极值（太阳圆盘），否则日盘会被"画"到云上
                    float bgLum=dot(bgColor,lumW);
                    bgColor*=saturate(2.5/max(bgLum,2.5));
                }

                // 环境光垂直梯度：天光环境源改用背景大气散射色而不是 SampleSH——
                // 全屏 blit pass 没有物体级 SH 绑定，SampleSH 在这里≈0，环境项从未真正生效，
                // 阴影面只能靠暖色日光散射染色 → 这就是云底永远发棕的最终根因。
                // 大气散射色与 TOD 自洽：正午蓝、黄昏橙，云的阴影色随天色走
                float3 ambUp=bgColor;
                float3 ambDown=bgColor*0.55;
                // 云受光色温控制：TOD 的太阳色正午仍偏暖，往亮度等价白回拉一部分
                float3 cloudSunCol=lerp(dot(cloudLightCol,float3(0.299,0.587,0.114)).xxx,cloudLightCol,_SunTint);

                //动态步长
                float originalStep=_StepSize;
                float bigStep=_StepSize*4;
                int zeroCounter=0;
                float isSearching=true;
                _StepSize=bigStep;

                // 物理量（qiutang98/寒霜）：σs=密度×_Extinction(米^-1)，σa=0(云反照率≈1) → σe=σs。
                // scattering 是沿视线已积分的辐射度，transmittance 是视线透射率——
                // 最终画面 = transmittance×背景 + scattering，不再有任何风格化颜色插值
                float3 scattering=0;
                float transmittance=1;
                float3 rayHitPos=0;
                float rayHitWeight=0;

                [loop]
                for (int i=0;i<_MaxStepCount;i++)
                {
                    if (travledDis>=totalStepDis)
                    {
                        break;
                    }
                    if (isSearching)
                    {
                        float density=SampleDensity(currentPos, travledDis);
                        if (density>0.001)
                        {
                            travledDis-=_StepSize;
                            currentPos-=worldRayDir*_StepSize;
                            isSearching=false;
                            _StepSize=originalStep;
                        }
                    }
                    else
                    {
                        float density=SampleDensity(currentPos, travledDis);
                        if (density>0.001)
                        {
                            float sigmaS=density*_Extinction;
                            float sigmaE=max(sigmaS,1e-7);
                            float stepTrans=exp(-sigmaE*_StepSize);

                            float sunVis=SunVisibility(currentPos);
                            float hp=GetHeightPercent(currentPos);

                            // Powder（qiutang98 改版 HZD）：深度概率(薄处糖粉暗边)×垂直概率(云底收光少)，
                            // VoL 顺光时削弱垂直压暗——逆光轮廓保暗、顺光云底不死黑
                            float depthProb=0.05+pow(saturate(density*10.0),clamp(remap(hp,0.3,0.85,0.5,2.0),0.5,2.0));
                            float vertProb=pow(saturate(remap(hp,0.07,0.22,0.1,1.0)),0.8);
                            float powder=PowderEffectNew(depthProb,vertProb,cosTheta);
                            // _PowderStrength=0 时完全跳过糖粉压暗，方便调试对比
                            powder=lerp(1.0,powder,_PowderStrength);

                            // 多重散射近似（寒霜）：太阳可见度按 0.5^o 折半衰减、相位偏心率同步收缩
                            float msPhase=0;
                            float contrib=1;
                            float visPow=1;
                            float ecc=1;
                            [unroll]
                            for (int o=0;o<3;o++)
                            {
                                float ph=lerp(HGPhaseFunc(cosTheta,_PhaseParams.x*ecc),
                                              HGPhaseFunc(cosTheta,_PhaseParams.y*ecc),_PhaseParams.z);
                                msPhase+=contrib*ph*pow(sunVis,visPow);
                                contrib*=0.5;
                                visPow*=0.5;
                                ecc*=0.5;
                            }
                            // 银边/火烧云：多重散射近似里 g 只有 0.5、混合权重只占 80%，相位峰太钝，
                            // 逆光时出不来强烈的亮环。这里单独叠一个尖锐前向瓣(_SilverSpread≈0.85~0.95)，
                            // 强度可调、可关，不影响上面物理多重散射的能量分布
                            msPhase+=_SilverIntensity*HGPhaseFunc(cosTheta,_SilverSpread)*sunVis;
                            // 直射：太阳辐射 × 多重散射相位 × Powder。
                            // _SunIntensity 是量纲标定：Unity 灯光颜色是 LDR 显示值(~1.4)，
                            // 真实太阳辐照/天光比 ~10:1，不补这个比例云只能靠环境光照亮 → 灰剪影
                            float3 S=cloudSunCol*_SunIntensity*msPhase*powder;
                            // 环境光只叠在第一次散射上（寒霜：多次叠加会抹平体积细节），各向同性不乘相位
                            #ifdef _AmbientTrace_ON
                                float ambVis=AmbientTrace(currentPos);
                                float3 ambUpLocal=lerp(ambUp,ambUp*ambVis,_AmbientTraceStrength);
                            #else
                                float3 ambUpLocal=ambUp;
                            #endif
                            S+=lerp(ambDown,ambUpLocal,hp)*lerp(0.55,1.0,hp)*_AmbientWeight;

                            // 寒霜能量守恒散射积分：Sint = S·σs·(1-e^{-σe·dt})/σe，再乘视线透射率
                            scattering+=transmittance*(S*sigmaS/sigmaE)*(1.0-stepTrans);

                            // 透射率加权命中点（qiutang98）：给空气透视一个真实的云体位置
                            rayHitPos+=currentPos*transmittance;
                            rayHitWeight+=transmittance;
                            transmittance*=stepTrans;
                        }
                        else
                        {
                            zeroCounter++;
                            if (zeroCounter>8)
                            {
                                isSearching=true;
                                _StepSize=bigStep;
                            }
                        }
                    }
                    if (transmittance<0.01)
                    {
                        break;
                    }
                    currentPos+=worldRayDir*_StepSize;
                    travledDis+=_StepSize;
                }
                // 地平线渐隐(空气透视)：低仰角视线的云渐隐进大气
                float horizonFade=smoothstep(_HorizonFadeParams.x,_HorizonFadeParams.y,worldRayDir.y);
                scattering*=horizonFade;
                transmittance=lerp(1.0,transmittance,horizonFade);
                // 空气透视距离：用透射率加权命中点，而不是云层入点
                float hitDist=rayHitWeight>1e-4?length(rayHitPos/rayHitWeight-cameraPos):disToBox;
                float aerial=1.0-exp(-max(hitDist-_AerialParams.x,0.0)*_AerialParams.y);
                aerial=max(aerial,1.0-horizonFade);
                // 厚云透光率地板归零：残留 1% 透光遇上 HDR 太阳圆盘仍会透穿可见
                trans_strength=saturate((transmittance-0.015)/0.985);
                // 合成 pass 是 Blend OneMinusSrcAlpha SrcAlpha：screen = color·(1-trans) + bg·trans。
                // scattering 是已积分辐射度（自带能量权重），反预乘还原出 color
                float3 cloudColor=scattering/max(1.0-trans_strength,1e-4);
                cloudColor=lerp(cloudColor,bgColor,saturate(aerial));
                return float4(cloudColor,trans_strength);
            }
            
            ENDHLSL
        }

        Pass
        {
            Blend OneMinusSrcAlpha SrcAlpha
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _Division_Rendering
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS:POSITION;
                float2 uv:TEXCOORD0;
                uint vertexID:SV_VertexID;
            };

            struct Varyings
            {
                float2 uv:TEXCOORD0;
                float4 positionCS:SV_POSITION;
            };
            TEXTURE2D(_BlitTexture);
            SAMPLER(sampler_BlitTexture);
            float4 _BlitTexture_TexelSize;
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS=GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv=GetFullScreenTriangleTexCoord(input.vertexID);
                return output;
            }

            float4 frag(Varyings input):SV_Target
            {
                float4 col = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv);
                
                #ifdef _Division_Rendering
                    // 改善 16 帧插值导致的风吹移动时云边和云底的锯齿网格
                    float2 texel = _BlitTexture_TexelSize.xy;
                    float4 s1 = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv + float2( texel.x,  0));
                    float4 s2 = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv + float2(-texel.x,  0));
                    float4 s3 = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv + float2( 0,  texel.y));
                    float4 s4 = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv + float2( 0, -texel.y));
                    
                    float4 s5 = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv + float2( texel.x,  texel.y));
                    float4 s6 = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv + float2(-texel.x, -texel.y));
                    float4 s7 = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv + float2(-texel.x,  texel.y));
                    float4 s8 = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,input.uv + float2( texel.x, -texel.y));

                    col = col * 0.25 + (s1 + s2 + s3 + s4) * 0.125 + (s5 + s6 + s7 + s8) * 0.0625;
                #endif
                
                return col;
            }
            
            ENDHLSL
        }
    }
}

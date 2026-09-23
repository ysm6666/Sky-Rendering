# 大气散射渲染技术文档：从公式到 Shader 代码的逐一映射

这份文档以**“物理数学公式”为主导**，将繁杂的大循环拆解。我们会先给出一个渲染步骤的数学公式，然后紧跟着展示我们的 `AtmosphereTest.shader` 是如何用代码翻译这段公式的。

---

## 核心总公式：单次散射模型 (Single Scattering)

当我们看向天空的任意一点（方向为 $\vec{v}$ ），最终落入我们眼睛的总光强 $I$ ，是视线路径上无数个空气粒子“散射出的光”的积分累加。
它的终极物理公式如下：

$$
I = \int_{A}^{P} \Big( I_{sun} \cdot \beta_{scat}(h) \cdot Phase(\theta) \cdot T(A, C) \cdot T(C, L) \Big) ds
$$

括号里的 5 个乘子，各自对应本文的一个模块，后文按同一次序逐个拆解：

| 乘子 | 物理含义 | 对应模块 | Shader 实现 |
|---|---|---|---|
| $I_{sun}$ | 太阳入射光强/颜色 | —（由 `GetMainLight()` 提供） | `light.color` |
| $\beta_{scat}(h)$ | 散射系数 × 高度密度 | 模块 1 | `DensityAtHeight()` + `_ExtinctionR/_ExtinctionM` |
| $Phase(\theta)$ | 散射相位函数 | 模块 3 | `getPhaseFunc()` |
| $T(A, C)$ | 采样点到相机的透射率 | 模块 2.2 | `SegmentDensityIntegral()` |
| $T(C, L)$ | 采样点到太阳的透射率 | 模块 2.1 / 2.3 | `lightSampleing()`（含 Terminator Fade） |


在代码中，其实就是在求这个巨大的积分。为了把它算出来，我们必须把括号里相乘的这 **5 个模块** 逐一写成函数，最后在主循环（Ray Marching）里组装。

下面，我们按模块逐个拆解公式与代码。

---

## 模块 1：大气密度分布公式 ρ(h)

**【物理公式】**
大气的浓度随着海拔高度 $h$ 是呈指数级衰减的。公式表示为：

$$
\rho(h) = \exp \left( - \frac{h}{H_0} \right)
$$


*   $H_0$ 是基准高度（标高）。在我们的模型里分为瑞利（Rayleigh）高度和米氏（Mie）高度。

**【代码实现】**
这只是个非常简单的纯函数映射。把海拔高度翻译成 0~1 的浓度系数。
```hlsl
// _DensityScaleHeight.xy 就等于基准高度 H_0（瑞利 7994, 米氏 1200）
float2 DensityAtHeight(float h)
{
    h = max(h, 0.0); // 保护机制：地表以下密度不再变浓，保持 1.0 (防止出现数值爆炸)
    return exp(-(h.xx / _DensityScaleHeight.xy)); // 严格对应 exp(-h / H_0)
}
```

---

## 模块 2：透射率 T 与光学厚度 ∫ρ(h)ds

**【物理公式】**
透射率 $T(A, B)$ 表示光从 A 走到 B 的路上，没被粒子散射掉、**成功存活下来的比例**。
它的推导公式为：

$$
T(A, B) = \exp \left( - \beta_{ext} \int_{A}^{B} \rho(h) ds \right)
$$


*   $\beta_{ext}$：消光系数（不同波长损耗不同）。
*   $\int_{A}^{B} \rho(h) ds$：这就是著名概念——**光学厚度 (Optical Depth)**，即整段路径上所有密度的累加总和。

这里分为两段需要计算透射率的光路：**太阳到采样点 $T(C, L)$**，以及 **采样点到相机 $T(A, C)$**。

### 2.1 太阳方向的光学厚度（暴力积分法求 T(C,L)）

**【代码实现】**
太阳方向的光路较长，我们使用类似黎曼和的长方形累加来强制积分：$\sum \rho(h_{step}) \cdot \Delta s$
```hlsl
float2 lightSampleing(float3 position, float3 lightDir)
{
    // ... 前置处理射线与地球的交点交距 ...
    float stepSize = intersectionInfo.y / _ToSunStepNum; // 划分 Δs (步长)
    float2 density = 0; // 用来累加积分
    
    // 强制循环累加求解 ∫ρ(h)ds
    for (float s = 0.5; s < _ToSunStepNum; s += 1)
    {
        float3 stepPosition = rayOrigin + rayDir * stepSize * s;
        float height = length(stepPosition - earthCenter) - _EarthRadius;
        density += DensityAtHeight(height) * stepSize; // 累加 ρ(h) * Δs
    }
    return density; // 注意：这里算完的仅仅是“光学厚度”，还不含 exp(-x)，等待外部整合
}
```

### 2.2 视线方向的光学厚度：解析积分的魔法（计算 T(A,C)）

**【代码实现】**
在普通的教程中，求线段 $L$ 上的积累浓度，通常是取中点：`density = DensityAtHeight(h_mid) * L`。
但当视线跨度极大、或是贴近地平线时，高度变化极其剧烈。用“中心一点”代表整段会导致严重的阶梯形色带（Bandings）。
为此，我们在 `SegmentDensityIntegral` 里，对这段微积分 $\int_0^L \rho(h) ds$ 求出了**绝对精确的数学解析解**。

这里还包含了极为细致的防止“穿模地下”报错机制：
```hlsl
// 这段代码的作用与上一个 loop 严格等价，都是算 ∫ρ(h)ds。只是它是靠微积分公式直接出结果！
float2 SegmentDensityIntegral(float h0, float h1, float L)
{
    // ... 代码详见 2.2 小节原文 (已省略防干扰)
}
```

### 2.3 太阳光被地球挡住时的黑线消除魔法 (`Terminator Fade`)
这正是你的提问所在。我们看向太阳时，会调用 `lightSampleing`，其中包含了这样一个特殊的分支判断：
```hlsl
float3 earthIntersection = GetSphereIntersection(rayOrigin, rayDir, earthCenter, _EarthRadius);
// 如果光线射向太阳的路上，先碰到了地球 (深度z>0且相交了)，说明太阳被地球挡住了！
if (earthIntersection.z > 0 && (earthIntersection.x != earthIntersection.y) && earthIntersection.y > 0)
{
    // 晨昏线平滑过渡
    float tPeri = -dot(rayOrigin - earthCenter, rayDir);
    float periH = length(rayOrigin - earthCenter + rayDir * tPeri) - _EarthRadius;
    float k = saturate(-periH / _TerminatorFade);
    float2 tauGrazing = sqrt(2.0 * PI * _EarthRadius * _DensityScaleHeight.xy);
    return tauGrazing + k * 1.0e6;
}
```

**它的原理：**
在绝大多数粗糙的大气教程里，一旦 `earthIntersection` 说碰到了地球，那就代表太阳光被死死挡住了，代码会直接简单粗暴地 `return 1e9` (返回极大光学厚度，让透射率为0)。
**但这样有个大问题！** 物理上的光是会绕着地球发生折射（也就是多重散射的微光），并非一碰地表就瞬间切断。如果强行截断，日落后天空上会出现一条用直尺画出来一样的**绝对锋利黑线 (Terminator Line)**，非常违和。

你发来的这段代码，就是为了填补因为没做多重散射而导致的阴影破绽，人为地把太阳落山“死黑的一瞬间”，拉长成一个柔和的渐变：
1. **找最近点**：`tPeri`。一条射线从眼睛发出，经过地球旁边。它离地球球心最近的那个点，在数学上就是射线方向向量与“球心到眼睛”向量的点积求投影。这就是 `-dot(...)`。
2. **算陷地深度**：`periH`。算出那个最近点的位置，然后拿它的长度减去 _EarthRadius。既然射向太阳会撞倒地球，那么这个最近点一定是在地下的，所以 `periH` 会算出一个“负数的高度值”。
3. **把深度转系数**：`k`。把陷入地下的深度，除以我们在材质面板里暴露的褪色参数 `_TerminatorFade`（一般是 2~5 公里）。如果太阳刚好落山一点点，刚陷入几百米，算出来 `k` 很小；如果落下极深，`saturate` 一卡，`k` 满值为 `1`。
4. **边缘极限值**：`tauGrazing` 这是著名的“Chapman 函数近似”。它物理上算出的就是在**贴着地平线擦边飞过时，光学厚度的物理学恒定最大值**。
5. **装配输出**：如果刚落山，你返回的就是擦边极限厚度（光透过来极弱，但能保持晚霞的最后余晖！）；如果太阳落深了，`k` 变为 1，加上天文级的惩罚大数字 `1.0e6`，光就彻底没啦（天彻底黑透）。一条完美的无缝日落光影曲线就这么被伪造出来了！

---

## 模块 3：相位函数 Phase(θ)

**【物理公式】**
相位函数决定了太阳光射到粒子上后，是往你的眼睛弹射，还是往其它方向弹射。

*   **瑞利相位 (Rayleigh)**：对分子（天空颜色），前向和后向散射相同。

    $$
    P_R(\theta) = \frac{3}{16\pi} (1 + \cos^2\theta)
    $$

*   **米氏相位 (Mie)**：对大颗粒（白雾/光晕），强烈偏向前向（顺着光走）。

    $$
    P_M(\theta) = \frac{1}{4\pi} \frac{3(1 - g^2)}{2(2 + g^2)} \frac{1 + \cos^2\theta}{(1 + g^2 - 2g\cos\theta)^{3/2}}
    $$



**【代码实现】**
这里的 `VdotL` 就是光线与点到相机方向的点乘，即 $\cos\theta$。公式百分之百对应：
```hlsl
float2 getPhaseFunc(float VdotL)
{
    // 完完全全就是对照着写的数学公式
    float phaseR = (3.0 / (16.0 * PI)) * (1 + (VdotL * VdotL));
    
    float g2 = _MieG * _MieG; // g 控制着米氏前向散射的聚集度 (也就是光晕大小)
    float phaseM = (1.0 / (4.0 * PI)) * ((3.0 * (1.0 - g2)) / (2.0 * (2.0 + g2))) * ((1 + VdotL * VdotL) / (pow((1 + g2 - 2 * _MieG * VdotL), 3.0 / 2.0)));
    
    return float2(phaseR, phaseM); // 分别返回瑞利和米氏的方向折射系数
}
```

---

## 模块 4：总积分装配 (Main Ray Marching Loop)

现在我们有了所有的函数零件，回到我们的**核心总公式**算总积分（把上式的 5 个乘子和 $\Delta s$ 塞进求和）：

$$
\Sigma \Big( I_{sun} \cdot \beta_{scat}(h) \cdot Phase(\theta) \cdot \exp\!\left(- \beta_{ext} \int_A^C \rho\,ds\right) \cdot \exp\!\left(-\beta_{ext} \int_C^L \rho\,ds\right) \Big) \Delta s
$$


**【代码实现】** 这就是 `computeAtmosphereScattering` 函数中计算的主干。
为了让你看懂这份最硬核的组装代码，我们将循环里每个变量都做了超详细拆解标注：

```hlsl
// ================== 循环前的准备工作 ==================
// 1. 光学厚度（浓度积分）的全局累加器
// 代表：从相机出发，到“当前步进点”为止，身后已经积累了多厚的空气“厚度”（不是颜色，单纯算遮挡的厚度）。
float2 opticalDepthCam = 0; 
// 这里 float2 的 x 存瑞利的浓度，y 存米氏的浓度。后面所有的 float2 都是这个规则。

// 2. 最终色彩发出强度的全局累加器
float3 scatterR = 0; // 累计接收到的瑞利（Rayleigh）光强（决定天蓝/夕阳红）
float3 scatterM = 0; // 累计接收到的米氏（Mie）光强（决定白雾/光晕）

// 3. 记录“上一个点”的位置信息，用于跟“当前点”连成一条线段
float tPrev = 0.0; // 上一迭代的线段端点距离
float hPrev = length(rayOrigin - earthCenter) - _EarthRadius; // 上一迭代端点的海拔高度 h

// 4. 消光系数预乘：β_ext × 大气总浓度倍增器 _AtmosphereDensity（面板可调"空气有多稠"）
// 0.000001 / 0.00001 是单位换算（材质面板数值 → 每米物理量级）
float3 extR = _ExtinctionR.rgb * _AtmosphereDensity * 0.000001f;
float3 extM = _ExtinctionM.rgb * _AtmosphereDensity * 0.00001f;

// ================== 大气视线步进主循环 ==================
for (float i = 1; i <= N; i += 1)
{
    // 【获取当前探测线段的下个端点位置 (tNext) 和 海拔高度 (hNext)】
    // viewDirLength: 视线能穿过大气层的总最远距离。
    // 步长分布分两种情况：视线很短（撞到近处物体/地面, < _AtmosphereHeight）时均匀切段即可；
    // 视线贯穿大气层时，用幂律分布 pow(i/N, _StepPower) 让近处线段密、远处线段长，省性能。
    float stepRatio = (viewDirLength < _AtmosphereHeight) ? (i / N) : pow(i / N, _StepPower);
    float tNext = viewDirLength * stepRatio;
    float hNext = length(rayOrigin + viewDirWS * tNext - earthCenter) - _EarthRadius;
    
    // 【防止同心圆条纹噪点的特殊 Trick：抖动 (Jitter)】
    // 我们不是在线段的正中间采样，而是根据噪点 jitter 随机在 tPrev 和 tNext 之间挑一个点 tMid 作为采样中心点。
    float tMid = lerp(tPrev, tNext, jitter);
    float hMid = length(rayOrigin + viewDirWS * tMid - earthCenter) - _EarthRadius;

    // ----- 积木 1：计算相机望向“取样点 (Mid)”的大气遮挡厚度 -----
    // opticalDepthCam 是之前所有步子存下来的累加浓度。
    // 这里算出 T(A, C) 的厚度。
    float2 odMid = opticalDepthCam + SegmentDensityIntegral(hPrev, hMid, tMid - tPrev);
    
    // ----- 积木 2：计算从“取样点 (Mid)”往上抬头看太阳的大气遮挡厚度 -----
    // 算出从这到太阳要穿过多少浓度的空气，即 T(C, L) 的厚度。
    float2 odSun = lightSampleing(rayOrigin + viewDirWS * tMid, lightDir);
    
    // ----- 积木 3：组装 透射率公式：总遮挡 = 往回看的厚度 + 往上看太阳的厚度 -----
    float2 odTotal = odMid + odSun;
    
    // 核心物理计算！用指数函数转化为真实的“存活比例”
    // 公式是 T = exp(-厚度 * Extinction_β)。算出了这束光折腾完还剩下多少百分比的能量！
    float3 extinction = exp(-(odTotal.x * extR + odTotal.y * extM));
                            
    // ----- 积木 4：真正发光！-----
    // 这团空气自己本身产生了多少“发光浓度粒子”？
    float2 segDensity = SegmentDensityIntegral(hPrev, hNext, tNext - tPrev);
    
    // 把它积分进你的眼睛里：
    // （当前段光强贡献 += 活下来的光能量比例 (extinction) * 这一段存在的发光粒子数量 (segDensity)）
    scatterR += extinction * segDensity.x; 
    scatterM += extinction * segDensity.y;

    // ----- 步进清理：准备好下一轮循环 -----
    opticalDepthCam += segDensity; // 累积厚度推进
    tPrev = tNext; // 上一个点 = 本次下个点
    hPrev = hNext;
}
// ================== 循环结束 ==================

// 积木 5：补充没乘完的公因式乘数。
// 根据数学乘法分配律，我们可以大胆地把不变的 相位偏转 Phase(θ) 和 颜色基底系数 β(Scattering) 提到 for 循环所有加法完成了之后再一起乘上去！省了显卡大量的计算时间！
float2 phaseRM = getPhaseFunc(dot(lightDir, viewDirWS));
scatterR *= phaseRM.x * extR;
scatterM *= phaseRM.y * extM;

// 积木 6：纯散射输出
// 再乘上 太阳传进来的原始颜色光强 和 曝光度。
// 注意：本函数只输出"纯散射"，夜间兜底色 / 地面环境光统一在 frag 里叠加——
// 因为夜里月亮会以 -sunDir 为方向【第二次】调用本函数，环境项若写在这里会被叠两遍。
return (scatterR + scatterM) * light.color * _Exposure;
```

---

## 模块 5：frag 最终组装（昼夜联动）

`computeAtmosphereScattering` 之外，`frag` 还做了这些事（与代码一一对应）：

1. **视线透射率**：对整条视线再积一次光学厚度，得 `transmittance`，用于压暗背景：
   `finalColor = blitColor * transmittance + inscatterColor`。
2. **月亮散射（夜间）**：太阳落山后（`sunBelowHorizon > 0`），把 `-sunDir` 当作月亮方向、
   `_MoonColor × _MoonIntensity` 当作月亮辐射，**第二次调用** `computeAtmosphereScattering`
   叠加冷蓝色的夜天光。
3. **深夜色兜底**：`_NightAmbient`(天顶) → `_NightHorizonAmbient`(地平线) 的垂直渐变，
   防止夜空死黑。
4. **地面环境补光**：向下看时叠加 `float3(0.15,0.25,0.4)` 的蓝灰渐变，白天有效。
5. **色调映射与抖动**：`finalColor = 1 - exp(-finalColor)` 压 HDR，再加 1/255 的抖动防色带。

---

## 附加推导区

### [附录 1] 射线与球体相交是怎么算的？
代码里的 `GetSphereIntersection` 解出了视线在大气里的总路程（也就是求了积分上限 $P$ 的坐标）。
**推导过程：**
1. **直线方程**：相机（坐标 $o$ ）打出光线方向 $d$ ，在距离 $t$ 时的坐标就是 $P = o + t \cdot d$。
2. **球体方程**：设地球球心为 $C$，球半径 $R$。圆上的点满足：$(P - C) \cdot (P - C) = R^2$。
3. **联立代入**：把直线的点 $P$ 塞进球的方程，求交点距离 $t$：
   $((o - C) + td) \cdot ((o - C) + td) = R^2$
4. **化为一元二次方程 $At^2 + Bt + C = 0$**：
   *   $A = d \cdot d$ （方向向量乘自己为 1）
   *   $B = 2.0 * ((o-C) \cdot d)$
   *   $C = (o-C) \cdot (o-C) - R^2$
5. 代码中的求根公式 $t = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$ 直接返回这两个解。

### [附录 2] 微积分解析解：SegmentDensityIntegral 为什么是 `(1-e^-k)/k`？

在普通的方法中，大家算一段距离的光学厚度用的是**矩形面积**：`浓度 = 终点浓度 * 距离`。
但这在面对极度陡峭弯曲的“指数级衰减曲线”上，误差极大。我们可以直接用**牛顿-莱布尼茨公式**解出原曲线面积！

**物理目标**：求一小段端点极短的线段 $L$ 上的光积累绝对浓度

$$
Total = \int_0^L \exp\left( - \frac{h(s)}{H} \right) ds
$$

**步骤 1：假定该微小线段内，高度是线性变化的**

假设在这个线段 $L$ 内，我们所处的海拔高度是从 $h_0$ 匀速直线上升/下降至 $h_1$ 的。
那么在这个线段上，你往前走了距离 $s$ 时，你当前的绝对高度方程是：

$$
h(s) = h_0 + \frac{h_1 - h_0}{L} \cdot s
$$

**步骤 2：代入指数物理模型中**

我们将 $h(s)$ 这个变量代入积分项：

$$
\int_0^L \exp\left( - \frac{h_0 + \frac{h_1 - h_0}{L} s}{H} \right) ds
$$

利用高中指数拆分法则 $\exp(A+B) = \exp(A) \cdot \exp(B)$。我们将只有常数的起始浓度部分（即 $\exp(-\frac{h_0}{H})$）提取到积分号外面：

$$
\exp\left(-\frac{h_0}{H}\right) \cdot \int_0^L \exp\left( - \frac{h_1 - h_0}{H \cdot L} s \right) ds
$$

**步骤 3：定义跨度系数 k**

为了让式子变清爽，我们可以把高度的“相对变化率”定义起来。令 $k = \frac{h_1 - h_0}{H}$（这就对应了代码里的那行 `float2 k = (hAbove1-hAbove0)/ScaleHeight`）。
而提出来的常数，恰好也就是代码调用过的基底起点密度 `DensityAtHeight(h0)`。
所以式子化简为：

$$
DensityAtHeight(h_0) \cdot \int_0^L \exp\left( - \frac{k}{L} s \right) ds
$$

**步骤 4：套用纯数学积分解决战斗**

根据大学一年级的高等数学微积分公式：$\int e^{a \cdot x} dx = \frac{1}{a} e^{a \cdot x}$。在这里对于积分符号内的式子，唯一的未知变数是 $s$，而系数 $a$ 就是 $-\frac{k}{L}$。
所以积分的原函数结果为：

$$
\Big[ -\frac{L}{k} \exp\left( -\frac{k}{L} s \right) \Big]_0^L
$$

我们把积分的规定上限极值 $s=L$ 和下限极值 $s=0$ 代入进去，拿来相减：

$$
\begin{aligned}
&\left(-\frac{L}{k} e^{-k \cdot \frac{L}{L}}\right) - \left(-\frac{L}{k} e^{-k \cdot 0}\right) \\
={}& -\frac{L}{k} e^{-k} + \frac{L}{k} \cdot 1 \\
={}& L \cdot \frac{1 - e^{-k}}{k}
\end{aligned}
$$


**极致完美的结论：**
最后结果 = $L \cdot \text{DensityAtHeight}(h_0) \cdot \frac{1 - e^{-k}}{k}$。

这个用几步纯代数算出来的结果，就是那条坑坑洼洼高度里绝对精确的真积分面积！
这也就是为什么代码里会凭空冒出一行 `f.x = (1.0 - exp(-k.x)) / k.x;` 以及结尾拼装组装出 `L * Density(h0) * f`。
你的这部分代码之所以高级没有狗牙条带，就是因为它用了一两行四则运算和初等函数，就彻底碾压并取代了普通教程里分几十步循环 for 加出来的劣质近似值。
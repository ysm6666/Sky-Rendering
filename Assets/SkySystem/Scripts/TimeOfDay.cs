using UnityEngine;

[ExecuteAlways]
public class TimeOfDay : MonoBehaviour
{
    [Header("Lights")]
    public Light sunLight;

    [Header("Time Control")]
    [Range(0f, 24f)]
    public float currentTime = 8f; // 8 AM
    public float dayLengthInMinutes = 5f;
    public bool autoPlay = true;

    [Header("Atmosphere & Colors")]
    [Tooltip("太阳光颜色随时间变化 (0:00 - 24:00)")]
    public Gradient sunColor;
    
    [Tooltip("太阳光强度随时间变化 (0:00 - 24:00)")]
    public AnimationCurve sunIntensity;
    
    [Tooltip("全局环境光颜色 (影响模型背光面与云层底部)")]
    public Gradient ambientColor;

    private void OnValidate()
    {
        // 自动初始化未设置的参数，避免每次手动填
        if (sunColor == null || sunColor.colorKeys.Length == 0 || (sunColor.colorKeys.Length == 2 && sunColor.colorKeys[0].color == Color.white && sunColor.colorKeys[1].color == Color.white))
        {
            sunColor = new Gradient()
            {
                colorKeys = new[] {
                    new GradientColorKey(new Color(0.05f, 0.05f, 0.1f), 0.0f),  // 0:00 漆黑
                    new GradientColorKey(new Color(0.8f, 0.4f, 0.1f), 0.25f), // 6:00 橙红日出
                    new GradientColorKey(new Color(1.0f, 0.95f, 0.9f), 0.5f), // 12:00 正午明亮
                    new GradientColorKey(new Color(0.8f, 0.4f, 0.1f), 0.75f), // 18:00 橙红日落
                    new GradientColorKey(new Color(0.05f, 0.05f, 0.1f), 1.0f)   // 24:00 漆黑
                }
            };
        }

        if (sunIntensity == null || sunIntensity.keys.Length == 0)
        {
            sunIntensity = new AnimationCurve(
                new Keyframe(0f, 0f),     // 0:00 无光
                new Keyframe(0.2f, 0f),   // 4:48 夜晚
                new Keyframe(0.25f, 1f),  // 6:00 日出恢复
                new Keyframe(0.5f, 1.5f), // 12:00 正午最强
                new Keyframe(0.75f, 1f),  // 18:00 日落变弱
                new Keyframe(0.8f, 0f),   // 19:12 完全黑
                new Keyframe(1f, 0f)      // 24:00 无光 
            );
        }

        if (ambientColor == null || ambientColor.colorKeys.Length == 0 || (ambientColor.colorKeys.Length == 2 && ambientColor.colorKeys[0].color == Color.white && ambientColor.colorKeys[1].color == Color.white))
        {
            ambientColor = new Gradient()
            {
                colorKeys = new[] {
                    new GradientColorKey(new Color(0.10f, 0.12f, 0.20f), 0.0f), // 夜晚月夜蓝(不死黑)
                    new GradientColorKey(new Color(0.10f, 0.11f, 0.18f), 0.22f),
                    new GradientColorKey(new Color(0.3f, 0.22f, 0.2f), 0.25f),  // 日出环境光偏暖暗
                    new GradientColorKey(new Color(0.6f, 0.7f, 0.8f), 0.5f),    // 正午环境光偏天蓝
                    new GradientColorKey(new Color(0.3f, 0.22f, 0.2f), 0.75f),  // 日落环境光偏暖暗
                    new GradientColorKey(new Color(0.10f, 0.11f, 0.18f), 0.78f),
                    new GradientColorKey(new Color(0.10f, 0.12f, 0.20f), 1.0f)  // 夜晚月夜蓝
                }
            };
        }
    }

    void Update()
    {
        if (Application.isPlaying && autoPlay)
        {
            currentTime += (Time.deltaTime / (dayLengthInMinutes * 60f)) * 24f;
            if (currentTime >= 24f)
            {
                currentTime %= 24f;
            }
        }

        UpdateTimeLighting();
    }

    void UpdateTimeLighting()
    {
        if (sunLight == null) return;

        // 时间百分比映射 0~1 的周期 (0点为0，12点为0.5，24点为1)
        float hourPercent = currentTime / 24f;

        // 旋转角度: 6:00 = 0度，12:00 = 90度，18:00 = 180度
        float angle = (currentTime - 6f) * (180f / 12f);
        sunLight.transform.localRotation = Quaternion.Euler(angle, 170f, 0f); // 固定Y轴防阴影乱闪

        // 获取曲线数值
        float evalIntensity = sunIntensity != null && sunIntensity.keys.Length > 0 
                              ? sunIntensity.Evaluate(hourPercent) : 1f;
        Color evalColor = sunColor != null ? sunColor.Evaluate(hourPercent) : Color.white;

        // 【解决问题2, 3】：保证主光强度永不为0，否则URP会剔除这个方向光！
        // 一旦剔除，自定义天空盒中的月亮将获取不到 _MainLightPosition 导致卡死或乱跳。
        sunLight.intensity = Mathf.Max(0.005f, evalIntensity);

        // 且需要保证颜色非绝对纯黑，防止 maxComponent = 0 被再次剔除。
        float maxCol = Mathf.Max(evalColor.r, Mathf.Max(evalColor.g, evalColor.b));
        if (maxCol < 0.001f)
        {
            evalColor = new Color(0.001f, 0.001f, 0.001f, evalColor.a);
        }
        sunLight.color = evalColor;

        // 覆盖环境光设置（使云层的SampleSH能获取到正确的昼夜漫反射底色）
        if (ambientColor != null)
        {
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = ambientColor.Evaluate(hourPercent);
        }
    }
}

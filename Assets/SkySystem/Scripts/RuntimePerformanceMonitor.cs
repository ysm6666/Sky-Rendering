using UnityEngine;
using UnityEngine.Profiling;

public class RuntimePerformanceMonitor : MonoBehaviour
{
    private float _deltaTime = 0.0f;
    private GUIStyle _style = new GUIStyle();
    private Rect _rect;

    void Start()
    {
        // 解除帧率锁定，以测试极限性能
        Application.targetFrameRate = -1; 
        
        // 自适应屏幕分辨率的字体大小设置
        int h = Screen.height;
        _style.alignment = TextAnchor.UpperLeft;
        _style.fontSize = h * 3 / 100;
        _style.normal.textColor = Color.green;
        
        // 留出左上角的边距
        _rect = new Rect(20, 20, Screen.width, h * 20 / 100);
    }

    void Update()
    {
        // 使用插值平滑 deltaTime，防止帧率数字疯狂闪烁看不清
        _deltaTime += (Time.unscaledDeltaTime - _deltaTime) * 0.1f;
    }

    void OnGUI()
    {
        // 1. 计算 FPS 和 单帧耗时 (毫秒)
        float msec = _deltaTime * 1000.0f;
        float fps = 1.0f / _deltaTime;

        // 2. 获取图形驱动分配的内存 (即 VRAM 显存的近似值)
        // 注意：此 API 在真机上需要 Development Build 才能获取精确值
        long vramBytes = Profiler.GetAllocatedMemoryForGraphicsDriver();
        float vramMB = vramBytes / (1024f * 1024f);

        // 3. 获取引擎分配的总物理内存 (即 RAM 内存)
        long ramBytes = Profiler.GetTotalAllocatedMemoryLong();
        float ramMB = ramBytes / (1024f * 1024f);

        // 4. 获取当前设备理论支持的最大显存 (静态硬件参数)
        int deviceVram = SystemInfo.graphicsMemorySize;

        string text = string.Format(
            "Frame Time: {0:0.0} ms ({1:0.} FPS)\n" +
            "Used VRAM: {2:0.0} MB / {3} MB\n" +
            "Used RAM: {4:0.0} MB", 
            msec, fps, vramMB, deviceVram, ramMB);

        GUI.Label(_rect, text, _style);
    }
}
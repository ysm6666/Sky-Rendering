using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AtmosphereRenderFeature : ScriptableRendererFeature
{
    [Serializable]
    public class Setting
    {
        public Material atmosphereMat;
        public RenderPassEvent Event = RenderPassEvent.AfterRenderingSkybox;
    }

    class CustomRenderPass : ScriptableRenderPass
    {
        private readonly Setting setting;
        RTHandle tempRT;

        public CustomRenderPass(Setting setting)
        {
            this.setting = setting;
            renderPassEvent = setting.Event;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var descriptor = renderingData.cameraData.cameraTargetDescriptor;
            descriptor.depthBufferBits = 0;
            RenderingUtils.ReAllocateIfNeeded(ref tempRT, descriptor);
            // 解决 Game 视图下深度纹理未生成导致大气层全黑或消失的问题
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Color);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (setting.atmosphereMat == null) return;

            CommandBuffer cmd = CommandBufferPool.Get("AtmosphereRenderFeature");
            Material material = setting.atmosphereMat;
            Blitter.BlitCameraTexture(cmd, renderingData.cameraData.renderer.cameraColorTargetHandle, tempRT, material, 0);
            Blitter.BlitCameraTexture(cmd, tempRT, renderingData.cameraData.renderer.cameraColorTargetHandle);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }

        public void Dispose()
        {
            tempRT?.Release();
            tempRT = null;
        }
    }

    CustomRenderPass m_ScriptablePass;
    public Setting setting;

    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass(setting);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (setting.atmosphereMat == null ||
            (renderingData.cameraData.camera.cameraType != CameraType.Game &&
             renderingData.cameraData.camera.cameraType != CameraType.SceneView))
        {
            return;
        }

        m_ScriptablePass.ConfigureInput(ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Depth);
        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        m_ScriptablePass?.Dispose();
    }
}

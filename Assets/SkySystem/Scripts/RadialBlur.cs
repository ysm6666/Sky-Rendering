using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Serialization;

public class RadialBlur : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public Shader raialBlurShader;
        public int BlurAmount;
        [Range(0,1)]
        public float lightRadius;
        [Range(0.1f,1f)]
        public float LuminanceThreshold;
        public float lightStrength;
        [Range(0,1)]
        public float moonStrengthFactor = 0.25f;
        public RenderPassEvent PassEvent;
        public Settings()
        {
            this.BlurAmount = 5;
            this.lightRadius = 2;
            this.raialBlurShader = null;
            LuminanceThreshold = 0.8f;
            this.lightStrength = 1.0f;
            this.PassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }
    }
    class RadialRenderPass : ScriptableRenderPass
    {
        private Material radialBlurMaterial;
        private Shader radialBlurShader;
        private int blurAmount;
        private float lightRadius;
        private float lightStrength;
        private float moonStrengthFactor;
        private float luminanceThreshold;
        private RTHandle extractedRT;
        public RadialRenderPass(Settings settings)
        {
            this.renderPassEvent = settings.PassEvent;
            this.blurAmount = settings.BlurAmount;
            this.lightRadius = settings.lightRadius;
            this.luminanceThreshold = settings.LuminanceThreshold;
            this.lightStrength = settings.lightStrength;
            this.moonStrengthFactor = settings.moonStrengthFactor;
            this.radialBlurShader=settings.raialBlurShader;
        }
        
        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.colorFormat = RenderTextureFormat.ARGBHalf;
            RenderingUtils.ReAllocateIfNeeded(ref extractedRT,desc,name:"ExtractedRT");
            if (radialBlurShader == null)
            {
                Debug.LogWarning("RadialBlur shader not set");
                return;
            }
            if (radialBlurMaterial == null)
            {
                radialBlurMaterial = new Material(radialBlurShader);
            }
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("RadialBlur");
            Light sunlight=RenderSettings.sun;
            Camera camera = renderingData.cameraData.camera;

            if (radialBlurMaterial==null||sunlight==null||camera==null)
            {
                Debug.Log("Radial Blur: radialBlurMaterial==null||sunlight==null||camera==null");
                return;
            }
            // Phase C5: 昼夜切换。夜间光束锚点交接给月亮(太阳对立面,与skybox/大气/云一致)
            Vector3 dirToSun = -sunlight.transform.forward;
            float night = Mathf.Clamp01(-dirToSun.y * 5f);
            Vector3 anchorDir = night > 0.5f ? -dirToSun : dirToSun;
            Vector3 sunWorldPosition = camera.transform.position + anchorDir * camera.farClipPlane;
            Vector3 sunviewPortPosition = camera.WorldToViewportPoint(sunWorldPosition);
            if (sunviewPortPosition.z>=0)
            {
                RTHandle source=renderingData.cameraData.renderer.cameraColorTargetHandle;
                // Phase C5: 夜间强度衰减到月光级(moonStrengthFactor)，过渡期下凹掩盖锚点翻转；阈值微升过滤夜空噪点
                float transitionDip = Mathf.Abs(night * 2f - 1f) * 0.7f + 0.3f;
                float strength = lightStrength * Mathf.Lerp(1f, moonStrengthFactor, night) * transitionDip;
                float threshold = Mathf.Min(luminanceThreshold * Mathf.Lerp(1f, 1.25f, night), 1f);
                cmd.SetGlobalVector(Shader.PropertyToID("_sunPositionVS"), sunviewPortPosition);
                cmd.SetGlobalFloat(Shader.PropertyToID("_LightRadius"), lightRadius);
                cmd.SetGlobalInt(Shader.PropertyToID("_BlurAmount"), blurAmount);
                cmd.SetGlobalFloat(Shader.PropertyToID("_LightThreshold"), threshold);
                cmd.SetGlobalFloat(Shader.PropertyToID("_LightStrength"), strength);
                
                Blitter.BlitCameraTexture(cmd,source,extractedRT,radialBlurMaterial,0);
                Blitter.BlitCameraTexture(cmd,extractedRT,source,radialBlurMaterial,1);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }

        public void Dispose()
        {
            extractedRT?.Release();
            extractedRT = null;
            if (radialBlurMaterial!=null)
            {
                DestroyImmediate(radialBlurMaterial);
                radialBlurMaterial = null;
            }
        }
        
    }

    RadialRenderPass m_ScriptablePass;
    public Settings settings=new Settings();
    /// <inheritdoc/>
    public override void Create()
    {
        if (settings.raialBlurShader != null)
        {
            m_ScriptablePass = new RadialRenderPass(settings);
        }
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        CameraType cameraType = renderingData.cameraData.cameraType;
        if (cameraType==CameraType.Preview || cameraType==CameraType.Reflection)return;
        if (m_ScriptablePass == null)
        {
            Debug.LogError("Radial Blur Pass not set");
            return;
        }
        m_ScriptablePass.ConfigureInput(ScriptableRenderPassInput.Color);
        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        m_ScriptablePass?.Dispose();
    }
}



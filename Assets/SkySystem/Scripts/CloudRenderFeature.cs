using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

public class CloudRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public Material CloudMaterial;
        public RenderPassEvent Event = RenderPassEvent.BeforeRenderingTransparents;
        [Range(1,4)]
        public int downsample = 1;

        public bool useDivisionRendering = true;
    }
    
    class CameraHistory
    {
        public Matrix4x4 PreVPMatrix;
        public int FrameIndex = 0;
        public RTHandle BackBuffer;
        public bool isFirstFrame = true;

        public void Dispose()
        {
            BackBuffer?.Release();
            BackBuffer = null;
        }
    }

   class CloudPass : ScriptableRenderPass
    {
        Material CloudMaterial;
        int downsample;
        private bool useDivisionRendering;
        
        private Dictionary<Camera, CameraHistory> history = new Dictionary<Camera, CameraHistory>();
        
        RTHandle renderCloudRT;
        
        public CloudPass(Settings settings)
        {
            this.CloudMaterial = settings.CloudMaterial;
            this.renderPassEvent = settings.Event;
            this.downsample = settings.downsample;
            this.useDivisionRendering = settings.useDivisionRendering;
        }

        public void SetDownsample(int downsample)
        {
            this.downsample = downsample;
        }
        
        public void Dispose()
        {
            renderCloudRT?.Release();
            renderCloudRT = null;
            foreach (var h in history.Values) h.Dispose();
            history.Clear();
            Shader.SetGlobalTexture(Shader.PropertyToID("_CloudRT"), Texture2D.blackTexture);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
           var desc = renderingData.cameraData.cameraTargetDescriptor;
           desc.depthBufferBits = 0;
           //desc.colorFormat = RenderTextureFormat.DefaultHDR; 手机端默认hdr没有alpha通道
           desc.colorFormat = RenderTextureFormat.ARGBHalf;
           desc.width = Mathf.Max(1, desc.width / downsample);
           desc.height = Mathf.Max(1, desc.height / downsample);
           RenderingUtils.ReAllocateIfNeeded(ref renderCloudRT,desc,name:"TempCloudRT");
           renderCloudRT.rt.filterMode = FilterMode.Bilinear;
           
           if (useDivisionRendering)
           {
               Camera cam = renderingData.cameraData.camera;
               if (!history.TryGetValue(cam, out var camHistory))
               {
                   camHistory = new CameraHistory();
                   history[cam] = camHistory;
               }
               RenderingUtils.ReAllocateIfNeeded(ref camHistory.BackBuffer,desc,name:"TempBackBuffer_" + cam.name);
           }
        }

        void SetAmbientProbe(CommandBuffer cmd)
        {
            SphericalHarmonicsL2 sh = RenderSettings.ambientProbe;
            cmd.SetGlobalVector("unity_SHAr",new Vector4(sh[0,0],sh[0,1],sh[0,2],sh[0,3]));
            cmd.SetGlobalVector("unity_SHAg",new Vector4(sh[1,0],sh[1,1],sh[1,2],sh[1,3]));
            cmd.SetGlobalVector("unity_SHAb",new Vector4(sh[2,0],sh[2,1],sh[2,2],sh[2,3]));
            cmd.SetGlobalVector("unity_SHBr",new Vector4(sh[0,4],sh[0,5],sh[0,6],sh[0,7]));
            cmd.SetGlobalVector("unity_SHBg",new Vector4(sh[1,4],sh[1,5],sh[1,6],sh[1,7]));
            cmd.SetGlobalVector("unity_SHBb",new Vector4(sh[2,4],sh[2,5],sh[2,6],sh[2,7]));
            cmd.SetGlobalVector("unity_SHC",new Vector4(sh[0,8],sh[1,8],sh[2,8],1.0f));
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("CloudRender");
            
            SetAmbientProbe(cmd);
            Camera cam = renderingData.cameraData.camera;
            context.SetupCameraProperties(cam);
            
            CameraHistory camHistory = null;
            if (useDivisionRendering && history.TryGetValue(cam, out camHistory))
            {
                //获取当前帧的vp矩阵
                Matrix4x4 projectionMatrix=GL.GetGPUProjectionMatrix(renderingData.cameraData.GetProjectionMatrix(),false);
                Matrix4x4 viewMatrix = renderingData.cameraData.GetViewMatrix();
                Matrix4x4 currentVPMatrix=projectionMatrix*viewMatrix;
                if (camHistory.isFirstFrame)
                {
                    cmd.DisableShaderKeyword("_Division_Rendering");
                    camHistory.PreVPMatrix = currentVPMatrix;
                    camHistory.isFirstFrame = false;
                }
                else
                {
                    cmd.EnableShaderKeyword("_Division_Rendering");
                }
                cmd.SetGlobalTexture(Shader.PropertyToID("_CloudBackBuffer"), camHistory.BackBuffer);
                cmd.SetGlobalInt(Shader.PropertyToID("_FrameIndex"), camHistory.FrameIndex);
                cmd.SetGlobalMatrix(Shader.PropertyToID("_PreVPMatrix"), camHistory.PreVPMatrix);
                camHistory.PreVPMatrix = currentVPMatrix;
            }
            else
            {
                cmd.DisableShaderKeyword("_Division_Rendering");
            }
            
            var source=renderingData.cameraData.renderer.cameraColorTargetHandle;
            
            CoreUtils.SetRenderTarget(cmd, renderCloudRT, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, ClearFlag.None, Color.clear);
            Blitter.BlitCameraTexture(cmd, source, renderCloudRT, CloudMaterial, 0);
            
            if (useDivisionRendering && camHistory != null)
            {
                CoreUtils.SetRenderTarget(cmd, camHistory.BackBuffer, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, ClearFlag.None, Color.clear);
                Blitter.BlitCameraTexture(cmd, renderCloudRT, camHistory.BackBuffer);
                camHistory.FrameIndex = (camHistory.FrameIndex+1) % 16;
            }
            
            CoreUtils.SetRenderTarget(cmd, source, RenderBufferLoadAction.Load, RenderBufferStoreAction.Store, ClearFlag.None, Color.clear);
            Blitter.BlitCameraTexture(cmd, renderCloudRT, source, CloudMaterial, 1);
            
            cmd.SetGlobalTexture(Shader.PropertyToID("_CloudRT"), renderCloudRT);
            
            context.ExecuteCommandBuffer(cmd);
            
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
           
        }
    }
    public Settings settings = new Settings();
    CloudPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        if (settings.CloudMaterial == null)
        {
            return;
        }
        m_ScriptablePass = new CloudPass(settings);
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        CameraType cameraType = renderingData.cameraData.cameraType;
        if (cameraType==CameraType.Preview || cameraType==CameraType.Reflection)
        {
            return;
        }
        if (settings.CloudMaterial && m_ScriptablePass!=null)
        {
            m_ScriptablePass.ConfigureInput(ScriptableRenderPassInput.Color); 
            renderer.EnqueuePass(m_ScriptablePass);    
        }
    }

    protected override void Dispose(bool disposing)
    {
        m_ScriptablePass?.Dispose();
    }

    public void SetDownsample(int downsample)
    {
        m_ScriptablePass?.SetDownsample(downsample);
    }
}



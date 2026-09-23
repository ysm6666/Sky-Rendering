using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;

// 离线烘焙体积云噪声（Hillaire TileableVolumeNoise 算法族，全部无缝 tileable）
// R = Perlin-Worley, GBA = Worley FBM 三档 —— 与 RenderCloudTest_Shape.shader 的通道语义一致
public static class CloudNoiseBaker
{
    // 实际资产目录。必须与 cloud_shape.mat 引用的贴图路径一致，
    // 且 CreateOrReplace 走 CopySerialized 原地覆盖以保住 GUID（否则材质贴图槽会断链变纯白）
    const string OutDir = "Assets/SkySystem/Textures/Baked";
    const string OutParent = "Assets/SkySystem/Textures";

    // ---------------- Hash ----------------
    static float Hash(int x, int y, int z, int seed)
    {
        unchecked
        {
            uint h = (uint)seed;
            h ^= (uint)x * 0x9E3779B1u; h = (h << 13) | (h >> 19); h *= 0x85EBCA6Bu;
            h ^= (uint)y * 0xC2B2AE35u; h = (h << 11) | (h >> 21); h *= 0x27D4EB2Fu;
            h ^= (uint)z * 0x165667B1u; h = (h << 15) | (h >> 17); h *= 0x9E3779B1u;
            h ^= h >> 16;
            return (h & 0xFFFFFF) / (float)0x1000000;
        }
    }

    static int Wrap(int v, int period) { v %= period; return v < 0 ? v + period : v; }

    // ---------------- Tileable Worley (返回 1-F1, 即"泡泡"形) ----------------
    static float Worley(float px, float py, float pz, int cells, int seed)
    {
        px *= cells; py *= cells; pz *= cells;
        int cx = Mathf.FloorToInt(px), cy = Mathf.FloorToInt(py), cz = Mathf.FloorToInt(pz);
        float minD = 1e10f;
        for (int ox = -1; ox <= 1; ox++)
        for (int oy = -1; oy <= 1; oy++)
        for (int oz = -1; oz <= 1; oz++)
        {
            int ix = cx + ox, iy = cy + oy, iz = cz + oz;
            int wx = Wrap(ix, cells), wy = Wrap(iy, cells), wz = Wrap(iz, cells);
            float fx = ix + Hash(wx, wy, wz, seed);
            float fy = iy + Hash(wx, wy, wz, seed + 91);
            float fz = iz + Hash(wx, wy, wz, seed + 173);
            float dx = px - fx, dy = py - fy, dz = pz - fz;
            float d = dx * dx + dy * dy + dz * dz;
            if (d < minD) minD = d;
        }
        return 1f - Mathf.Clamp01(Mathf.Sqrt(minD));
    }

    static float WorleyFbm(float x, float y, float z, int baseCells, int seed)
    {
        return Worley(x, y, z, baseCells, seed) * 0.625f
             + Worley(x, y, z, baseCells * 2, seed + 7) * 0.25f
             + Worley(x, y, z, baseCells * 4, seed + 13) * 0.125f;
    }

    // ---------------- Tileable Perlin ----------------
    static readonly Vector3[] Grads =
    {
        new(1,1,0), new(-1,1,0), new(1,-1,0), new(-1,-1,0),
        new(1,0,1), new(-1,0,1), new(1,0,-1), new(-1,0,-1),
        new(0,1,1), new(0,-1,1), new(0,1,-1), new(0,-1,-1)
    };

    static float Fade(float t) => t * t * t * (t * (t * 6f - 15f) + 10f);

    static float GradDot(int x, int y, int z, int period, int seed, float dx, float dy, float dz)
    {
        var g = Grads[(int)(Hash(Wrap(x, period), Wrap(y, period), Wrap(z, period), seed) * 11.999f)];
        return g.x * dx + g.y * dy + g.z * dz;
    }

    static float Perlin(float px, float py, float pz, int period, int seed)
    {
        px *= period; py *= period; pz *= period;
        int x0 = Mathf.FloorToInt(px), y0 = Mathf.FloorToInt(py), z0 = Mathf.FloorToInt(pz);
        float fx = px - x0, fy = py - y0, fz = pz - z0;
        float u = Fade(fx), v = Fade(fy), w = Fade(fz);
        float n000 = GradDot(x0, y0, z0, period, seed, fx, fy, fz);
        float n100 = GradDot(x0 + 1, y0, z0, period, seed, fx - 1, fy, fz);
        float n010 = GradDot(x0, y0 + 1, z0, period, seed, fx, fy - 1, fz);
        float n110 = GradDot(x0 + 1, y0 + 1, z0, period, seed, fx - 1, fy - 1, fz);
        float n001 = GradDot(x0, y0, z0 + 1, period, seed, fx, fy, fz - 1);
        float n101 = GradDot(x0 + 1, y0, z0 + 1, period, seed, fx - 1, fy, fz - 1);
        float n011 = GradDot(x0, y0 + 1, z0 + 1, period, seed, fx, fy - 1, fz - 1);
        float n111 = GradDot(x0 + 1, y0 + 1, z0 + 1, period, seed, fx - 1, fy - 1, fz - 1);
        float nx00 = Mathf.Lerp(n000, n100, u), nx10 = Mathf.Lerp(n010, n110, u);
        float nx01 = Mathf.Lerp(n001, n101, u), nx11 = Mathf.Lerp(n011, n111, u);
        return Mathf.Lerp(Mathf.Lerp(nx00, nx10, v), Mathf.Lerp(nx01, nx11, v), w); // [-1,1]
    }

    static float PerlinFbm(float x, float y, float z, int basePeriod, int octaves, int seed)
    {
        float sum = 0, amp = 1, ampSum = 0;
        int p = basePeriod;
        for (int i = 0; i < octaves; i++)
        {
            sum += Perlin(x, y, z, p, seed + i * 37) * amp;
            ampSum += amp;
            amp *= 0.5f; p *= 2;
        }
        return sum / ampSum * 0.5f + 0.5f; // [0,1]
    }

    static float Remap(float v, float a, float b, float c, float d) => c + (v - a) / (b - a) * (d - c);

    // ---------------- Bake ----------------
    [MenuItem("Tools/Cloud/Bake All Cloud Noise")]
    public static void BakeAll()
    {
        if (!AssetDatabase.IsValidFolder(OutDir))
            AssetDatabase.CreateFolder(OutParent, "Baked");

        BakeBase128();
        BakeDetail64();
        BakeCurl128();
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("[CloudNoiseBaker] All done. Assets in " + OutDir);
    }

    [MenuItem("Tools/Cloud/Bake Weather Map")]
    public static void BakeWeather()
    {
        if (!AssetDatabase.IsValidFolder(OutDir))
            AssetDatabase.CreateFolder(OutParent, "Baked");
        const int N = 512;
        var data = new Color32[N * N];
        var regBuf = new float[N * N];
        var locBuf = new float[N * N];
        var typeBuf = new float[N * N];

        // 通道语义（与 shader SampleCoverageField 单次采样对应）：
        // R = 低频天气团（区域云量，数公里级缓变）
        // G = 高频云朵轮廓（Perlin-Worley 风格混合），烘焙时与 R 的大型对齐——
        //     "云长在天气团内部"，高频不再游离于低频之外（UE复刻文建议）
        // B = 云型区域（层积/浓积成片分布）
        // 两个 coverage 通道都必须直方图拉伸铺满 0~1（阈值裁剪的量纲前提），但不 clamp 拉对比
        float regMin = float.MaxValue, regMax = float.MinValue;
        for (int y = 0; y < N; y++)
        {
            for (int x = 0; x < N; x++)
            {
                float u = x / (float)N, v = y / (float)N;
                int i = y * N + x;
                regBuf[i] = PerlinFbm(u, v, 0.23f, 3, 2, 3100);
                if (regBuf[i] < regMin) regMin = regBuf[i];
                if (regBuf[i] > regMax) regMax = regBuf[i];
                typeBuf[i] = Mathf.Clamp01(Remap(PerlinFbm(u, v, 0.53f, 2, 3, 2200), 0.35f, 0.65f, 0f, 1f));
            }
        }
        float regInv = 1f / Mathf.Max(regMax - regMin, 1e-5f);

        float locMin = float.MaxValue, locMax = float.MinValue;
        for (int y = 0; y < N; y++)
        {
            for (int x = 0; x < N; x++)
            {
                float u = x / (float)N, v = y / (float)N;
                int i = y * N + x;
                // 多八度 Perlin 出大小不一的团块 + Billow 出明确边界 + Worley 出云朵个体感
                float shape = PerlinFbm(u, v, 0.41f, 12, 4, 3200);
                float billow = 1f - Mathf.Abs(PerlinFbm(u, v, 0.59f, 16, 3, 3300) * 2f - 1f);
                float cell = WorleyFbm(u, v, 0.31f, 8, 3400);
                float raw = shape * 0.45f + billow * 0.25f + cell * 0.30f;
                // 与低频大型对齐：天气团弱处高频整体压低，云只在天气团里成片
                float regNorm = (regBuf[i] - regMin) * regInv;
                locBuf[i] = raw * Mathf.Lerp(0.55f, 1.0f, regNorm);
                if (locBuf[i] < locMin) locMin = locBuf[i];
                if (locBuf[i] > locMax) locMax = locBuf[i];
            }
        }
        float locInv = 1f / Mathf.Max(locMax - locMin, 1e-5f);
        for (int i = 0; i < data.Length; i++)
        {
            float r = (regBuf[i] - regMin) * regInv;
            float g = (locBuf[i] - locMin) * locInv;
            data[i] = new Color32((byte)(r * 255f), (byte)(g * 255f), (byte)(typeBuf[i] * 255f), 255);
        }
        Debug.Log(string.Format("[CloudNoiseBaker] WeatherMap R raw {0:F3}~{1:F3}, G raw {2:F3}~{3:F3} -> normalized 0~1", regMin, regMax, locMin, locMax));
        var tex = new Texture2D(N, N, TextureFormat.RGBA32, false, true)
        {
            wrapMode = TextureWrapMode.Repeat,
            filterMode = FilterMode.Bilinear
        };
        tex.SetPixels32(data);
        tex.Apply(false);
        CreateOrReplace(tex, OutDir + "/WeatherMap512.asset");
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
    }

    static void BakeBase128()
    {
        const int N = 128;
        var data = new Color32[N * N * N];
        for (int z = 0; z < N; z++)
        {
            int zz = z;
            EditorUtility.DisplayProgressBar("Bake BaseNoise 128^3", $"slice {z}/{N}", z / (float)N);
            Parallel.For(0, N, y =>
            {
                for (int x = 0; x < N; x++)
                {
                    float u = x / (float)N, v = y / (float)N, w = zz / (float)N;
                    float perlin = PerlinFbm(u, v, w, 4, 7, 1234);
                    float wf0 = WorleyFbm(u, v, w, 4, 100);
                    float wf1 = WorleyFbm(u, v, w, 8, 200);
                    float wf2 = WorleyFbm(u, v, w, 16, 300);
                    // Perlin-Worley: 用 worley 抬高 perlin 下限（Hillaire）
                    float pw = Mathf.Clamp01(Remap(perlin, 0f, 1f, wf0, 1f));
                    data[(zz * N + y) * N + x] = new Color32(
                        (byte)(pw * 255f), (byte)(wf0 * 255f), (byte)(wf1 * 255f), (byte)(wf2 * 255f));
                }
            });
        }
        EditorUtility.ClearProgressBar();
        SaveTex3D(data, N, OutDir + "/BaseNoise128.asset");
    }

    static void BakeDetail64()
    {
        const int N = 64;
        var data = new Color32[N * N * N];
        for (int z = 0; z < N; z++)
        {
            int zz = z;
            EditorUtility.DisplayProgressBar("Bake DetailNoise 64^3", $"slice {z}/{N}", z / (float)N);
            Parallel.For(0, N, y =>
            {
                for (int x = 0; x < N; x++)
                {
                    float u = x / (float)N, v = y / (float)N, w = zz / (float)N;
                    float r = WorleyFbm(u, v, w, 4, 400);
                    float g = WorleyFbm(u, v, w, 8, 500);
                    float b = Worley(u, v, w, 16, 600) * 0.75f + Worley(u, v, w, 32, 610) * 0.25f;
                    data[(zz * N + y) * N + x] = new Color32(
                        (byte)(r * 255f), (byte)(g * 255f), (byte)(b * 255f), 255);
                }
            });
        }
        EditorUtility.ClearProgressBar();
        SaveTex3D(data, N, OutDir + "/DetailNoise64.asset");
    }

    static void BakeCurl128()
    {
        const int N = 128;
        var data = new Color32[N * N];
        const float eps = 1f / 128f;
        for (int y = 0; y < N; y++)
        {
            for (int x = 0; x < N; x++)
            {
                float u = x / (float)N, v = y / (float)N;
                // 2D curl = (dPhi/dy, -dPhi/dx)，势场用 tileable perlin（z 固定切片）
                float p1 = PerlinFbm(u, v + eps, 0.5f, 6, 3, 900);
                float p2 = PerlinFbm(u, v - eps, 0.5f, 6, 3, 900);
                float p3 = PerlinFbm(u + eps, v, 0.5f, 6, 3, 900);
                float p4 = PerlinFbm(u - eps, v, 0.5f, 6, 3, 900);
                float cx = (p1 - p2) / (2f * eps);
                float cy = -(p3 - p4) / (2f * eps);
                var c = new Vector2(cx, cy);
                if (c.magnitude > 1e-5f) c = c.normalized * Mathf.Clamp01(c.magnitude * 0.25f);
                data[y * N + x] = new Color32(
                    (byte)((c.x * 0.5f + 0.5f) * 255f), (byte)((c.y * 0.5f + 0.5f) * 255f), 128, 255);
            }
        }
        var tex = new Texture2D(N, N, TextureFormat.RGBA32, false, true)
        {
            wrapMode = TextureWrapMode.Repeat,
            filterMode = FilterMode.Bilinear
        };
        tex.SetPixels32(data);
        tex.Apply(false);
        CreateOrReplace(tex, OutDir + "/CurlNoise128.asset");
    }

    static void SaveTex3D(Color32[] data, int n, string path)
    {
        var tex = new Texture3D(n, n, n, TextureFormat.RGBA32, false)
        {
            wrapMode = TextureWrapMode.Repeat,
            filterMode = FilterMode.Bilinear
        };
        tex.SetPixelData(data, 0);
        tex.Apply(false);
        CreateOrReplace(tex, path);
    }

    static void CreateOrReplace(Object asset, string path)
    {
        var existing = AssetDatabase.LoadMainAssetAtPath(path);
        if (existing != null)
        {
            // 用序列化拷贝覆盖旧资产，保住 GUID——否则材质引用会断链变默认白图
            EditorUtility.CopySerialized(asset, existing);
            EditorUtility.SetDirty(existing);
        }
        else
        {
            AssetDatabase.CreateAsset(asset, path);
        }
        Debug.Log("[CloudNoiseBaker] Saved " + path);
    }
}

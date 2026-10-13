// Мини-библиотека для звуков мода: PCM16 WAV <-> float mono, нарезка, смешивание, питч.
// Подключается из PowerShell через Add-Type (компилятор .NET Framework уже есть в Windows).
using System;
using System.Collections.Generic;
using System.IO;

public static class Sfx
{
    public const int Rate = 44100;   // формат звуков игры/USM: mono 44.1 kHz 16-bit

    // Читает PCM16 WAV любого числа каналов, сводит в моно и пересэмплирует в 44.1 kHz.
    public static float[] Load(string path)
    {
        byte[] b = File.ReadAllBytes(path);
        int p = 12, ch = 0, sr = 0, bits = 0;
        while (p + 8 <= b.Length)
        {
            string id = System.Text.Encoding.ASCII.GetString(b, p, 4);
            int size = BitConverter.ToInt32(b, p + 4);
            if (id == "fmt ")
            {
                if (BitConverter.ToUInt16(b, p + 8) != 1) throw new Exception(path + ": not PCM");
                ch = BitConverter.ToUInt16(b, p + 10);
                sr = BitConverter.ToInt32(b, p + 12);
                bits = BitConverter.ToUInt16(b, p + 22);
            }
            else if (id == "data")
            {
                if (bits != 16) throw new Exception(path + ": need 16-bit");
                int frames = size / (2 * ch);
                float[] mono = new float[frames];
                for (int i = 0; i < frames; i++)
                {
                    float s = 0;
                    for (int c = 0; c < ch; c++) s += BitConverter.ToInt16(b, p + 8 + (i * ch + c) * 2);
                    mono[i] = s / ch / 32768f;
                }
                return sr == Rate ? mono : Speed(mono, (double)sr / Rate);
            }
            p += 8 + size + (size & 1);
        }
        throw new Exception(path + ": no data chunk");
    }

    public static void Save(string path, float[] x)
    {
        using (var w = new BinaryWriter(File.Create(path)))
        {
            int data = x.Length * 2;
            w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + data);
            w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt ")); w.Write(16);
            w.Write((short)1); w.Write((short)1); w.Write(Rate); w.Write(Rate * 2); w.Write((short)2); w.Write((short)16);
            w.Write(System.Text.Encoding.ASCII.GetBytes("data")); w.Write(data);
            foreach (float s in x) w.Write((short)Math.Max(-32767, Math.Min(32767, Math.Round(s * 32767))));
        }
    }

    // Линейное пересэмплирование: factor > 1 = быстрее и выше, < 1 = медленнее и ниже.
    public static float[] Speed(float[] x, double factor)
    {
        int n = (int)(x.Length / factor);
        float[] y = new float[n];
        for (int i = 0; i < n; i++)
        {
            double pos = i * factor; int j = (int)pos; double f = pos - j;
            float a = x[Math.Min(j, x.Length - 1)], c = x[Math.Min(j + 1, x.Length - 1)];
            y[i] = (float)(a + (c - a) * f);
        }
        return y;
    }

    // Начала ударов: огибающая RMS по 5 мс, скачок выше порога после тишины.
    public static int[] Onsets(float[] x, double thresholdRatio, double minGapSec)
    {
        int win = Rate / 200; int n = x.Length / win;
        double[] env = new double[n]; double max = 0;
        for (int k = 0; k < n; k++)
        {
            double s = 0; for (int i = 0; i < win; i++) { double v = x[k * win + i]; s += v * v; }
            env[k] = Math.Sqrt(s / win); max = Math.Max(max, env[k]);
        }
        var res = new List<int>(); int gap = (int)(minGapSec * 200); int last = -gap;
        for (int k = 1; k < n; k++)
            if (env[k] > max * thresholdRatio && env[k] > env[k - 1] * 2.0 && k - last >= gap) { res.Add(k * win); last = k; }
        return res.ToArray();
    }

    public static float Peak(float[] x) { float m = 0; foreach (float v in x) m = Math.Max(m, Math.Abs(v)); return m; }
    public static double Rms(float[] x) { double s = 0; foreach (float v in x) s += v * v; return Math.Sqrt(s / Math.Max(1, x.Length)); }

    // Кусок с короткой атакой и плавным затуханием (без щелчков на краях).
    public static float[] Slice(float[] x, int start, double lenSec, double fadeSec)
    {
        start = Math.Max(0, start - Rate / 500);   // 2 мс до удара, чтобы не срезать атаку
        int n = Math.Min((int)(lenSec * Rate), x.Length - start);
        float[] y = new float[n]; int fade = Math.Min(n, (int)(fadeSec * Rate)); int att = Math.Min(n, Rate / 1000);
        for (int i = 0; i < n; i++)
        {
            double g = 1;
            if (i < att) g = (double)i / att;
            if (i >= n - fade) g *= Math.Pow((double)(n - i) / fade, 2);
            y[i] = (float)(x[start + i] * g);
        }
        return y;
    }

    // Смешивает b в a со сдвигом offsetSec и громкостью gain; длина = большая из двух.
    public static float[] Mix(float[] a, float[] b, double offsetSec, double gain)
    {
        int off = (int)(offsetSec * Rate);
        float[] y = new float[Math.Max(a.Length, off + b.Length)];
        Array.Copy(a, y, a.Length);
        for (int i = 0; i < b.Length; i++) y[off + i] += (float)(b[i] * gain);
        return y;
    }

    // Простой однополюсный фильтр низких частот: убирает «хрусткий» верх у дальних/тяжёлых ударов.
    public static float[] LowPass(float[] x, double cutoffHz)
    {
        double rc = 1.0 / (2 * Math.PI * cutoffHz), dt = 1.0 / Rate, a = dt / (rc + dt);
        float[] y = new float[x.Length]; double s = 0;
        for (int i = 0; i < x.Length; i++) { s += a * (x[i] - s); y[i] = (float)s; }
        return y;
    }

    // Мягкое ограничение (tanh): поднимает среднюю громкость без жёсткого клиппинга.
    public static float[] SoftClip(float[] x, double drive)
    {
        float[] y = new float[x.Length]; double k = Math.Tanh(drive);
        for (int i = 0; i < x.Length; i++) y[i] = (float)(Math.Tanh(x[i] * drive) / k);
        return y;
    }

    public static float[] Normalize(float[] x, double peak)
    {
        float m = Peak(x); if (m <= 0) return x;
        float[] y = new float[x.Length]; double g = peak / m;
        for (int i = 0; i < x.Length; i++) y[i] = (float)(x[i] * g);
        return y;
    }
}

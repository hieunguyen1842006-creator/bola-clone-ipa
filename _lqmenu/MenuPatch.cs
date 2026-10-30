// NVH LQ LIVE CONFIG — patch IFix hook LFramework.get_frameSynchr
//
// NHIEM VU: doc file Documents/nvh_aov.txt (app ghi) va ap vao PlayerPrefs
// key iFix.* ma payload AOV (HeroSkin_1/2) dang doc. App doi toggle -> ghi
// file -> patch doc trong ~1 giay -> payload ap ngay, khong can tat game.
//
// QUAN TRONG 1: IFix CHI patch method khai trong process_cfg. TOAN BO logic
//   nam trong MOT method get_frameSynchr(). KHONG goi method khac cua LFramework.
// QUAN TRONG 2: get_frameSynchr co the bi goi nhieu lan moi frame — gioi han
//   doc file bang Time.realtimeSinceStartup: toi da 1 lan/giay.
// QUAN TRONG 3: KHONG co UI, KHONG dung Input API (bi strip tren build iOS),
//   moi lenh rui ro boc trong try/catch — exception khong bao gio lan ra ngoai.
//
// Format nvh_aov.txt (app ghi, rev tang moi lan doi):
//   rev=3
//   esp=1
//   bp=0
//   aim=1
//   tmode=0        (0=hp 1=percent 2=near 3=ray)
//   lines=3        (1..5)
//   draw=1         (0=off 1=always 2=skill)
//   smite=1        (0=off 1=on)
//   smt=0          (0=boss 1=buff 2=all)
//   zoom=1.6       (1.0..5.0)
//   skin=111:0     (heroId:modelIndex)

using System;
using UnityEngine;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

// ---------------- type gia lap (IFix resolve ten) ----------------
// LFrameSynchr PHAI cung namespace voi LFramework — signature method trong
// process_cfg la NucleusDrive.Logic.LFrameSynchr, sai namespace = IFix khong
// tim thay method de patch (sinh patch rong).

namespace NucleusDrive.Logic
{
    public class LFrameSynchr { }

    public class LFramework
    {
        // ---- field CO SAN cua game (KHONG khai trong process_cfg) ----
        public LFrameSynchr _frameSynchr;

        // ---- field moi ----
        public int   __mRev;        // rev da ap (bo qua file khong doi)
        public float __mNext;       // moc thoi gian duoc doc tiep

        /// <summary>Doc nvh_aov.txt moi giay -> ghi PlayerPrefs iFix.*</summary>
        public LFrameSynchr get_frameSynchr()
        {
            LFrameSynchr fs = _frameSynchr;

            // gioi tan so: toi da 1 lan moi giay, bat ke goi may lan/frame
            float now = Time.realtimeSinceStartup;
            if (now < __mNext) return fs;
            __mNext = now + 1.0f;

            try
            {
                string path = Application.persistentDataPath + "/nvh_aov.txt";
                if (!System.IO.File.Exists(path)) return fs;
                string t = System.IO.File.ReadAllText(path);
                if (t == null || t.Length == 0) return fs;

                // ---- rev: chi ap dung khi file doi ----
                int rev = __mRev;
                int p = t.IndexOf("rev=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 4, e - p - 4)
                                       : t.Substring(p + 4);
                    int v;
                    if (int.TryParse(s.Trim(), out v)) rev = v;
                }
                if (rev == __mRev) return fs;
                __mRev = rev;

                // ---- esp ----
                p = t.IndexOf("esp=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 4, e - p - 4)
                                       : t.Substring(p + 4);
                    int v;
                    if (int.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetInt("iFix.ESP.Enabled.v1", v);
                }

                // ---- bocpha ----
                p = t.IndexOf("bp=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 3, e - p - 3)
                                       : t.Substring(p + 3);
                    int v;
                    if (int.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetInt("iFix.AutoBP.Enabled.v1", v);
                }

                // ---- aim on/off ----
                p = t.IndexOf("aim=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 4, e - p - 4)
                                       : t.Substring(p + 4);
                    int v;
                    if (int.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetInt("iFix.AIM.Enabled.v1", v);
                }

                // ---- aim target mode ----
                p = t.IndexOf("tmode=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 6, e - p - 6)
                                       : t.Substring(p + 6);
                    int v;
                    if (int.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetInt("iFix.AIM.TargetMode.v1", v);
                }

                // ---- aim lines ----
                p = t.IndexOf("lines=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 6, e - p - 6)
                                       : t.Substring(p + 6);
                    int v;
                    if (int.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetInt("iFix.AIM.Lines.v1", v);
                }

                // ---- draw mode ----
                p = t.IndexOf("draw=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 5, e - p - 5)
                                       : t.Substring(p + 5);
                    int v;
                    if (int.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetInt("iFix.AIM.DrawMode.v1", v);
                }

                // ---- smite on/off + target ----
                p = t.IndexOf("smite=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 6, e - p - 6)
                                       : t.Substring(p + 6);
                    int v;
                    if (int.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetInt("iFix.AutoSmite.Enabled.v1", v);
                }
                p = t.IndexOf("smt=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 4, e - p - 4)
                                       : t.Substring(p + 4);
                    int v;
                    if (int.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetInt("iFix.AutoSmite.TargetMode.v1", v);
                }

                // ---- camera zoom ----
                p = t.IndexOf("zoom=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 5, e - p - 5)
                                       : t.Substring(p + 5);
                    float v;
                    if (float.TryParse(s.Trim(), out v))
                        PlayerPrefs.SetFloat("iFix.Camera.Zoom.v1", v);
                }

                // ---- skin hero:model ----
                p = t.IndexOf("skin=");
                if (p >= 0)
                {
                    int e = t.IndexOf('\n', p);
                    string s = (e > p) ? t.Substring(p + 5, e - p - 5)
                                       : t.Substring(p + 5);
                    s = s.Trim();
                    int c = s.IndexOf(':');
                    if (c > 0)
                    {
                        int hero;
                        int model;
                        if (int.TryParse(s.Substring(0, c).Trim(), out hero)
                            && int.TryParse(s.Substring(c + 1).Trim(), out model))
                        {
                            PlayerPrefs.SetInt("iFix.SelectedSkin.v1." + hero, model);
                        }
                    }
                }

                PlayerPrefs.Save();
            }
            catch (Exception)
            {
                // nuot het — khong cho exception lan ra duong goi cua game
            }

            return fs;
        }
    }
}

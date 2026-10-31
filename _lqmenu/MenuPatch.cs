// NVH LQ HB PROBE — build CHAN DOAN
//
// Muc dich DUY NHAT: xac dinh patch co THUC THI hay khong.
//   - Khong detection, khong goi API nao cua game.
//   - Chi doc nvh_aov.txt (live config nhu v2) + ghi 2 con dem vao PlayerPrefs:
//       iFix.HB.Loaded   = 1            (da vao duoc hook)
//       iFix.HB.Calls    = <so frame>   (tang dan moi 30 frame)
//   - Neu app KHONG thay iFix.HB.Loaded sau khi mo game => hook khong chay
//     => loi nam o payload/load, khong phai o logic ben trong.
//
// 3 lop chan nhu v2: L1 chi thread chinh | L2 probe Input | L3 try/catch.

using System;
using UnityEngine;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

namespace NucleusDrive.Logic
{
    public class LFrameSynchr { }

    public class LFramework
    {
        // ---- field CO SAN cua game (KHONG khai trong process_cfg) ----
        public LFrameSynchr _frameSynchr;

        // ---- field moi ----
        public int   __mMainTid;    // thread id ghi danh dau tien = thread chinh
        public int   __mRev;        // rev da ap (bo qua file khong doi)
        public int   __mCalls;      // so frame da chay qua
        public float __mNext;       // moc thoi gian doc config tiep

        public LFrameSynchr get_frameSynchr()
        {
            LFrameSynchr fs = _frameSynchr;

            try
            {
                // ==== L1: chan thread ====
                int tid = System.Threading.Thread.CurrentThread.ManagedThreadId;
                if (__mMainTid == 0) __mMainTid = tid;
                if (tid != __mMainTid) return fs;

                // ==== HB: bang chung patch dang chay ====
                __mCalls = __mCalls + 1;
                try
                {
                    if (__mCalls == 1)
                    {
                        PlayerPrefs.SetInt("iFix.HB.Loaded", 1);
                        PlayerPrefs.Save();
                    }
                    PlayerPrefs.SetInt("iFix.HB.Calls", __mCalls);
                    if ((__mCalls % 30) == 0) PlayerPrefs.Save();
                }
                catch (Exception) { }

                // ==== L2: probe Input ====
                int probe = Input.touchCount;
                if (probe < -1) return fs;

                float now = Time.realtimeSinceStartup;

                // ==== doc live config moi giay (giong v2 da chay on) ====
                if (now >= __mNext)
                {
                    __mNext = now + 1.0f;
                    string path = Application.persistentDataPath + "/nvh_aov.txt";
                    if (System.IO.File.Exists(path))
                    {
                        string t = System.IO.File.ReadAllText(path);
                        if (t != null && t.Length > 0)
                        {
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
                            if (rev != __mRev)
                            {
                                __mRev = rev;

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
                        }
                    }
                }
            }
            catch (Exception)
            {
                // nuot het — khong cho exception lan ra duong goi cua game
            }

            return fs;
        }
    }
}

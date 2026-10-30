// NVH LQ LIVE CONFIG v2 — patch IFix hook LFramework.get_frameSynchr
//
// NHIEM VU: doc Documents/nvh_aov.txt (app ghi) moi giay, ap vao PlayerPrefs
// key iFix.* ma payload AOV doc. File nvh_aov.log = heartbeat de app doc.
//
// BAU VAT LIEU TU CAC BAN TRUOC (da kiem chung tren may that):
//   - diag-2 (touchCount LA LENH DAU TIEN cua body): KHONG đơ — call nem
//     exception thi exception lan ra vo hai.
//   - diag-3 / livecfg-v1 (body chay that: UI write / File + PlayerPrefs):
//     đơ luc load vao tran.
//   => Hook bi goi trong ngu canh ma Unity API nang khong chiu (kha nang cao:
//      thread phu cua frame-sync khi load). Managed exception vo hai, con
//      API tren thread sai thi treo.
//
// VAy v2 co 3 lop chan truoc moi viec nang:
//   L1: chi lam viec tren thread ghi danh dau tien (thread chinh).
//   L2: probe Input.touchCount — tai tao dung hanh xu an toan cua diag-2:
//       nem exception = bo qua toan bo phan viec nang.
//   L3: try/catch toan bo — khong exception nao lan ra ngoai.
// Toan bo API da kiem tra RVA trong dump.cs: deu compiled.

using System;
using UnityEngine;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

// ---------------- type gia lap (IFix resolve ten) ----------------
// LFrameSynchr PHAI cung namespace voi LFramework — signature trong process_cfg
// la NucleusDrive.Logic.LFrameSynchr, sai namespace = IFix sinh patch rong.

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
        public int   __mCalls;      // dem luot chay qua phan viec (heartbeat)
        public float __mNext;       // moc thoi gian doc config tiep
        public float __mLogNext;    // moc thoi gian ghi heartbeat tiep

        /// <summary>Doc nvh_aov.txt moi giay -> ghi PlayerPrefs iFix.*</summary>
        public LFrameSynchr get_frameSynchr()
        {
            LFrameSynchr fs = _frameSynchr;

            try
            {
                // ==== L1: chan thread ====
                int tid = System.Threading.Thread.CurrentThread.ManagedThreadId;
                if (__mMainTid == 0)
                {
                    // luot goi dau tien cua framework = thread chinh (khoi tao
                    // game chay tren main — cac ban truoc tao UI thanh cong o
                    // luot nay nen thread nay chay duoc Unity API)
                    __mMainTid = tid;
                }
                if (tid != __mMainTid) return fs;

                // ==== L2: probe Input — ngu canh "Input System only" nem
                // exception, hanh xu dung nhu diag-2 (an toan, khong đơ) ====
                int probe = Input.touchCount;
                if (probe < -1) return fs;

                __mCalls = __mCalls + 1;
                float now = Time.realtimeSinceStartup;

                // ==== doc config moi giay ====
                if (now >= __mNext)
                {
                    __mNext = now + 1.0f;
                    string path = Application.persistentDataPath + "/nvh_aov.txt";
                    if (System.IO.File.Exists(path))
                    {
                        string t = System.IO.File.ReadAllText(path);
                        if (t != null && t.Length > 0)
                        {
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

                // ==== heartbeat moi 5 giay — app doc file nay ====
                if (now >= __mLogNext)
                {
                    __mLogNext = now + 5.0f;
                    string hb = "tid=" + tid + " main=1 rev=" + __mRev
                        + " calls=" + __mCalls + " t=" + (int)now;
                    System.IO.File.WriteAllText(
                        Application.persistentDataPath + "/nvh_aov.log", hb);
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

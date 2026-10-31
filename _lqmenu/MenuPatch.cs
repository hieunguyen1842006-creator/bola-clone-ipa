// NVH LQ LIVE CONFIG v12 — patch IFix hook LFramework.get_frameSynchr
//
// Pham vi: CHI dieu khien cac toggle doc tu nvh_aov.txt
//   esp / bp / aim / tmode / lines / draw / smite / smt / zoom
//
// SKIN KHONG nam trong patch nay. Doi skin bang lenh chat /skin <0..99>
// trong tran — payload goc goi thang ChangeActorMesh nen model doi NGAY,
// con duong ghi prefs thi chi co tac dung luc game dung lai mesh. Hai duong
// ghi cung mot key se de len nhau, nen patch co tinh KHONG dung toi skin.
//
// BANG CHUNG TU BAN v7 (logs 13:54 / 14:01):
//   iFix.HB.Loaded = 1, iFix.HB.Calls = 1896  -> hook CHAY.
//   NHUNG iFix.Cfg.* / iFix.Detect.* khong bao gio xuat hien
//   => khoi doc config nam SAU bo dem throttle khong he chay.
//
// v8 SUA GOC:
//   - BO field __mTick. Throttle dung CHINH __mCalls (field duy nhat da
//     chung minh song): if (__mCalls % 20 != 0) return fs;
//   - BO field __mPath (string). Duong dan lay tu Environment.GetEnvironmentVariable
//     ("HOME") — API thuan .NET, KHONG can main thread, KHONG bi Unity chan.
//   - BO field __mRev / __mProbeReq / __mProbeDone. Trang thai giu trong
//     PlayerPrefs cua chinh process game (doc/ghi in-process = tuc thi).
//   - Ap config MOI lan xu ly (khong so rev) -> doi la an trong ~0.3s.
//   - Tra ket qua bang FILE (khong qua cfprefsd):
//        <Documents>/nvh_step.txt   S1..S5/S2/S9 = diem dung khung doc config
//        <Documents>/nvh_where.txt  duong dan config that patch dang doc
//        <Documents>/nvh_hb.txt     nhip tim B0/B1 (dung im = hook khong chay)
//
// File app ghi (doc moi ~0.3s):
//   rev= probe= esp= bp= aim= tmode= lines= draw= smite= smt= zoom=
//
// Prefs patch ghi ra (app doc):
//   iFix.HB.Loaded=1  iFix.HB.Calls=<n>

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

        // ---- field moi: DUY NHAT 1 field int, da chung minh song ----
        public int __mCalls;

        public LFrameSynchr get_frameSynchr()
        {
            LFrameSynchr fs = _frameSynchr;

            try
            {
                __mCalls = __mCalls + 1;
                if ((__mCalls % 20) != 0) return fs;

                // ---------- thu muc that cua game (khong dung API Unity) ----------
                string home = null;
                try { home = System.Environment.GetEnvironmentVariable("HOME"); } catch (Exception) { }
                if (home == null || home.Length == 0)
                {
                    try { home = Application.persistentDataPath; } catch (Exception) { }
                }
                if (home == null || home.Length == 0) return fs;

                string dir = home + "/Documents";

                // thu ghi marker: Documents cua game -> /var/mobile/Documents -> Media
                string good = null;
                try
                {
                    System.IO.File.WriteAllText(dir + "/nvh_step.txt", "S1");
                    good = dir;
                }
                catch (Exception) { }
                if (good == null)
                {
                    try
                    {
                        System.IO.File.WriteAllText("/var/mobile/Documents/nvh_step.txt", "S1");
                        good = "/var/mobile/Documents";
                    }
                    catch (Exception) { }
                }
                if (good == null)
                {
                    try
                    {
                        System.IO.File.WriteAllText("/var/mobile/Media/nvh_step.txt", "S1");
                        good = "/var/mobile/Media";
                    }
                    catch (Exception) { }
                }
                if (good == null) return fs;

                try { System.IO.File.WriteAllText(good + "/nvh_where.txt", good); } catch (Exception) { }

                // ---------- tim file config: uu tien thu muc vua ghi duoc ----------
                string cfg = null;
                string c1 = dir + "/nvh_aov.txt";
                string c2 = "/var/mobile/Documents/nvh_aov.txt";
                string c3 = "/var/mobile/Media/nvh_aov.txt";
                string c4 = good + "/nvh_aov.txt";

                if (System.IO.File.Exists(c1)) cfg = c1;
                if (cfg == null && System.IO.File.Exists(c4)) cfg = c4;
                if (cfg == null && System.IO.File.Exists(c2)) cfg = c2;
                if (cfg == null && System.IO.File.Exists(c3)) cfg = c3;
                if (cfg == null)
                {
                    try { System.IO.File.WriteAllText(good + "/nvh_step.txt", "S2"); } catch (Exception) { }
                    return fs;
                }

                try { System.IO.File.WriteAllText(good + "/nvh_step.txt", "S3"); } catch (Exception) { }
                try { System.IO.File.WriteAllText(good + "/nvh_where.txt", cfg); } catch (Exception) { }

                string t = null;
                try { t = System.IO.File.ReadAllText(cfg); } catch (Exception) { }
                if (t == null || t.Length == 0)
                {
                    try { System.IO.File.WriteAllText(good + "/nvh_step.txt", "S31"); } catch (Exception) { }
                    return fs;
                }
                try { System.IO.File.WriteAllText(good + "/nvh_step.txt", "S4"); } catch (Exception) { }

                // ---------- ap config -> prefs cua chinh process game ----------
                {
                    int p;
                    int e;
                    string s;
                    int v;

                    p = t.IndexOf("esp=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 4, e - p - 4) : t.Substring(p + 4);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.ESP.Enabled.v1", v);
                    }

                    p = t.IndexOf("bp=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 3, e - p - 3) : t.Substring(p + 3);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoBP.Enabled.v1", v);
                    }

                    p = t.IndexOf("aim=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 4, e - p - 4) : t.Substring(p + 4);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AIM.Enabled.v1", v);
                    }

                    p = t.IndexOf("tmode=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AIM.TargetMode.v1", v);
                    }

                    p = t.IndexOf("lines=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AIM.Lines.v1", v);
                    }

                    p = t.IndexOf("draw=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 5, e - p - 5) : t.Substring(p + 5);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AIM.DrawMode.v1", v);
                    }

                    p = t.IndexOf("smite=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoSmite.Enabled.v1", v);
                    }

                    p = t.IndexOf("smt=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 4, e - p - 4) : t.Substring(p + 4);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoSmite.TargetMode.v1", v);
                    }

                    p = t.IndexOf("zoom=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 5, e - p - 5) : t.Substring(p + 5);
                        float f;
                        if (float.TryParse(s.Trim(), out f))
                            PlayerPrefs.SetFloat("iFix.Camera.Zoom.v1", f);
                    }

                    // SKIN: KHONG xu ly o day. Doi skin bang lenh chat /skin <n>
                    // trong tran (payload goc tu goi ChangeActorMesh ngay -> thay lien).
                    // Neu patch cung ghi iFix.SelectedSkin.v1.* thi se de len lua
                    // chon cua chat -> bo hoan toan.
                }

                PlayerPrefs.SetInt("iFix.HB.Loaded", 1);
                PlayerPrefs.SetInt("iFix.HB.Calls", __mCalls);
                PlayerPrefs.Save();
                try { System.IO.File.WriteAllText(good + "/nvh_step.txt", "S5"); } catch (Exception) { }
                // Nhip tim: KHONG dung ToString (IFix resolve sai, tra "True").
                // Ghi chuoi hang luan phien theo tick -> app thay doi = patch dang chay.
                try
                {
                    int beat = (__mCalls / 20) % 2;
                    System.IO.File.WriteAllText(good + "/nvh_hb.txt", (beat == 0) ? "B0" : "B1");
                }
                catch (Exception) { }
            }
            catch (Exception)
            {
                // nuot het — khong cho exception lan ra duong goi cua game
                try { System.IO.File.WriteAllText("/var/mobile/Documents/nvh_step.txt", "S9"); } catch (Exception) { }
            }

            return fs;
        }
    }
}

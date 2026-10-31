// NVH LQ LIVE CONFIG v8 — patch IFix hook LFramework.get_frameSynchr
//
// BANG CHUNG TU BAN v7 (logs 13:54 / 14:01):
//   iFix.HB.Loaded = 1, iFix.HB.Calls = 1896  -> hook CHAY.
//   NHUNG iFix.Cfg.* va iFix.Detect.* KHONG BAO GIO xuat hien.
//   => khoi doc config nam SAU bo dem throttle khong he chay.
//
// v8 SUA GOC:
//   - BO field __mTick. Throttle dung CHINH __mCalls (field duy nhat da
//     chung minh song): if (__mCalls % 20 != 0) return fs;
//     => khong con phu thuoc field moi de bi game ghi de moi frame.
//   - BO field __mPath (string). Duong dan lay tu Environment.GetEnvironmentVariable
//     ("HOME") — API thuan .NET, KHONG can main thread, KHONG bi Unity chan.
//     Chi khi HOME rong moi fallback Application.persistentDataPath.
//   - BO field __mRev / __mProbeReq / __mProbeDone. Trang thai giu trong
//     PlayerPrefs cua chinh process game (doc/ghi in-process = tuc thi).
//   - Ap config MOI lan xu ly (khong so rev) -> doi la an trong ~0.3s.
//   - Tra ket qua bang FILE (khong qua cfprefsd):
//        <Documents>/nvh_step.txt    S1..S9  = diem dung cua khung doc config
//        <Documents>/nvh_where.txt   thu muc that patch dang dung
//        <Documents>/nvh_detect.txt  D0..D7/DOK/DERR = diem dung khi do tuong
//        <Documents>/nvh_skin.txt    ten skin, ngan cach '|'
//     Van ghi prefs (iFix.Detect.Hero/Skin/Count, iFix.HB.Calls) lam kenh phu.
//
// File app ghi (doc moi ~0.3s):
//   rev= probe= esp= bp= aim= tmode= lines= draw= smite= smt= zoom= skin=<hero>:<model>
//
// Prefs patch ghi ra (app doc):
//   iFix.HB.Loaded=1  iFix.HB.Calls=<n>
//   iFix.Detect.Hero / Skin / Count (int)   iFix.Detect.Names (string, '|')

using System;
using UnityEngine;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

public struct PoolObjHandle<T>
{
    public uint _handleSeq;
    public T _handleObj;
    public bool HasValue { get { return false; } }
    public T handle { get { return default(T); } }
}

namespace Kyrios.Actor
{
    public class ActorLinker
    {
        public uint ConfigId { get { return 0; } }
    }
}

namespace Assets.Scripts.GameLogic.GameKernal
{
    // CHU Y: GameKernal la NAMESPACE trong game, khong phai class.
    public class Player
    {
        public PoolObjHandle<Kyrios.Actor.ActorLinker> CaptainLinker;
    }
}

namespace Kyrios
{
    public class VHostLogic
    {
        public Assets.Scripts.GameLogic.GameKernal.Player get_hostPlayer() { return null; }
    }

    public class KyriosFramework
    {
        public static VHostLogic get_hostLogic() { return null; }
    }
}

namespace ResData
{
    public class ResHeroSkin
    {
        public string szSkinName;
    }
}

namespace Assets.Scripts.GameSystem
{
    public static class CSkinInfo
    {
        public static uint GetWearSkinID(uint heroId) { return 0; }
        public static ResData.ResHeroSkin GetHeroSkin(uint heroId, uint skinId) { return null; }
    }
}

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
                int probeReq = 0;

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

                    // SKIN: app ghi san KEY dang CHUOI vao config
                    //     skinkey=iFix.SelectedSkin.v1.<hero>
                    //     skinmodel=<n>
                    // Patch chi doc chuoi — KHONG ghep so (Int32::ToString
                    // trong IFix patch resolve sai -> tra "True").
                    p = t.IndexOf("skinmodel=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 10, e - p - 10) : t.Substring(p + 10);
                        int model;
                        if (int.TryParse(s.Trim(), out model))
                        {
                            int kp = t.IndexOf("skinkey=");
                            if (kp >= 0)
                            {
                                int ke = t.IndexOf('\n', kp);
                                string keyStr = (ke > kp)
                                    ? t.Substring(kp + 8, ke - kp - 8)
                                    : t.Substring(kp + 8);
                                keyStr = keyStr.Trim();
                                if (keyStr.Length > 0)
                                    PlayerPrefs.SetInt(keyStr, model);
                            }
                        }
                    }

                    p = t.IndexOf("probe=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        int.TryParse(s.Trim(), out probeReq);
                    }
                }

                PlayerPrefs.SetInt("iFix.HB.Loaded", 1);
                PlayerPrefs.SetInt("iFix.HB.Calls", __mCalls);
                PlayerPrefs.Save();
                try { System.IO.File.WriteAllText(good + "/nvh_step.txt", "S5"); } catch (Exception) { }

                // ================= do tuong (chi khi app yeu cau) =================
                int probeDone = PlayerPrefs.GetInt("iFix.Cfg.Probe", 0);
                if (probeReq != probeDone && probeReq > 0)
                {
                    PlayerPrefs.SetInt("iFix.Cfg.Probe", probeReq);

                    string stage = "D0";
                    int dHero = 0;
                    int dSkin = 0;
                    int dCount = 0;
                    string dNames = "";

                    try
                    {
                        Kyrios.VHostLogic host = Kyrios.KyriosFramework.get_hostLogic();
                        stage = "D1";
                        if (host != null)
                        {
                            Assets.Scripts.GameLogic.GameKernal.Player pl = host.get_hostPlayer();
                            stage = "D2";
                            if (pl != null)
                            {
                                PoolObjHandle<Kyrios.Actor.ActorLinker> cap = pl.CaptainLinker;
                                stage = "D3";
                                if (cap.HasValue)
                                {
                                    stage = "D4";
                                    Kyrios.Actor.ActorLinker al = cap.handle;
                                    if (al != null)
                                    {
                                        stage = "D5";
                                        uint heroId = al.ConfigId;
                                        stage = "D6";
                                        if (heroId > 0U && heroId < 100000U)
                                        {
                                            uint wear = Assets.Scripts.GameSystem.CSkinInfo
                                                .GetWearSkinID(heroId);
                                            stage = "D7";
                                            dHero = (int)heroId;
                                            dSkin = (int)wear;

                                            uint si = 0U;
                                            string prevName = "";
                                            while (si < 8U)
                                            {
                                                ResData.ResHeroSkin rs = Assets.Scripts.GameSystem
                                                    .CSkinInfo.GetHeroSkin(heroId, si);
                                                if (rs == null) break;
                                                string nm = rs.szSkinName;
                                                if (nm == null || nm.Length == 0) break;
                                                if (nm == prevName) break;
                                                prevName = nm;
                                                if (dCount > 0) dNames += "|";
                                                dNames += nm;
                                                dCount++;
                                                si++;
                                            }
                                            stage = "DOK";
                                        }
                                    }
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        stage = "DERR";
                        try { PlayerPrefs.SetString("iFix.Detect.Err", ex.GetType().Name); } catch (Exception) { }
                    }

                    try
                    {
                        PlayerPrefs.SetString("iFix.Detect.Stage", stage);
                        PlayerPrefs.SetInt("iFix.Detect.Hero", dHero);
                        PlayerPrefs.SetInt("iFix.Detect.Skin", dSkin);
                        PlayerPrefs.SetInt("iFix.Detect.Count", dCount);
                        PlayerPrefs.SetString("iFix.Detect.Names", dNames);
                        PlayerPrefs.Save();
                    }
                    catch (Exception) { }

                    try { System.IO.File.WriteAllText(good + "/nvh_detect.txt", stage); } catch (Exception) { }
                    try
                    {
                        if (dNames.Length > 0)
                            System.IO.File.WriteAllText(good + "/nvh_skin.txt", dNames);
                    }
                    catch (Exception) { }
                }
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

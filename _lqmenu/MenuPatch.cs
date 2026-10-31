// NVH LQ LIVE CONFIG v7 — patch IFix hook LFramework.get_frameSynchr
//
// BANG CHUNG TU BAN DO HB (615880d):
//   iFix.HB.Calls = 228 -> 841 -> DUNG.
//   => hook CO chay luc lobby, roi khi vao tran bi goi tu THREAD KHAC.
//   Bo loc "chi thread chinh" (L1) da chan sach moi thu ben trong
//   (detection + ca viec doc config trong tran).
//
// v7 SUA GOC:
//   - BO hoan toan bo loc thread va bo moi API Unity can main-thread
//     (Input / Time / Application goi lap). Chi dung:
//        * duong dan cache 1 lan (lan goi dau, tuong duong lobby/main)
//        * System.IO.File  (doc config, ghi log phu)
//        * PlayerPrefs     (Set/Get/Save — an toan da luong)
//     => chay duoc tren thread frame-sync ma khong treo.
//   - Throttle bang BO DEM thay vi dong ho: cu 20 lan goi xu ly 1 lan.
//   - Detection ghi ket qua bang PREF KIEM SO (SetInt/SetString) —
//     khong noi so vao chuoi (Int32::ToString trong IFix patch tra "True").
//
// File nvh_aov.txt (app ghi):
//   rev=<n> probe=<n> esp= bp= aim= tmode= lines= draw= smite= smt= zoom= skin=<hero>:<model>
//
// Prefs patch ghi ra (app doc):
//   iFix.HB.Loaded=1  iFix.HB.Calls=<n>
//   iFix.Detect.Stage=<s0..s7|ok|err:Loai>
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

        // ---- field moi ----
        public int    __mCalls;     // so lan hook duoc goi (khong loc thread)
        public int    __mTick;      // bo dem throttle (thay cho dong ho)
        public int    __mRev;       // rev config da ap
        public int    __mProbeReq;  // yeu cau do tuong tu app
        public int    __mProbeDone; // da do xong so hieu nao
        public string __mPath;      // duong dan config, cache 1 lan

        public LFrameSynchr get_frameSynchr()
        {
            LFrameSynchr fs = _frameSynchr;

            try
            {
                __mCalls = __mCalls + 1;

                // cache duong dan 1 lan (lan goi dau — khong lap lai API nay)
                if (__mPath == null)
                {
                    try
                    {
                        __mPath = Application.persistentDataPath + "/nvh_aov.txt";
                    }
                    catch (Exception) { }
                }
                if (__mPath == null) return fs;

                // heartbeat: chi ghi RAM moi frame, Save moi 60 lan
                try
                {
                    if (__mCalls == 1)
                    {
                        PlayerPrefs.SetInt("iFix.HB.Loaded", 1);
                    }
                    PlayerPrefs.SetInt("iFix.HB.Calls", __mCalls);
                    if ((__mCalls % 60) == 0) PlayerPrefs.Save();
                }
                catch (Exception) { }

                // throttle: cu 20 lan goi moi xu ly 1 lan
                __mTick = __mTick + 1;
                if ((__mTick % 20) != 0) return fs;

                // ================= doc live config =================
                // May do: ghi so hieu buoc vao iFix.Cfg.Step de biet chan o dau
                //   1 = qua throttle | 2 = File.Exists FALSE | 3 = co file
                //   4 = doc xong | 5 = rev doi | 6 = da ap key | 7 = da doc probe
                //   99 = exception (xem iFix.Cfg.Err)
                string cfgPath = __mPath;
                try
                {
                    PlayerPrefs.SetInt("iFix.Cfg.Step", 1);
                    bool hasFile = System.IO.File.Exists(cfgPath);
                    if (!hasFile)
                    {
                        PlayerPrefs.SetInt("iFix.Cfg.Step", 2);
                        PlayerPrefs.Save();
                        return fs;
                    }
                    PlayerPrefs.SetInt("iFix.Cfg.Step", 3);

                    string t = System.IO.File.ReadAllText(cfgPath);
                    if (t == null || t.Length == 0)
                    {
                        PlayerPrefs.SetInt("iFix.Cfg.Step", 31);
                        PlayerPrefs.Save();
                        return fs;
                    }
                    PlayerPrefs.SetInt("iFix.Cfg.Step", 4);

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
                    if (rev == __mRev)
                    {
                        PlayerPrefs.SetInt("iFix.Cfg.Step", 41);   // rev chua doi
                        PlayerPrefs.Save();
                        return fs;
                    }
                    __mRev = rev;
                    PlayerPrefs.SetInt("iFix.Cfg.Step", 5);

                    {
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
                    }
                    PlayerPrefs.SetInt("iFix.Cfg.Step", 6);

                    p = t.IndexOf("probe=");
                    if (p >= 0)
                    {
                        int e = t.IndexOf('\n', p);
                        string s = (e > p) ? t.Substring(p + 6, e - p - 6)
                                           : t.Substring(p + 6);
                        int v;
                        if (int.TryParse(s.Trim(), out v)) __mProbeReq = v;
                    }
                    PlayerPrefs.SetInt("iFix.Cfg.Step", 7);
                    PlayerPrefs.Save();
                }
                catch (Exception ex)
                {
                    try
                    {
                        PlayerPrefs.SetInt("iFix.Cfg.Step", 99);
                        PlayerPrefs.SetString("iFix.Cfg.Err", ex.GetType().Name);
                        PlayerPrefs.Save();
                    }
                    catch (Exception) { }
                    return fs;
                }

                // ================= do tuong (chi khi app yeu cau) =================
                if (__mProbeReq != __mProbeDone)
                {
                    __mProbeDone = __mProbeReq;

                    string stage = "s0";
                    int dHero = 0;
                    int dSkin = 0;
                    int dCount = 0;
                    string dNames = "";

                    try
                    {
                        Kyrios.VHostLogic host = Kyrios.KyriosFramework.get_hostLogic();
                        stage = "s1";
                        if (host != null)
                        {
                            Assets.Scripts.GameLogic.GameKernal.Player pl = host.get_hostPlayer();
                            stage = "s2";
                            if (pl != null)
                            {
                                PoolObjHandle<Kyrios.Actor.ActorLinker> cap = pl.CaptainLinker;
                                stage = "s3";
                                if (cap.HasValue)
                                {
                                    stage = "s4";
                                    Kyrios.Actor.ActorLinker al = cap.handle;
                                    if (al != null)
                                    {
                                        stage = "s5";
                                        uint heroId = al.ConfigId;
                                        stage = "s6";
                                        if (heroId > 0U && heroId < 100000U)
                                        {
                                            uint wear = Assets.Scripts.GameSystem.CSkinInfo
                                                .GetWearSkinID(heroId);
                                            stage = "s7";
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
                                            stage = "ok";
                                        }
                                    }
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        stage = "err:" + ex.GetType().Name;
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

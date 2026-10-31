// NVH LQ LIVE CONFIG v15 — patch IFix hook LFramework.get_frameSynchr
//
// Pham vi: CHI dieu khien cac toggle doc tu nvh_aov.txt
//   esp / bp / aim / tmode / lines / draw / smite / smt / zoom / wearskin / killfx
//
// v15 — HIEU UNG DIET (banner thong bao diet di kem skin):
//   Nut chieu doc CRoleInfo.dwShowSkinID (v14 da chay). Banner diet thi KHONG:
//   KillNotify3D / KillNotifyUT co cache RIENG, key theo (playId -> skinId)
//   va (skinId -> ResBillboardCfg):
//       KillNotifyUT.CacheNotifySkinIDMap / AddCacheNotifySkinIDMap(playId, skinId)
//       KillNotifyUT.CacheTextSkinBillBoardDict / AddCacheSkinBillBoardDict(skinId)
//   => nguon skin cho banner la du lieu SERVER cua actor, khong phai field
//   dwShowSkinID. v15 thu: tu minh nap cache do bang chinh ham cua game, va
//   ghi lai chan doan de biet con thieu gi:
//       iFix.KF.*  (prefs: SkinID / MyPlayerId / Broadcast / PersonalBtn / BbCount / BbMax)
//       nvh_where.txt  -> dong "KF:......" = co flag nao resolve duoc
//   Bat/tat bang killfx= trong nvh_aov.txt (0/1) — tat thi khong goi gi ca.
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

namespace Assets.Scripts.GameSystem
{
    // Ground truth tu dump.cs (LQ 1.64.1.7):
    //   CRoleInfo:        public uint dwShowSkinID; // 0x26C
    //   CRoleInfoManager: Singleton<CRoleInfoManager>, CRoleInfo GetMasterRoleInfo()
    // Day la field ma he thong NUT CHIEU / thong bao diet doc de chon skin
    // (PersonalButton::get_PersonalBtnId doc thang field, KHONG qua ham).
    public class CRoleInfo
    {
        public uint dwShowSkinID;
        public uint dwShowHeroID;                // 0x268
        public ulong get_playerUllUID() { return 0; }
    }

    public class CRoleInfoManager
    {
        public static CRoleInfoManager GetInstance() { return null; }
        public CRoleInfo GetMasterRoleInfo() { return null; }
    }

    // CSkinInfo::GetHeroSkinID(heroId, skinIndex) -> skin id TOAN CUC.
    public class CSkinInfo
    {
        public static uint GetHeroSkinID(uint heroId, uint skinId) { return 0; }
    }

    // KillNotifyUT (TypeDefIndex 7086) — cache cua he thong banner diet.
    public class KillNotifyUT
    {
        public static void AddCacheNotifySkinIDMap(uint playId, uint skinId) { }
        public static void AddCacheSkinBillBoardDict(uint skinId) { }
    }
}

namespace Kyrios
{
    public class KyriosFramework
    {
        public static NucleusDrive.Logic.GameKernal.GamePlayerCenter get_playerCenter() { return null; }
    }
}

namespace NucleusDrive.Logic.GameKernal
{
    public class GamePlayerCenter
    {
        public LDataProvider.PlayerBase GetPlayer(uint inPlayerID) { return null; }
        public LDataProvider.PlayerBase GetPlayerByUid(ulong uid) { return null; }
        public System.Collections.Generic.List<LDataProvider.PlayerBase> GetAllPlayers() { return null; }
    }
}

namespace LDataProvider
{
    // PlayerBase (TypeDefIndex 10735) — du lieu nguoi choi ma server gui xuong.
    // broadcastID / PersonalButtonID la lua chon "bao bao" + "nut chieu" cua
    // tung nguoi; banner diet doc tu day, KHONG doc tu CRoleInfo.
    public class PlayerBase
    {
        public uint PlayerId;            // 0x8
        public ulong PlayerUId;          // 0x18
        public int broadcastID;          // 0xFC
        public int PersonalButtonID;     // 0x104
        public uint GameStartSkin;       // 0x15C
        public uint GameOverSkin;        // 0x160
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

                    // SKIN NAP TRUOC TRAN:
                    //   wearskin=<0..99>   0 = tat
                    // Khong ghi iFix.SelectedSkin.v1.* (do la lua chon cua UI
                    // /skin trong tran). Gia tri nay ghi vao iFix.WearSkin.v1 va
                    // duoc ap vao CRoleInfo.dwShowSkinID ngay ben duoi.
                    p = t.IndexOf("wearskin=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 9, e - p - 9) : t.Substring(p + 9);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.WearSkin.v1", v);
                    }

                    // killfx=<0|1>  bat thi patch tu nap cache banner diet
                    p = t.IndexOf("killfx=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 7, e - p - 7) : t.Substring(p + 7);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.KillFx.v1", v);
                    }
                }

                // ---- ap skin nap truoc tran vao field game dung de chon NUT ----
                // PersonalButton::get_PersonalBtnId so dwShowSkinID voi danh sach
                // skin cua tuong -> quyet dinh bo nut chieu nao duoc dung.
                // Chi ghi khi lech gia tri (do la store du moi tick).
                try
                {
                    int wear = PlayerPrefs.GetInt("iFix.WearSkin.v1", 0);
                    if (wear > 0)
                    {
                        Assets.Scripts.GameSystem.CRoleInfoManager mgr =
                            Assets.Scripts.GameSystem.CRoleInfoManager.GetInstance();
                        if (mgr != null)
                        {
                            Assets.Scripts.GameSystem.CRoleInfo ri = mgr.GetMasterRoleInfo();
                            if (ri != null && ri.dwShowSkinID != (uint)wear)
                            {
                                ri.dwShowSkinID = (uint)wear;
                            }
                        }
                    }
                }
                catch (Exception) { }

                // ---- HIEU UNG DIET: chan doan + nap cache banner ----
                // Banner diet (KillNotify3D/KillNotifyUT) KHONG doc dwShowSkinID
                // ma doc cache rieng theo (playId -> skinId) va (skinId -> billboard).
                // Cache do game nap tu du lieu SERVER cua actor, nen hack local
                // phai tu nap lai. Buoc 1 la chan doan: resolve "minh" va ghi lai
                // broadcastID that cua minh + cua ca tran (so sanh la biet thieu gi).
                //   prefs:  iFix.KF.MyId / SkinID / Broadcast / PersonalBtn
                //           iFix.KF.BbCount / BbMax
                //   file :  nvh_kf.txt = "KF:CMUS-BP F" (chu nao resolve duoc)
                try
                {
                    Assets.Scripts.GameSystem.CRoleInfoManager kfMgr =
                        Assets.Scripts.GameSystem.CRoleInfoManager.GetInstance();
                    Assets.Scripts.GameSystem.CRoleInfo kfRi =
                        (kfMgr != null) ? kfMgr.GetMasterRoleInfo() : null;

                    if (kfRi == null)
                    {
                        try { System.IO.File.WriteAllText(good + "/nvh_kf.txt", "KF:nori"); } catch (Exception) { }
                    }
                    else
                    {
                        ulong kfUid = 0;
                        try { kfUid = kfRi.get_playerUllUID(); } catch (Exception) { }

                        NucleusDrive.Logic.GameKernal.GamePlayerCenter kfPc = null;
                        try { kfPc = Kyrios.KyriosFramework.get_playerCenter(); } catch (Exception) { }

                        string kfFlag = "KF:";
                        kfFlag = kfFlag + ((kfPc != null) ? "C" : "-") + ((kfUid != 0) ? "U" : "-");

                        LDataProvider.PlayerBase kfMe = null;
                        if (kfPc != null && kfUid != 0)
                        {
                            try { kfMe = kfPc.GetPlayerByUid(kfUid); } catch (Exception) { }
                        }
                        kfFlag = kfFlag + ((kfMe != null) ? "M" : "-");

                        int kfWear = PlayerPrefs.GetInt("iFix.WearSkin.v1", 0);
                        uint kfSkin = 0;
                        if (kfWear > 0)
                        {
                            try
                            {
                                kfSkin = Assets.Scripts.GameSystem.CSkinInfo.GetHeroSkinID(
                                    kfRi.dwShowHeroID, (uint)kfWear);
                            }
                            catch (Exception) { }
                        }
                        kfFlag = kfFlag + ((kfSkin != 0) ? "S" : "-");
                        PlayerPrefs.SetInt("iFix.KF.SkinID", (int)kfSkin);

                        if (kfMe != null)
                        {
                            PlayerPrefs.SetInt("iFix.KF.MyId", (int)kfMe.PlayerId);
                            PlayerPrefs.SetInt("iFix.KF.Broadcast", kfMe.broadcastID);
                            PlayerPrefs.SetInt("iFix.KF.PersonalBtn", kfMe.PersonalButtonID);
                            PlayerPrefs.SetInt("iFix.KF.StartSkin", (int)kfMe.GameStartSkin);
                            kfFlag = kfFlag + ((kfMe.broadcastID != 0) ? "B" : "-")
                                            + ((kfMe.PersonalButtonID != 0) ? "P" : "-");
                        }

                        // ca tran: co bao nhieu nguoi co broadcastID != 0, va gia tri
                        // lon nhat la bao nhieu -> biet "mien gia tri" cua billboard id
                        try
                        {
                            if (kfPc != null)
                            {
                                System.Collections.Generic.List<LDataProvider.PlayerBase> kfAll =
                                    kfPc.GetAllPlayers();
                                int kfCnt = 0;
                                int kfMax = 0;
                                if (kfAll != null)
                                {
                                    int kfN = kfAll.Count;
                                    for (int kfI = 0; kfI < kfN; kfI++)
                                    {
                                        LDataProvider.PlayerBase kfPb = kfAll[kfI];
                                        if (kfPb == null) continue;
                                        if (kfPb.broadcastID != 0)
                                        {
                                            kfCnt = kfCnt + 1;
                                            if (kfPb.broadcastID > kfMax) kfMax = kfPb.broadcastID;
                                        }
                                    }
                                }
                                PlayerPrefs.SetInt("iFix.KF.BbCount", kfCnt);
                                PlayerPrefs.SetInt("iFix.KF.BbMax", kfMax);
                            }
                        }
                        catch (Exception) { }

                        // nap cache banner bang CHINH ham cua game (3s/lan)
                        if (PlayerPrefs.GetInt("iFix.KillFx.v1", 0) == 1
                            && kfMe != null && kfSkin != 0 && ((__mCalls % 180) == 0))
                        {
                            try
                            {
                                Assets.Scripts.GameSystem.KillNotifyUT.AddCacheNotifySkinIDMap(
                                    kfMe.PlayerId, kfSkin);
                                Assets.Scripts.GameSystem.KillNotifyUT.AddCacheSkinBillBoardDict(kfSkin);
                                kfFlag = kfFlag + "F";
                            }
                            catch (Exception) { }
                        }

                        try { System.IO.File.WriteAllText(good + "/nvh_kf.txt", kfFlag); } catch (Exception) { }
                    }
                }
                catch (Exception) { }

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

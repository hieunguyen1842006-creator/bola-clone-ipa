// NVH LQ LIVE CONFIG v17 — 2 hook IFix:
//   1. NucleusDrive.Logic.LFramework::get_frameSynchr()  (Project.Plugins_d)
//      -> doc nvh_aov.txt, ap vao PlayerPrefs (esp/bp/aim/tmode/lines/draw/
//         smite/smt/zoom + ban)
//   2. LDataProvider.PlayerBase::IsAtMyTeam(Int32,Int32)  (Project.Plugins_d)
//      -> ghi broadcastID (banner thong bao diet) + GameStartSkin theo skin
//         dang mac thật của chính host player.
//
// BANG CHUNG cho hook 2 (goi tham chieu "LQ NS\THÔNG BÁO HẠ NÚT BẤM"):
//   - PersonalButton::IsOpen() doi thanh `return true`  -> da co o HS1 (v13)
//   - PlayerBase::IsAtMyTeam(int,int) la cho duy nhat ghi PlayerBase.broadcastID
//     + PersonalButtonID + GameStartSkin (bang skin->id, khong tao banner gia,
//     khong goi KillNotifySkinMono.Show).
//   - PlayerBase (TypeDefIndex 10735, dump 1.64.1.7):
//       uint PlayerId        @0x8
//       int  broadcastID     @0xFC   <- banner diet
//       int  PersonalButtonID@0x104
//       uint GameStartSkin   @0x15C
//       List<uint> _heroIds  @0x170
//   - Ket qua team KHONG the goi lai ham goc (IFix thay than ham) nen phai
//     viet lai dung logic 1.64.1; day la phan rui ro nhat, xem cuoi ham.
//
// ESP QUAI (mon=) DA GO: ban v16/v16b/v16c lam game dung khi dang load.
// Se lam lai sau bang duong minimap (Set3DUIWorldPos_ByScreenPoint).
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
using System.Collections.Generic;

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

                    // cac nguong cua khoi auto chen trong vm3 (merge_menu.py doc)
                    p = t.IndexOf("bppct=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoBP.Pct.v1", v);
                    }

                    p = t.IndexOf("smthp=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoSmite.Hp.v1", v);
                    }

                    p = t.IndexOf("ice=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 4, e - p - 4) : t.Substring(p + 4);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoIce.Enabled.v1", v);
                    }

                    p = t.IndexOf("icepct=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 7, e - p - 7) : t.Substring(p + 7);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoIce.Pct.v1", v);
                    }

                    // BANNER DIET: ban=<0|1> -> hook PlayerBase::IsAtMyTeam doc
                    p = t.IndexOf("ban=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 4, e - p - 4) : t.Substring(p + 4);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.Banner.v1", v);
                    }
                }

                // SKIN: KHONG xu ly o day. Doi skin bang lenh chat /skin <n>
                    // trong tran (payload goc tu goi ChangeActorMesh ngay -> thay lien).
                    // Neu patch cung ghi iFix.SelectedSkin.v1.* thi se de len lua
                    // chon cua chat -> bo hoan toan.

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

// ============================================================================
// BANNER DIET (v17) — hook LDataProvider.PlayerBase::IsAtMyTeam(Int32,Int32)
//
// IsAtMyTeam bi IFix THAY THAN, khong goi lai duoc ham goc. Nen:
//   * phan ghi metadata (broadcastID/GameStartSkin) nam TRONG ham nay
//   * cuoi ham phai TRA LAI dung ket qua team cua ban 1.64.1:
//         PlayerId != playerId            -> false
//         configId == 0                   -> true
//         _heroIds == null                -> false
//         !_heroIds.Contains(configId)    -> false
//         con lai                         -> true
//   Cac kieu duoi day chi la STUB de csc bien dich; IFix resolve theo
//   ten type + ten field/method that trong Project.Plugins_d / Project_d.
// ============================================================================

namespace Kyrios
{
    public class Player
    {
    }

    public class VHostLogic
    {
        public Player get_hostPlayer() { return null; }

        public uint get_HostPlayerId() { return 0; }
    }

    public class KyriosFramework
    {
        public static VHostLogic get_hostLogic() { return null; }
    }
}

namespace Assets.Scripts.GameSystem
{
    public class CSkinInfo
    {
        public static uint GetWearSkinID(uint heroId) { return 0; }

        public static uint GetHeroSkinID(uint heroId, uint skinId) { return 0; }
    }
}

namespace LDataProvider
{
    public class PlayerBase
    {
        // ---- field CO SAN cua game (KHONG khai trong process_cfg) ----
        public uint PlayerId;
        public int broadcastID;
        public int PersonalButtonID;
        public uint GameStartSkin;
        public List<uint> _heroIds;

        public bool IsAtMyTeam(int playerId, int configId)
        {
            // ---- ghi metadata banner diet cho dung host player ----
            try
            {
                if (PlayerPrefs.GetInt("iFix.Banner.v1", 1) != 0)
                {
                    if (this.PlayerId == (uint)playerId && configId > 0)
                    {
                        Kyrios.VHostLogic hl = Kyrios.KyriosFramework.get_hostLogic();
                        // dung 4 guard cua ban tham chieu (skin_presentation.py):
                        // hostLogic != null, hostPlayer != null, dung host id,
                        // dung player + hero thuoc danh sach cua player do.
                        if (hl != null && hl.get_hostPlayer() != null
                            && this.PlayerId == hl.get_HostPlayerId())
                        {
                            uint heroId = (uint)configId;
                            List<uint> myHeroes = this._heroIds;
                            if (myHeroes != null && myHeroes.Contains(heroId))
                            {
                                uint wear = Assets.Scripts.GameSystem.CSkinInfo.GetWearSkinID(heroId);
                                if (wear > 0)
                                {
                                    uint c = Assets.Scripts.GameSystem.CSkinInfo.GetHeroSkinID(heroId, wear);
                                    if (c > 0)
                                    {
                                    // Map UI thuần: khong goi SkillSlot/RequestUseSkill.
                                    // b = billboard/banner (65 dong), p = PersonalButtonID
                                    // (86 dong), nguon LQ NS skin_*_mapping.json.
                                    int b = 0;
                                    int p = 0;
                                    if (c == 14111u) p = 1;
                                    else if (c == 15212u) p = 2;
                                    else if (c == 19906u) p = 3;
                                    else if (c == 11115u) p = 4;
                                    else if (c == 11812u) p = 5;
                                    else if (c == 11614u) p = 6;
                                    else if (c == 11616u) p = 7;
                                    else if (c == 15711u) p = 8;
                                    else if (c == 19508u) p = 9;
                                    else if (c == 15012u) p = 10;
                                    else if (c == 13116u) p = 11;
                                    else if (c == 13015u) p = 12;
                                    else if (c == 15412u) p = 13;
                                    else if (c == 52011u) p = 14;
                                    else if (c == 15013u) p = 15;
                                    else if (c == 54307u) p = 16;
                                    else if (c == 15015u) p = 17;
                                    else if (c == 10620u) p = 19;
                                    else if (c == 13118u) p = 20;
                                    else if (c == 51015u) p = 21;
                                    else if (c == 59702u) p = 22;
                                    else if (c == 19015u) p = 23;
                                    else if (c == 13613u) p = 24;
                                    else if (c == 13314u) p = 25;
                                    else if (c == 11107u) p = 26;
                                    else if (c == 52414u) p = 27;
                                    else if (c == 59901u) p = 28;
                                    else if (c == 59802u) p = 29;
                                    else if (c == 10915u) p = 30;
                                    else if (c == 15413u) p = 31;
                                    else if (c == 50119u) p = 32;
                                    else if (c == 11620u) p = 33;
                                    else if (c == 11120u) p = 34;
                                    else if (c == 13706u) p = 35;
                                    else if (c == 10714u) p = 36;
                                    else if (c == 52113u) p = 37;
                                    else if (c == 50120u) p = 38;
                                    else if (c == 54805u) p = 39;
                                    else if (c == 19109u) p = 40;
                                    else if (c == 17408u) p = 42;
                                    else if (c == 12913u) p = 43;
                                    else if (c == 50108u) p = 44;
                                    else if (c == 11215u) p = 45;
                                    else if (c == 13213u) p = 46;
                                    else if (c == 15903u) p = 47;
                                    else if (c == 54507u) p = 48;
                                    else if (c == 52415u) p = 49;
                                    else if (c == 52908u) p = 50;
                                    else if (c == 15009u) p = 52;
                                    else if (c == 19908u) p = 53;
                                    else if (c == 53806u) p = 54;
                                    else if (c == 52809u) p = 55;
                                    else if (c == 59902u) p = 56;
                                    else if (c == 10713u) p = 57;
                                    else if (c == 16612u) p = 58;
                                    else if (c == 14214u) p = 59;
                                    else if (c == 54309u) p = 60;
                                    else if (c == 10916u) p = 61;
                                    else if (c == 12107u) p = 62;
                                    else if (c == 50613u) p = 63;
                                    else if (c == 15217u) p = 64;
                                    else if (c == 14120u) p = 65;
                                    else if (c == 15905u) p = 67;
                                    else if (c == 13316u) p = 68;
                                    else if (c == 10618u) p = 69;
                                    else if (c == 53612u) p = 70;
                                    else if (c == 17108u) p = 71;
                                    else if (c == 15016u) p = 72;
                                    else if (c == 52810u) p = 73;
                                    else if (c == 13707u) p = 74;
                                    else if (c == 19016u) p = 75;
                                    else if (c == 13215u) p = 76;
                                    else if (c == 14215u) p = 77;
                                    else if (c == 59602u) p = 78;
                                    else if (c == 59703u) p = 79;
                                    else if (c == 59903u) p = 80;
                                    else if (c == 10812u) p = 81;
                                    else if (c == 10917u) p = 82;
                                    else if (c == 54807u) p = 83;
                                    else if (c == 19111u) p = 84;
                                    else if (c == 12313u) p = 85;
                                    else if (c == 11122u) p = 89;
                                    else if (c == 52016u) p = 90;
                                    else if (c == 54508u) p = 91;
                                    else if (c == 52417u) p = 92;
                                    else if (c == 59501u) p = 93;

                                    if (c == 12910u) b = 1;
                                    else if (c == 13210u) b = 2;
                                    else if (c == 16710u) b = 3;
                                    else if (c == 15212u) b = 4;
                                    else if (c == 11812u) b = 5;
                                    else if (c == 19906u) b = 6;
                                    else if (c == 11616u) b = 7;
                                    else if (c == 19508u) b = 8;
                                    else if (c == 15012u) b = 9;
                                    else if (c == 15711u) b = 10;
                                    else if (c == 15412u) b = 11;
                                    else if (c == 13015u) b = 12;
                                    else if (c == 13116u) b = 13;
                                    else if (c == 17517u) b = 14;
                                    else if (c == 52011u) b = 15;
                                    else if (c == 15013u) b = 16;
                                    else if (c == 54307u) b = 17;
                                    else if (c == 15014u) b = 18;
                                    else if (c == 10620u) b = 19;
                                    else if (c == 15015u) b = 20;
                                    else if (c == 13118u) b = 21;
                                    else if (c == 10914u) b = 22;
                                    else if (c == 51015u) b = 23;
                                    else if (c == 59702u) b = 24;
                                    else if (c == 19015u) b = 25;
                                    else if (c == 13613u) b = 26;
                                    else if (c == 13314u) b = 27;
                                    else if (c == 11107u) b = 28;
                                    else if (c == 52414u) b = 29;
                                    else if (c == 53708u) b = 30;
                                    else if (c == 50119u) b = 31;
                                    else if (c == 11620u) b = 32;
                                    else if (c == 11120u) b = 33;
                                    else if (c == 13706u) b = 34;
                                    else if (c == 11215u) b = 35;
                                    else if (c == 13213u) b = 36;
                                    else if (c == 15306u) b = 37;
                                    else if (c == 50108u) b = 38;
                                    else if (c == 17408u) b = 42;
                                    else if (c == 52415u) b = 43;
                                    else if (c == 54805u) b = 44;
                                    else if (c == 15009u) b = 45;
                                    else if (c == 19614u) b = 46;
                                    else if (c == 19908u) b = 47;
                                    else if (c == 54507u) b = 48;
                                    else if (c == 14111u) b = 49;
                                    else if (c == 53806u) b = 50;
                                    else if (c == 52809u) b = 51;
                                    else if (c == 54309u) b = 52;
                                    else if (c == 16612u) b = 53;
                                    else if (c == 14214u) b = 54;
                                    else if (c == 10916u) b = 55;
                                    else if (c == 12107u) b = 56;
                                    else if (c == 13119u) b = 57;
                                    else if (c == 15217u) b = 58;
                                    else if (c == 19016u) b = 59;
                                    else if (c == 53612u) b = 60;
                                    else if (c == 15016u) b = 61;
                                    else if (c == 17108u) b = 62;
                                    else if (c == 12312u) b = 63;
                                    else if (c == 13215u) b = 64;
                                    else if (c == 12313u) b = 65;
                                    else if (c == 59903u) b = 66;
                                    else if (c == 10812u) b = 67;
                                    else if (c == 52417u) b = 68;

                                    this.GameStartSkin = c;
                                    this.PersonalButtonID = p;
                                    this.broadcastID = b;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception) { }

            // ---- ket qua team goc (logic 1.64.1) ----
            if (this.PlayerId != (uint)playerId) return false;
            if (configId == 0) return true;
            List<uint> ids = this._heroIds;
            if (ids == null) return false;
            return ids.Contains((uint)configId);
        }
    }
}

// NVH LQ LIVE CONFIG v13+MON — patch IFix hook LFramework.get_frameSynchr
//
// Pham vi: CHI dieu khien cac toggle doc tu nvh_aov.txt
//   esp / bp / aim / tmode / lines / draw / smite / smt / zoom / mon
// mon=1 -> chot danh sach MONSTER / SOLDIER / DRAGON tu ActorManager
//        va ghi ra nvh_monster.txt cho app hien thi (khong ve truc tiep —
//        ve overlay 2D phai qua LQHud payload quen thuoc tung client).
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

public struct PoolObjHandle<T> where T : class
{
}

namespace NucleusDrive.Logic
{
    public class LActorRoot
    {
        public void DummyMethod() { }
    }

    public class LGameActorMgr
    {
        // Ground truth (TypeDefIndex 11793):
        //   List<PoolObjHandle<LActorRoot>> MonsterActors   // 0x70
        //   List<PoolObjHandle<LActorRoot>> SoldierActors   // 0xA0
        //   List<PoolObjHandle<LActorRoot>> JungleMonsters  // 0xA8
        public List<PoolObjHandle<LActorRoot>> MonsterActors;
        public List<PoolObjHandle<LActorRoot>> SoldierActors;
        public List<PoolObjHandle<LActorRoot>> JungleMonsters;

        public List<PoolObjHandle<LActorRoot>> GetAllMonsters() { return null; }
        public List<PoolObjHandle<LActorRoot>> GetAllJungleMonsters() { return null; }
    }

    public class LFrameSynchr { }

    public class LBattleLogic
    {
        public LGameActorMgr get_gameActorMgr() { return null; }
    }

    public class LMainBattleLogic : LBattleLogic
    {
    }

    public class LFramework
    {
        public LMainBattleLogic get_mainBattleLogic() { return null; }

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

                    p = t.IndexOf("bppct=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoBP.Pct.v1", v);
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

                    p = t.IndexOf("edras=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.Edras.AutoCombo.On.v1", v);
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

                    p = t.IndexOf("smthp=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 6, e - p - 6) : t.Substring(p + 6);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.AutoSmite.Hp.v1", v);
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

                    // ESP QUAI VIEN (thử nghiệm): mon=<0|1>
                    p = t.IndexOf("mon=");
                    if (p >= 0)
                    {
                        e = t.IndexOf('\n', p);
                        s = (e > p) ? t.Substring(p + 4, e - p - 4) : t.Substring(p + 4);
                        if (int.TryParse(s.Trim(), out v))
                            PlayerPrefs.SetInt("iFix.ESP.Monster.v1", v);
                    }
                }

                // ---- ESP QUAI (số lượng từ vm3 CPlayerLocationStat::UpdateLogic + LGameActorMgr) ----
                // Hook CPlayerLocationStat::UpdateLogic (vm3) trên main thread đếm trực tiếp
                // ActorManager.MonsterActors / SoldierActors và số quái đang sống, rồi ghi vào
                // PlayerPrefs iFix.ESP.Monster.M / S / D đồng thời vẽ ESP quái (minimap + 3D box + tia + HP).
                // Tại đây ta đọc lại 3 prefs đó và xuất thẳng ra file <Documents>/nvh_mon.txt
                // để app đọc tức thì (không bị kẹt cache cfprefsd của iOS).
                {
                    try
                    {
                        NucleusDrive.Logic.LGameActorMgr gm = null;
                        try { gm = get_mainBattleLogic().get_gameActorMgr(); }
                        catch (Exception) { }

                        int cM = 0, cS = 0, cD = 0;
                        if (gm != null)
                        {
                            try { cM = (gm.MonsterActors != null) ? gm.MonsterActors.Count : 0; } catch (Exception) { }
                            try { cS = (gm.SoldierActors != null) ? gm.SoldierActors.Count : 0; } catch (Exception) { }
                            try { cD = (gm.JungleMonsters != null) ? gm.JungleMonsters.Count : 0; } catch (Exception) { }
                            try
                            {
                                if (cM == 0)
                                {
                                    List<PoolObjHandle<LActorRoot>> all = gm.GetAllMonsters();
                                    if (all != null) cM = all.Count;
                                }
                            }
                            catch (Exception) { }
                        }
                        if (cM > 0) PlayerPrefs.SetInt("iFix.ESP.Monster.M", cM);
                        if (cS > 0) PlayerPrefs.SetInt("iFix.ESP.Monster.S", cS);
                        if (cD > 0) PlayerPrefs.SetInt("iFix.ESP.Monster.D", cD);

                        int mVal = PlayerPrefs.GetInt("iFix.ESP.Monster.M", 0);
                        int sVal = PlayerPrefs.GetInt("iFix.ESP.Monster.S", 0);
                        int dVal = PlayerPrefs.GetInt("iFix.ESP.Monster.D", 0);
                        if (mVal < 0) mVal = 0;
                        if (mVal > 999) mVal = 999;
                        if (sVal < 0) sVal = 0;
                        if (sVal > 999) sVal = 999;
                        if (dVal < 0) dVal = 0;
                        if (dVal > 999) dVal = 999;

                        string digits = "0123456789";
                        string sm = digits.Substring(mVal % 10, 1);
                        if (mVal >= 10)
                        {
                            string d1 = digits.Substring((mVal / 10) % 10, 1);
                            sm = d1 + sm;
                        }
                        if (mVal >= 100)
                        {
                            string d2 = digits.Substring((mVal / 100) % 10, 1);
                            sm = d2 + sm;
                        }

                        string ss = digits.Substring(sVal % 10, 1);
                        if (sVal >= 10)
                        {
                            string d1 = digits.Substring((sVal / 10) % 10, 1);
                            ss = d1 + ss;
                        }
                        if (sVal >= 100)
                        {
                            string d2 = digits.Substring((sVal / 100) % 10, 1);
                            ss = d2 + ss;
                        }

                        string sd = digits.Substring(dVal % 10, 1);
                        if (dVal >= 10)
                        {
                            string d1 = digits.Substring((dVal / 10) % 10, 1);
                            sd = d1 + sd;
                        }
                        if (dVal >= 100)
                        {
                            string d2 = digits.Substring((dVal / 100) % 10, 1);
                            sd = d2 + sd;
                        }

                        string monLine = "Quái=";
                        monLine = monLine + sm;
                        monLine = monLine + " • Lính=";
                        monLine = monLine + ss;
                        monLine = monLine + " • Rồng=";
                        monLine = monLine + sd;
                        System.IO.File.WriteAllText(good + "/nvh_mon.txt", monLine);
                        System.IO.File.WriteAllText(good + "/nvh_ver.txt", "v18-smite-bp-ice");
                    }
                    catch (Exception) { }
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

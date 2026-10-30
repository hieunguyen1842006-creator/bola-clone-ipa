// NVH LQ LIVE CONFIG v3 — patch IFix hook LFramework.get_frameSynchr
//
// NHIEM VU:
//   1. Doc Documents/nvh_aov.txt (app ghi) moi giay -> ap vao PlayerPrefs
//      key iFix.* ma payload AOV doc (ESP/aim/smite/zoom/skin).
//   2. TU NHAN DIEN TUONG DANG CHOI: doc hostPlayer -> CaptainLinker ->
//      ConfigId + CSkinInfo (GetWearSkinID / GetHeroSkin) -> ghi vao file
//      nvh_aov.log: ma tuong, skin dang mac, SO skin + TEN tung skin.
//      App doc file nay de hien danh sach skin bam chon (khong can nhap tay).
//
// BAU VAT LIEU TU CAC BAN TRUOC:
//   - diag-2 (touchCount lenh dau): khong đơ — exception vo hai.
//   - diag-3/v1 (body chay that tren thread sai): đơ luc load.
//   => 3 lop chan: L1 chi thread chinh | L2 probe Input.touchCount |
//      L3 try/catch toan bo. Toan bo API da kiem tra RVA trong dump.cs.
//
// File nvh_aov.log (app doc):
//   dong 1: tid=<n> main=1 rev=<r> calls=<c> t=<giay>
//   dong 2: hero=<id> skin=<dangmac> count=<n> names=<t0>|<t1>|...
//           hero=0 khi khong trong tran / chua san sang.

using System;
using UnityEngine;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

// ---------------- type gia lap (IFix resolve ten) ----------------
// LFrameSynchr PHAI cung namespace voi LFramework — signature trong process_cfg
// la NucleusDrive.Logic.LFrameSynchr, sai namespace = IFix sinh patch rong.

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

namespace Assets.Scripts.GameLogic
{
    public class GameKernal
    {
        public class Player
        {
            public PoolObjHandle<Kyrios.Actor.ActorLinker> CaptainLinker;
        }
    }
}

namespace ResData
{
    public class ResHeroSkin
    {
        public bool bHideUI;
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
        public int   __mMainTid;    // thread id ghi danh dau tien = thread chinh
        public int   __mRev;        // rev da ap (bo qua file khong doi)
        public int   __mCalls;      // dem luot chay qua phan viec (heartbeat)
        public float __mNext;       // moc thoi gian doc config tiep
        public float __mLogNext;    // moc thoi gian ghi heartbeat tiep

        /// <summary>Doc nvh_aov.txt moi giay + ghi trang thai tuong moi 5 giay.</summary>
        public LFrameSynchr get_frameSynchr()
        {
            LFrameSynchr fs = _frameSynchr;

            try
            {
                // ==== L1: chan thread ====
                int tid = System.Threading.Thread.CurrentThread.ManagedThreadId;
                if (__mMainTid == 0)
                {
                    __mMainTid = tid;
                }
                if (tid != __mMainTid) return fs;

                // ==== L2: probe Input — ngu canh xau nem exception, bo qua ====
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

                // ==== heartbeat 5 giay + TU NHAN DIEN TUONG ====
                if (now >= __mLogNext)
                {
                    __mLogNext = now + 5.0f;
                    string hb = "tid=" + tid + " main=1 rev=" + __mRev
                        + " calls=" + __mCalls + " t=" + (int)now;

                    // trang thai tuong: hostLogic -> hostPlayer -> CaptainLinker
                    string st = "hero=0";
                    try
                    {
                        Kyrios.VHostLogic host = Kyrios.KyriosFramework.get_hostLogic();
                        if (host != null)
                        {
                            Assets.Scripts.GameLogic.GameKernal.Player pl = host.get_hostPlayer();
                            if (pl != null)
                            {
                                PoolObjHandle<Kyrios.Actor.ActorLinker> cap = pl.CaptainLinker;
                                if (cap.HasValue)
                                {
                                    Kyrios.Actor.ActorLinker al = cap.handle;
                                    if (al != null)
                                    {
                                        uint heroId = al.ConfigId;
                                        uint wear = Assets.Scripts.GameSystem.CSkinInfo
                                            .GetWearSkinID(heroId);

                                        // liet ke skin: GetHeroSkin tra null khi vuot so luong
                                        string names = "";
                                        int cnt = 0;
                                        uint si = 0;
                                        while (si < 60)
                                        {
                                            ResData.ResHeroSkin rs = Assets.Scripts.GameSystem
                                                .CSkinInfo.GetHeroSkin(heroId, si);
                                            if (rs == null) break;
                                            string nm = rs.szSkinName;
                                            if (nm == null || nm.Length == 0)
                                                nm = "Skin " + si.ToString();
                                            if (cnt > 0) names = names + "|";
                                            names = names + nm;
                                            cnt = cnt + 1;
                                            si = si + 1;
                                        }

                                        st = "hero=" + heroId.ToString()
                                            + " skin=" + wear.ToString()
                                            + " count=" + cnt.ToString()
                                            + " names=" + names;
                                    }
                                }
                            }
                        }
                    }
                    catch (Exception)
                    {
                        // khong doc duoc state — bao hero=0, khong bao gio lan ra
                    }

                    System.IO.File.WriteAllText(
                        Application.persistentDataPath + "/nvh_aov.log",
                        hb + "\n" + st);
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

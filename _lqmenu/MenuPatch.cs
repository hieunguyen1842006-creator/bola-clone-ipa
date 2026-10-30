// NVH LQ LIVE CONFIG v4 — patch IFix hook LFramework.get_frameSynchr
//
// NHIEM VU:
//   1. Doc Documents/nvh_aov.txt (app ghi) moi giay -> ap vao PlayerPrefs
//      key iFix.* ma payload AOV doc (ESP/aim/smite/zoom/skin).
//   2. Khi app YEU CAU (dong "probe="): doc hostPlayer -> CaptainLinker ->
//      ConfigId + CSkinInfo -> ghi ma tuong / skin dang mac / ten skin vao
//      nvh_aov.log de app hien bang skin bam chon.
//
// SUA LOI TREO (v4):
//   v3 khai `class GameKernal { class Player }` -> ten metadata
//   Assets.Scripts.GameLogic.GameKernal+Player, trong khi game la
//   NAMESPACE Assets.Scripts.GameLogic.GameKernal + class Player.
//   Lech ten => IFix resolve hut NGAY LUC NAP PATCH => treo truoc khi hook
//   chay (nen khoa detection bang co probe khong cuu duoc). Da sua:
//   namespace Assets.Scripts.GameLogic.GameKernal { public class Player }
//
// Da doi chieu dump.cs (chinh xac tung chu):
//   PoolObjHandle<T> : struct, co HasValue / handle (property)
//   Kyrios.Actor.ActorLinker::get_ConfigId -> uint
//   Kyrios.VHostLogic::get_hostPlayer() -> Player
//   ResData.ResHeroSkin::szSkinName (string, field)
//   CSkinInfo::GetWearSkinID(uint) / GetHeroSkin(uint,uint)
//
// AN TOAN RUNTIME: GetHeroSkin khi MISS key goi TableManager::Reload (nang).
//   => chi do khi app yeu cau, chan heroId vo ly, toi da 8 skin, dung som.
//   Duong mac dinh (khong probe) khong goi API nao cua game.
// 3 lop chan: L1 chi thread chinh | L2 probe Input.touchCount | L3 try/catch.

using System;
using UnityEngine;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

// ---------------- type gia lap (IFix resolve ten) ----------------

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
        public int   __mMainTid;    // thread id ghi danh dau tien = thread chinh
        public int   __mRev;        // rev da ap (bo qua file khong doi)
        public int   __mProbeReq;   // so hieu yeu cau do tuong (app tang)
        public int   __mProbeDone;  // so hieu da do xong
        public int   __mCalls;      // dem luot chay qua phan viec (heartbeat)
        public float __mNext;       // moc thoi gian doc config tiep
        public float __mLogNext;    // moc thoi gian ghi heartbeat tiep

        public LFrameSynchr get_frameSynchr()
        {
            LFrameSynchr fs = _frameSynchr;

            try
            {
                // ==== L1: chan thread ====
                int tid = System.Threading.Thread.CurrentThread.ManagedThreadId;
                if (__mMainTid == 0) __mMainTid = tid;
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

                                p = t.IndexOf("probe=");
                                if (p >= 0)
                                {
                                    int e = t.IndexOf('\n', p);
                                    string s = (e > p) ? t.Substring(p + 6, e - p - 6)
                                                       : t.Substring(p + 6);
                                    int v;
                                    if (int.TryParse(s.Trim(), out v)) __mProbeReq = v;
                                }

                                PlayerPrefs.Save();
                            }
                        }
                    }
                }

                // ==== heartbeat 2 giay + do tuong (chi khi app yeu cau) ====
                if (now >= __mLogNext)
                {
                    __mLogNext = now + 2.0f;
                    string hb = "tid=" + tid + " main=1 rev=" + __mRev
                        + " calls=" + __mCalls + " t=" + (int)now;

                    // dbg: dau vet tung buoc de biet chet o dau (s0..s6 / err=)
                    string st = "hero=0 dbg=s0";
                    if (__mProbeReq != __mProbeDone)
                    {
                        __mProbeDone = __mProbeReq;
                        try
                        {
                            Kyrios.VHostLogic host = Kyrios.KyriosFramework.get_hostLogic();
                            st = "hero=0 dbg=s1";
                            if (host != null)
                            {
                                Assets.Scripts.GameLogic.GameKernal.Player pl = host.get_hostPlayer();
                                st = "hero=0 dbg=s2";
                                if (pl != null)
                                {
                                    PoolObjHandle<Kyrios.Actor.ActorLinker> cap = pl.CaptainLinker;
                                    st = "hero=0 dbg=s3";
                                    if (cap.HasValue)
                                    {
                                        st = "hero=0 dbg=s4";
                                        Kyrios.Actor.ActorLinker al = cap.handle;
                                        if (al != null)
                                        {
                                            st = "hero=0 dbg=s5";
                                            uint heroId = al.ConfigId;
                                            st = "hero=0 dbg=s6 hid=" + heroId.ToString();
                                            if (heroId > 0U && heroId < 100000U)
                                            {
                                                uint wear = Assets.Scripts.GameSystem.CSkinInfo
                                                    .GetWearSkinID(heroId);
                                                st = "hero=0 dbg=s7 hid=" + heroId.ToString()
                                                    + " wear=" + wear.ToString();

                                                // toi da 8 skin; dung som khi gap null/ten rong/lap
                                                string names = ""; int cnt = 0; uint si = 0U;
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
                                                    if (cnt > 0) names += "|";
                                                    names += nm;
                                                    cnt++; si++;
                                                }

                                                st = "hero=" + heroId.ToString()
                                                    + " skin=" + wear.ToString()
                                                    + " count=" + cnt.ToString()
                                                    + " names=" + names
                                                    + " dbg=ok";
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        catch (Exception ex)
                        {
                            string msg = ex.Message;
                            if (msg == null) msg = "null";
                            msg = msg.Replace('\n', ' ').Replace('\r', ' ');
                            if (msg.Length > 70) msg = msg.Substring(0, 70);
                            st = "hero=0 err=" + ex.GetType().Name + ":" + msg;
                        }
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

﻿// NVH LQ MENU — menu cam ung da trang trong game (IFix patch, hook LFramework.get_frameSynchr)
//
// QUAN TRONG 1: IFix CHI patch dung nhung method khai trong process_cfg. Moi method
// khac duoc goi tu trong do se tro vao DLL goc (khong ton tai) -> crash.
// Vi vay TOAN BO logic phai nam trong MOT method get_frameSynchr().
//
// QUAN TRONG 2: get_frameSynchr() bi goi nhieu lan moi frame khi vao tran.
// Chan theo Time.frameCount: moi frame chi xu ly 1 lan.
//
// QUAN TRONG 3: KHONG goi method khac cua LFramework. UI DontDestroyOnLoad.
//
// KEY PlayerPrefs (khop dung payload AOV that — hook doc cac key nay):
//   iFix.ESP.Enabled.v1          0/1
//   iFix.AutoBP.Enabled.v1       0/1  (bocpha)
//   iFix.AIM.Enabled.v1          0/1
//   iFix.AIM.TargetMode.v1       0=hp 1=percent 2=near 3=ray
//   iFix.AIM.DrawMode.v1         0=off 1=always(/line all) 2=skill
//   iFix.AIM.Lines.v1            1..5 so duong aim
//   iFix.AutoSmite.Enabled.v1    0/1
//   iFix.AutoSmite.TargetMode.v1 0=boss 1=buff 2=all
//   iFix.Camera.Zoom.v1          float 1.0..5.0
//   iFix.SelectedSkin.v1.<heroId> index skin 0..99 (doi model khi respawn/doi mesh)
//   /listskin tra ten skin qua chat (doc databin game — menu khong doc duoc)
//
// TRANG: 0=MAIN 1=SKIN 2=AIM 3=LINE 4=SMITE 5=CAMERA
// DONG chia 3 vung: trai = giam, giua = chon/tat, phai = tang.
//
// DIAGNOSIS 3 (breadcrumb tren nut, tim thu chet dung):
//   NVH = doan input CHUA chay qua lan nao (hook bi goi qua it hoac chi luc load)
//   A   = da vao doan input (init xong, qua chan panelGo)
//   B   = sap goi Input.touchCount  -> dong bang o B = Input.touchCount cham/throw
//   C   = touchCount OK, khong co touch; MAU NUT BIEN DOI Lien TUC = hook song moi frame
//   D   = co touch, sap goi GetTouch
//   E   = GetTouch OK, dang xu ly cham + nut VANG
//   Ket luan theo chu tren nut: NVH=hook chay lai sau init | B=Input bi strip |
//   C+frozen color=hook dung sau vai frame | C+mau chay=hook song, thu input khac.

using System;
using UnityEngine;
using UnityEngine.UI;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

// ---------------- type gia lap (IFix resolve ten) ----------------
public struct ActorMeta { public int ConfigId; public int SkinID; }
public struct CrypticInt32 { public int ToInt() { return 0; } }
public struct PoolObjHandle<T> { public uint _handleSeq; public T _handleObj; public T handle { get { return default(T); } } }
public struct VInt3 { public int x; public int y; public int z; public static explicit operator Vector3(VInt3 v) { return default(Vector3); } }
public class ActorPreloadTab { }
public class ActorServerData { }

namespace CSProtocol
{
    public enum COM_PLAYERCAMP { CAMP_NONE = 0, CAMP_1 = 1, CAMP_2 = 2 }
}

namespace Kyrios
{
    public class VHostLogic { public CSProtocol.COM_PLAYERCAMP get_enemyCamp() { return CSProtocol.COM_PLAYERCAMP.CAMP_NONE; } }
    public class KyriosFramework { public static VHostLogic get_hostLogic() { return null; } }
}

namespace Assets.Scripts.GameSystem
{
    public static class CSkinInfo
    {
        public static uint GetWearSkinID(uint heroId) { return 0; }
        public static bool IsOwnSkin(uint skinId, ulong ownBits) { return true; }
        public static bool IsCanBuy(uint heroId, uint skinId) { return true; }
        public static bool GetDefaultSkinIsAvailable(uint heroId) { return true; }
    }
    public class NotifyInfoBase { }
}

namespace NucleusDrive.Share { public class MsgSkinResCheckInfoSend { } }

namespace LDataProvider
{
    public class ActorServerDataProvider
    {
        public bool GetActorSkinID(ref ActorMeta m, out int skinId)
        {
            skinId = (int)Assets.Scripts.GameSystem.CSkinInfo.GetWearSkinID((uint)m.ConfigId);
            return true;
        }
    }
}

public class KillNotify3D
{
    private bool IsPlaySkinKillNotify(Assets.Scripts.GameSystem.NotifyInfoBase n) { return true; }
    public bool IsShowDefault(int id, uint skin) { return false; }
}

public class GameLoader
{
    private bool CheckSkinMD5(ActorPreloadTab a, ActorServerData b) { return true; }
    private static void SendCheckMsg(NucleusDrive.Share.MsgSkinResCheckInfoSend m) { }
}

namespace NucleusDrive.Logic
{
    public class LFrameSynchr { }

    public class LFramework
    {
        // ---- field CO SAN cua game (KHONG khai trong process_cfg) ----
        public LFrameSynchr _frameSynchr;

        // ---- field moi ----
        public bool  __mInit;
        public bool  __mOpen;
        public int   __mFrame;      // chong goi lap
        public int   __mRetry;      // cho scene on dinh
        public int   __mPage;       // trang hien tai
        public int   __mHero;       // heroId dang chinh skin
        public int   __mSkin;       // index skin dang chinh
        public int   __mDirty;      // co phai ve lai chu
        public int   __mAlive;      // da chay qua doan input it nhat 1 lan
        public float __mX;
        public float __mY;
        public object __mRoot;
        public object __mCanvas;
        public object __mPanel;
        public object __mBtn;
        public object __mBtnText;
        public object __mLabels;
        public object __mFont;

        /// <summary>Toan bo menu nam trong 1 method.</summary>
        public LFrameSynchr get_frameSynchr()
        {
            LFrameSynchr fs = _frameSynchr;

            // ===== 0. CHAN GOI LAP =====
            int nowFrame = Time.frameCount;
            if (nowFrame == __mFrame) return fs;
            __mFrame = nowFrame;

            GameObject root = null;
            if (__mRoot != null) root = (GameObject)__mRoot;

            if (!__mInit || root == null)
            {
                __mRoot = null;
                __mCanvas = null;
                __mPanel = null;
                __mBtn = null;
                __mLabels = null;
                __mFont = null;
                __mOpen = false;

                __mRetry++;
                if (__mRetry < 15) return fs;
                __mRetry = 0;

                Font fnt = (Font)Resources.GetBuiltinResource(typeof(Font), "Arial.ttf");
                if (fnt == null) return fs;
                __mFont = fnt;

                if (!__mInit)
                {
                    __mX = 60f;
                    __mY = 60f;
                    __mPage = 0;
                    __mHero = 111;
                    __mSkin = 0;
                    __mDirty = 1;
                }
                __mInit = true;

                root = new GameObject("NVHMenuRoot",
                    new Type[] { typeof(RectTransform), typeof(Canvas) });
                Canvas cv = (Canvas)root.GetComponent(typeof(Canvas));
                if (cv != null)
                {
                    cv.renderMode = RenderMode.ScreenSpaceOverlay;
                    cv.sortingOrder = 32000;
                }
                __mCanvas = cv;
                UnityEngine.Object.DontDestroyOnLoad(root);

                // ---- nut mo menu ----
                GameObject btn = new GameObject("NVHBtn",
                    new Type[] { typeof(RectTransform), typeof(Image) });
                btn.transform.SetParent(root.transform, false);
                RectTransform brt = (RectTransform)btn.GetComponent(typeof(RectTransform));
                if (brt != null)
                {
                    brt.anchorMin = new Vector2(0f, 0f);
                    brt.anchorMax = new Vector2(0f, 0f);
                    brt.pivot = new Vector2(0.5f, 0.5f);
                    brt.anchoredPosition = new Vector2(__mX, __mY);
                    brt.sizeDelta = new Vector2(64f, 64f);
                }
                Image bi = (Image)btn.GetComponent(typeof(Image));
                if (bi != null) bi.color = new Color(0.12f, 0.65f, 1f, 0.9f);
                __mBtn = btn;

                GameObject btxGo = new GameObject("t",
                    new Type[] { typeof(RectTransform), typeof(Text) });
                btxGo.transform.SetParent(btn.transform, false);
                Text btx = (Text)btxGo.GetComponent(typeof(Text));
                if (btx != null)
                {
                    btx.font = fnt;
                    btx.text = "NVH";
                    btx.fontSize = 24;
                    btx.alignment = TextAnchor.MiddleCenter;
                    btx.color = Color.white;
                    btx.raycastTarget = false;
                }
                __mBtnText = btx;

                // ---- panel 10 dong ----
                GameObject panel = new GameObject("NVHPanel",
                    new Type[] { typeof(RectTransform), typeof(Image) });
                panel.transform.SetParent(root.transform, false);
                RectTransform prt = (RectTransform)panel.GetComponent(typeof(RectTransform));
                if (prt != null)
                {
                    prt.anchorMin = new Vector2(0f, 0f);
                    prt.anchorMax = new Vector2(0f, 0f);
                    prt.pivot = new Vector2(0f, 0f);
                    prt.anchoredPosition = new Vector2(__mX - 32f, __mY + 40f);
                    prt.sizeDelta = new Vector2(300f, 440f);
                }
                Image pi = (Image)panel.GetComponent(typeof(Image));
                if (pi != null) pi.color = new Color(0.04f, 0.04f, 0.07f, 0.93f);
                panel.SetActive(false);
                __mOpen = false;
                __mPanel = panel;

                Text[] lb = new Text[10];
                for (int k = 0; k < 10; k++)
                {
                    GameObject row = new GameObject("row" + k,
                        new Type[] { typeof(RectTransform), typeof(Text) });
                    row.transform.SetParent(panel.transform, false);
                    RectTransform rrt = (RectTransform)row.GetComponent(typeof(RectTransform));
                    if (rrt != null)
                    {
                        rrt.anchorMin = new Vector2(0f, 1f);
                        rrt.anchorMax = new Vector2(1f, 1f);
                        rrt.pivot = new Vector2(0.5f, 1f);
                        rrt.anchoredPosition = new Vector2(0f, -10f - k * 42f);
                        rrt.sizeDelta = new Vector2(-24f, 40f);
                    }
                    Text tx = (Text)row.GetComponent(typeof(Text));
                    if (tx != null)
                    {
                        tx.font = fnt;
                        tx.fontSize = 22;
                        tx.alignment = TextAnchor.MiddleLeft;
                        tx.color = new Color(0.9f, 0.95f, 1f, 1f);
                        tx.raycastTarget = false;
                        tx.text = "";
                    }
                    lb[k] = tx;
                }
                __mLabels = lb;
                __mRoot = root;
                return fs;
            }

            // ===== 2. input =====
            GameObject panelGo = null;
            if (__mPanel != null) panelGo = (GameObject)__mPanel;
            if (panelGo == null) return fs;

            // ===== DIAGNOSIS 3: breadcrumb A..E, viet chu TRUOC moi lenh rui ro =====
            // Neu mot lenh nao do cham/throw, IFix huy ca khoi nay -> chu
            // dung yen o buoc cuoi cung ghi duoc -> do la thu chet.
            Text btxD = null;
            if (__mBtnText != null) btxD = (Text)__mBtnText;
            if (btxD != null) btxD.text = "A";

            if (btxD != null) btxD.text = "B";
            int tc = Input.touchCount;

            if (btxD != null) btxD.text = "C";
            __mAlive = __mAlive + 1;                 // dem so frame doan input song
            float pulse = Mathf.Sin((float)__mAlive * 0.06f);
            Image imgD = null;
            if (__mBtn != null)
            {
                GameObject btnGoD = (GameObject)__mBtn;
                if (btnGoD != null)
                    imgD = (Image)btnGoD.GetComponent(typeof(Image));
            }
            if (imgD != null)
            {
                if (tc > 0) imgD.color = new Color(0.95f, 0.85f, 0.1f, 0.95f);
                else imgD.color = new Color(0.30f + 0.35f * (pulse * 0.5f + 0.5f),
                                            0.65f, 1f, 0.95f);
            }

            if (tc > 0)
            {
                if (btxD != null) btxD.text = "D";
                int lim = tc > 2 ? 2 : tc;
                for (int i = 0; i < lim; i++)
                {
                    Touch t = Input.GetTouch(i);
                    if (btxD != null) btxD.text = "E";
                    if (t.phase != TouchPhase.Began) continue;

                    // cham nut NVH -> dong/mo panel
                    float dx = t.position.x - __mX;
                    float dy = t.position.y - __mY;
                    if (dx * dx + dy * dy < 40f * 40f)
                    {
                        __mOpen = !__mOpen;
                        panelGo.SetActive(__mOpen);
                        __mDirty = 1;
                        break;
                    }

                    if (!__mOpen) continue;

                    RectTransform prt2 =
                        (RectTransform)panelGo.GetComponent(typeof(RectTransform));
                    if (prt2 == null) continue;

                    Vector2 lp = default(Vector2);
                    if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(
                            prt2, t.position, null, out lp)) continue;

                    Rect rr = prt2.rect;
                    if (lp.x < rr.xMin - 20f || lp.x > rr.xMax + 20f) continue;
                    if (lp.y < rr.yMin || lp.y > rr.yMax) continue;

                    int row = (int)((rr.yMax - lp.y - 10f) / 42f);

                    // chia 3 vung: 0=trai (giam), 1=giua, 2=phai (tang)
                    int act = 1;
                    if (lp.x < rr.xMin + 96f) act = 0;
                    else if (lp.x > rr.xMax - 96f) act = 2;

                    // ===== xu ly theo trang =====
                    if (__mPage == 0)
                    {
                        // MAIN
                        if (row == 1)
                        {
                            int v = PlayerPrefs.GetInt("iFix.ESP.Enabled.v1", 0);
                            PlayerPrefs.SetInt("iFix.ESP.Enabled.v1", v == 0 ? 1 : 0);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 2)
                        {
                            int v = PlayerPrefs.GetInt("iFix.AutoBP.Enabled.v1", 0);
                            PlayerPrefs.SetInt("iFix.AutoBP.Enabled.v1", v == 0 ? 1 : 0);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 3)
                        {
                            __mPage = 1;
                            __mSkin = PlayerPrefs.GetInt(
                                "iFix.SelectedSkin.v1." + __mHero, 0);
                            __mDirty = 1;
                        }
                        else if (row == 4) { __mPage = 2; __mDirty = 1; }
                        else if (row == 5) { __mPage = 3; __mDirty = 1; }
                        else if (row == 6) { __mPage = 4; __mDirty = 1; }
                        else if (row == 7) { __mPage = 5; __mDirty = 1; }
                    }
                    else if (__mPage == 1)
                    {
                        // SKIN: heroId + index 0..99
                        if (row == 0) { __mPage = 0; __mDirty = 1; }
                        else if (row == 1)
                        {
                            if (act == 0 && __mHero > 1) __mHero--;
                            else if (act == 2) __mHero++;
                            __mSkin = PlayerPrefs.GetInt(
                                "iFix.SelectedSkin.v1." + __mHero, 0);
                            __mDirty = 1;
                        }
                        else if (row == 2)
                        {
                            if (act == 0 && __mSkin > 0) __mSkin--;
                            else if (act == 2 && __mSkin < 99) __mSkin++;
                            else if (act == 1 && __mSkin >= 0 && __mSkin <= 99)
                            {
                                // cham giua: ap dung luon
                            }
                            PlayerPrefs.SetInt("iFix.SelectedSkin.v1." + __mHero, __mSkin);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                    }
                    else if (__mPage == 2)
                    {
                        // AIM
                        if (row == 0) { __mPage = 0; __mDirty = 1; }
                        else if (row == 1)
                        {
                            int v = PlayerPrefs.GetInt("iFix.AIM.Enabled.v1", 0);
                            PlayerPrefs.SetInt("iFix.AIM.Enabled.v1", v == 0 ? 1 : 0);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 2)
                        {
                            PlayerPrefs.SetInt("iFix.AIM.TargetMode.v1", 0);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 3)
                        {
                            PlayerPrefs.SetInt("iFix.AIM.TargetMode.v1", 1);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 4)
                        {
                            PlayerPrefs.SetInt("iFix.AIM.TargetMode.v1", 2);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 5)
                        {
                            PlayerPrefs.SetInt("iFix.AIM.TargetMode.v1", 3);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 6)
                        {
                            int ln = PlayerPrefs.GetInt("iFix.AIM.Lines.v1", 1);
                            if (act == 0 && ln > 1) ln--;
                            else if (act == 2 && ln < 5) ln++;
                            PlayerPrefs.SetInt("iFix.AIM.Lines.v1", ln);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                    }
                    else if (__mPage == 3)
                    {
                        // LINE (DrawMode)
                        if (row == 0) { __mPage = 0; __mDirty = 1; }
                        else if (row == 1)
                        {
                            PlayerPrefs.SetInt("iFix.AIM.DrawMode.v1", 0);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 2)
                        {
                            PlayerPrefs.SetInt("iFix.AIM.DrawMode.v1", 1);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 3)
                        {
                            PlayerPrefs.SetInt("iFix.AIM.DrawMode.v1", 2);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                    }
                    else if (__mPage == 4)
                    {
                        // SMITE (trungtri)
                        if (row == 0) { __mPage = 0; __mDirty = 1; }
                        else if (row == 1)
                        {
                            PlayerPrefs.SetInt("iFix.AutoSmite.Enabled.v1", 0);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 2)
                        {
                            PlayerPrefs.SetInt("iFix.AutoSmite.TargetMode.v1", 0);
                            PlayerPrefs.SetInt("iFix.AutoSmite.Enabled.v1", 1);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 3)
                        {
                            PlayerPrefs.SetInt("iFix.AutoSmite.TargetMode.v1", 1);
                            PlayerPrefs.SetInt("iFix.AutoSmite.Enabled.v1", 1);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                        else if (row == 4)
                        {
                            PlayerPrefs.SetInt("iFix.AutoSmite.TargetMode.v1", 2);
                            PlayerPrefs.SetInt("iFix.AutoSmite.Enabled.v1", 1);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                    }
                    else if (__mPage == 5)
                    {
                        // CAMERA: thanh keo
                        if (row == 0) { __mPage = 0; __mDirty = 1; }
                        else if (row == 1)
                        {
                            float pct = (lp.x - rr.xMin) / 276f;
                            if (pct < 0f) pct = 0f;
                            if (pct > 1f) pct = 1f;
                            float zv = 1.0f + pct * 4.0f;
                            zv = (int)(zv * 10f + 0.5f) / 10f;
                            PlayerPrefs.SetFloat("iFix.Camera.Zoom.v1", zv);
                            PlayerPrefs.Save();
                            __mDirty = 1;
                        }
                    }
                }
            }

            // ===== 3. ve lai chu — CHI khi mo + co thay doi =====
            if (__mOpen && __mDirty != 0 && __mLabels != null)
            {
                __mDirty = 0;
                Text[] lb2 = (Text[])__mLabels;
                if (lb2 == null || lb2[0] == null) return fs;

                bool espOn = PlayerPrefs.GetInt("iFix.ESP.Enabled.v1", 0) == 1;
                bool bpOn = PlayerPrefs.GetInt("iFix.AutoBP.Enabled.v1", 0) == 1;
                int aimEn = PlayerPrefs.GetInt("iFix.AIM.Enabled.v1", 0);
                int tm = PlayerPrefs.GetInt("iFix.AIM.TargetMode.v1", 0);
                int dm = PlayerPrefs.GetInt("iFix.AIM.DrawMode.v1", 0);
                int lines = PlayerPrefs.GetInt("iFix.AIM.Lines.v1", 1);
                int smEn = PlayerPrefs.GetInt("iFix.AutoSmite.Enabled.v1", 0);
                int smTm = PlayerPrefs.GetInt("iFix.AutoSmite.TargetMode.v1", 0);
                float zz = PlayerPrefs.GetFloat("iFix.Camera.Zoom.v1", 1.6f);

                if (__mPage == 0)
                {
                    lb2[0].text = "NVH MOD";
                    lb2[1].text = "ESP       " + (espOn ? "ON" : "OFF");
                    lb2[2].text = "BOCPHA    " + (bpOn ? "ON" : "OFF");
                    lb2[3].text = "SKIN    >";
                    lb2[4].text = "AIM     >";
                    lb2[5].text = "LINE    >";
                    lb2[6].text = "SMITE   >";
                    lb2[7].text = "CAMERA  >";
                    lb2[8].text = "";
                    lb2[9].text = "";
                }
                else if (__mPage == 1)
                {
                    lb2[0].text = "< BACK        SKIN";
                    lb2[1].text = "HERO    -   " + __mHero + "   +";
                    lb2[2].text = "MODEL   -   " + __mSkin + "   +";
                    lb2[3].text = "chat /listskin xem ten";
                    lb2[4].text = "(dung khi respawn)";
                    lb2[5].text = "";
                    lb2[6].text = "";
                    lb2[7].text = "";
                    lb2[8].text = "";
                    lb2[9].text = "";
                }
                else if (__mPage == 2)
                {
                    lb2[0].text = "< BACK         AIM";
                    lb2[1].text = "AIM       " + (aimEn == 1 ? "ON" : "OFF");
                    lb2[2].text = (tm == 0 ? "> " : "  ") + "TARGET HP";
                    lb2[3].text = (tm == 1 ? "> " : "  ") + "TARGET PCT";
                    lb2[4].text = (tm == 2 ? "> " : "  ") + "TARGET NEAR";
                    lb2[5].text = (tm == 3 ? "> " : "  ") + "TARGET RAY";
                    lb2[6].text = "LINES   -   " + lines + "   +";
                    lb2[7].text = "";
                    lb2[8].text = "";
                    lb2[9].text = "";
                }
                else if (__mPage == 3)
                {
                    lb2[0].text = "< BACK        LINE";
                    lb2[1].text = (dm == 0 ? "> " : "  ") + "OFF";
                    lb2[2].text = (dm == 1 ? "> " : "  ") + "ALWAYS  (/line all)";
                    lb2[3].text = (dm == 2 ? "> " : "  ") + "SKILL";
                    lb2[4].text = "";
                    lb2[5].text = "";
                    lb2[6].text = "";
                    lb2[7].text = "";
                    lb2[8].text = "";
                    lb2[9].text = "";
                }
                else if (__mPage == 4)
                {
                    lb2[0].text = "< BACK       SMITE";
                    lb2[1].text = (smEn == 0 ? "> " : "  ") + "OFF";
                    lb2[2].text = (smEn == 1 && smTm == 0 ? "> " : "  ") + "BOSS";
                    lb2[3].text = (smEn == 1 && smTm == 1 ? "> " : "  ") + "BUFF";
                    lb2[4].text = (smEn == 1 && smTm == 2 ? "> " : "  ") + "ALL";
                    lb2[5].text = "";
                    lb2[6].text = "";
                    lb2[7].text = "";
                    lb2[8].text = "";
                    lb2[9].text = "";
                }
                else
                {
                    // CAMERA
                    lb2[0].text = "< BACK      CAMERA";
                    float pct = (zz - 1.0f) / 4.0f;
                    if (pct < 0f) pct = 0f;
                    if (pct > 1f) pct = 1f;
                    int n = (int)(pct * 20f + 0.5f);
                    string bar = "[";
                    for (int k = 0; k < 20; k++)
                    {
                        bar = bar + (k < n ? "=" : ".");
                    }
                    bar = bar + "]";
                    lb2[1].text = bar;
                    lb2[2].text = "ZOOM  " + zz + "x";
                    lb2[3].text = "ke tren thanh de chinh";
                    lb2[4].text = "";
                    lb2[5].text = "";
                    lb2[6].text = "";
                    lb2[7].text = "";
                    lb2[8].text = "";
                    lb2[9].text = "";
                }
            }

            return fs;
        }
    }
}

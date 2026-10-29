// NVH LQ MENU — menu cam ung trong game (IFix patch, hook LFramework.get_frameSynchr)
//
// QUAN TRONG 1: IFix CHI patch dung nhung method khai trong process_cfg. Moi method
// khac duoc goi tu trong do se tro vao DLL goc (khong ton tai) -> crash.
// Vi vay TOAN BO logic phai nam trong MOT method get_frameSynchr().
//
// QUAN TRONG 2: get_frameSynchr() la accessor BI GOI RAT NHIEU LAN MOI FRAME khi
// vao tran (moi actor / moi he thong deu lay). IFix thay the TOAN BO than ham,
// nen neu than ham nang thi game dung hinh ngay luc load tran.
//   -> Dong dau tien phai la chan theo Time.frameCount: moi frame chi xu ly 1 lan,
//      cac lan goi sau return ngay (chi ~10 lenh IL).
//
// QUAN TRONG 3: KHONG duoc goi method khac cua LFramework (vd get_mainBattleLogic):
// khai trong newMethodInfo thi IFix bien no thanh block VM `return null` thay vi
// method that cua game; khong khai thi IFix khong resolve duoc. Chuong cua UI:
// DontDestroyOnLoad(root) -> UI song qua moi scene (lobby <-> tran), khong can biet
// dang o dau. Neu object chet (lifetime check) thi tao lai sau vai frame.
//
// Dieu khien: cham nut NVH goc trai duoi -> mo panel. Cham tung dong de bat/tat.
// Trang thai ghi vao PlayerPrefs tien to "iFix.*" — cung key patch AOV dung,
// nen menu nay dieu khien duoc ca hook cua payload that.

using System;
using UnityEngine;
using UnityEngine.UI;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

// ---------------- type gia lap (IFix resolve ten) ----------------
public struct ActorMeta { public int ConfigId; }
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
        // ---- field CO SAN cua game (KHONG khai trong process_cfg -> IFix
        //      resolve ve field that, giu nguyen hanh vi goc) ----
        public LFrameSynchr _frameSynchr;

        // ---- field moi (khai trong process_cfg, sinh tu chinh file nay) ----
        public bool  __mInit;
        public bool  __mOpen;
        public int   __mFrame;      // Time.frameCount da xu ly (chong goi lap)
        public int   __mRetry;      // so frame cho truoc khi tao lai UI
        public float __mX;
        public float __mY;
        public object __mRoot;
        public object __mCanvas;
        public object __mPanel;
        public object __mBtn;
        public object __mLabels;
        public object __mFont;

        /// <summary>Toan bo menu nam trong 1 method — IFix chi patch method nay.</summary>
        public LFrameSynchr get_frameSynchr()
        {
            // Giu nguyen hanh vi goc: tra ve dung field cua game.
            LFrameSynchr fs = _frameSynchr;

            // ===== 0. CHAN GOI LAP =====
            // Vao tran, method nay bi goi nhieu lan moi frame. Chi xu ly 1
            // lan/frame, cac lan sau thoat ngay de khong lam game dung hinh.
            int nowFrame = Time.frameCount;
            if (nowFrame == __mFrame) return fs;
            __mFrame = nowFrame;

            // UI con song khong? Ep kieu ve GameObject de dung lifetime check
            // cua UnityEngine.Object (null-check thuong KHONG bat duoc object da huy).
            GameObject root = null;
            if (__mRoot != null) root = (GameObject)__mRoot;

            if (!__mInit || root == null)
            {
                // Xoa sach reference co the da chet, tranh dung lai do rac.
                __mRoot = null;
                __mCanvas = null;
                __mPanel = null;
                __mBtn = null;
                __mLabels = null;
                __mFont = null;
                __mOpen = false;

                // Cho vai frame cho scene on dinh roi moi dung UI.
                __mRetry++;
                if (__mRetry < 15) return fs;
                __mRetry = 0;

                // Font BAT BUOC: Text khong co font nem NullReference moi frame.
                Font fnt = (Font)Resources.GetBuiltinResource(typeof(Font), "Arial.ttf");
                if (fnt == null) return fs;      // khong co font -> bo qua UI, game chay binh thuong
                __mFont = fnt;

                if (!__mInit)
                {
                    // Vi tri nut goc trai duoi. Panel nam NGAY TREN nut.
                    __mX = 60f;
                    __mY = 60f;
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

                // Giu UI qua cac dot nap lai scene (lobby <-> tran).
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

                // ---- panel (nam ngay tren nut) ----
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
                    prt.sizeDelta = new Vector2(280f, 270f);
                }
                Image pi = (Image)panel.GetComponent(typeof(Image));
                if (pi != null) pi.color = new Color(0.04f, 0.04f, 0.07f, 0.93f);
                panel.SetActive(false);
                __mPanel = panel;

                // ---- 6 dong ----
                Text[] lb = new Text[6];
                for (int k = 0; k < 6; k++)
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
                        tx.text = "ROW " + k;
                    }
                    lb[k] = tx;
                }
                __mLabels = lb;
                __mRoot = root;

                // Tao xong thi khong xu ly cham trong chinh frame nay.
                return fs;
            }

            // ===== 2. cam ung =====
            GameObject panelGo = null;
            if (__mPanel != null) panelGo = (GameObject)__mPanel;
            if (panelGo == null) return fs;

            int tc = Input.touchCount;
            if (tc > 0)
            {
                int lim = tc > 2 ? 2 : tc;      // toi da 2 ngon, tranh vong lap nang
                for (int i = 0; i < lim; i++)
                {
                    Touch t = Input.GetTouch(i);
                    if (t.phase != TouchPhase.Began) continue;

                    float dx = t.position.x - __mX;
                    float dy = t.position.y - __mY;
                    if (dx * dx + dy * dy < 48f * 48f)
                    {
                        __mOpen = !__mOpen;
                        panelGo.SetActive(__mOpen);
                        break;
                    }

                    if (__mOpen)
                    {
                        RectTransform prt2 =
                            (RectTransform)panelGo.GetComponent(typeof(RectTransform));
                        if (prt2 != null)
                        {
                            Vector2 lp = default(Vector2);
                            if (RectTransformUtility.ScreenPointToLocalPointInRectangle(
                                    prt2, t.position, null, out lp))
                            {
                                Rect rr = prt2.rect;
                                if (lp.x >= rr.xMin - 20f && lp.x <= rr.xMax + 20f
                                    && lp.y >= rr.yMin && lp.y <= rr.yMax)
                                {
                                    int row = (int)((rr.yMax - lp.y - 10f) / 42f);

                                    if (row == 0)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.ESP.Enabled.v1", 0);
                                        PlayerPrefs.SetInt("iFix.ESP.Enabled.v1", v == 0 ? 1 : 0);
                                    }
                                    else if (row == 1)
                                    {
                                        float z = PlayerPrefs.GetFloat("iFix.Camera.Zoom.v1", 1.6f);
                                        z += 0.2f;
                                        if (z > 5.05f) z = 1.0f;
                                        PlayerPrefs.SetFloat("iFix.Camera.Zoom.v1", z);
                                    }
                                    else if (row == 2)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.AIM.Enabled.v1", 0);
                                        PlayerPrefs.SetInt("iFix.AIM.Enabled.v1", v == 0 ? 1 : 0);
                                    }
                                    else if (row == 3)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.Privacy.Off.v1", 0);
                                        PlayerPrefs.SetInt("iFix.Privacy.Off.v1", v == 0 ? 1 : 0);
                                    }
                                    else if (row == 4)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.FakeHost.v1", 0);
                                        PlayerPrefs.SetInt("iFix.FakeHost.v1", v == 0 ? 1 : 0);
                                    }
                                    else if (row == 5)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.AutoSmite.Enabled.v1", 0);
                                        PlayerPrefs.SetInt("iFix.AutoSmite.Enabled.v1", v == 0 ? 1 : 0);
                                    }
                                    PlayerPrefs.Save();
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            // ===== 3. cap nhat chu — CHI khi panel mo =====
            // Panel dong thi khong cap nhat: tranh cap phat chuoi moi frame
            // (GC spike) va tranh cham vao Text khong can thiet.
            if (__mOpen && __mLabels != null)
            {
                Text[] lb2 = (Text[])__mLabels;
                if (lb2 != null && lb2[0] != null)
                {
                    float zz = PlayerPrefs.GetFloat("iFix.Camera.Zoom.v1", 1.6f);
                    lb2[0].text = "ESP      " +
                        (PlayerPrefs.GetInt("iFix.ESP.Enabled.v1", 0) == 0 ? "OFF" : "ON");
                    lb2[1].text = "ZOOM     " + zz + "x";
                    lb2[2].text = "AIM      " +
                        (PlayerPrefs.GetInt("iFix.AIM.Enabled.v1", 0) == 0 ? "OFF" : "ON");
                    lb2[3].text = "PRIVACY  " +
                        (PlayerPrefs.GetInt("iFix.Privacy.Off.v1", 0) == 0 ? "OFF" : "ON");
                    lb2[4].text = "HOST     " +
                        (PlayerPrefs.GetInt("iFix.FakeHost.v1", 0) == 0 ? "OFF" : "ON");
                    lb2[5].text = "SMITE    " +
                        (PlayerPrefs.GetInt("iFix.AutoSmite.Enabled.v1", 0) == 0 ? "OFF" : "ON");
                }
            }

            return fs;
        }
    }
}

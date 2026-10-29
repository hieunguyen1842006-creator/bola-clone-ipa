// NVH LQ MENU — menu cam ung trong game (IFix patch, hook LFramework.get_frameSynchr)
//
// QUAN TRONG: IFix CHI patch dung nhung method khai trong process_cfg. Moi method
// khac duoc goi tu trong do se tro vao DLL goc (khong ton tai) -> crash.
// Vi vay TOAN BO logic phai nam trong MOT method get_frameSynchr().
// (Day cung la pattern cua NVHLQ.vault cu da chay duoc tren may that.)
//
// Dieu khien: cham nut NVH goc trai duoi -> mo panel. Cham tung dong de bat/tat.
// Trang thai ghi vao PlayerPrefs tien to "iFix.*" — cung key patch AOV dung,
// nen menu nay dieu khien duoc ca hook cua payload that.

using System;
using System.IO;
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
        //      resolve ve field that cua LFramework, dung de giu nguyen hanh vi
        //      goc thay vi ghi de bang null) ----
        public LFrameSynchr _frameSynchr;

        // ---- field moi (khai trong process_cfg) ----
        public bool  __mInit;
        public bool  __mOpen;
        public float __mX;
        public float __mY;
        public int   __mTouch;
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

            // ============ 1. khoi tao UI ============
            if (!__mInit)
            {
                __mInit = true;
                __mOpen = false;
                __mX = 78f;
                __mY = 120f;

                // Font BAT BUOC phai co: Text khong co font se nem
                // NullReferenceException MOI FRAME -> flood log -> treo game.
                Font fnt = (Font)Resources.GetBuiltinResource(typeof(Font), "Arial.ttf");
                __mFont = fnt;
                if (fnt == null)
                {
                    // khong co font -> khong tao UI, giu game chay binh thuong
                    return fs;
                }

                GameObject root = new GameObject("NVHMenuRoot",
                    new Type[] { typeof(RectTransform), typeof(Canvas) });
                Canvas cv = (Canvas)root.GetComponent(typeof(Canvas));
                if (cv != null)
                {
                    cv.renderMode = RenderMode.ScreenSpaceOverlay;
                    cv.sortingOrder = 32000;
                }
                __mCanvas = cv;

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
                    brt.sizeDelta = new Vector2(76f, 76f);
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
                    btx.fontSize = 26;
                    btx.alignment = TextAnchor.MiddleCenter;
                    btx.color = Color.white;
                    btx.raycastTarget = false;
                }

                // ---- panel ----
                GameObject panel = new GameObject("NVHPanel",
                    new Type[] { typeof(RectTransform), typeof(Image) });
                panel.transform.SetParent(root.transform, false);
                RectTransform prt = (RectTransform)panel.GetComponent(typeof(RectTransform));
                if (prt != null)
                {
                    prt.anchorMin = new Vector2(0f, 0f);
                    prt.anchorMax = new Vector2(0f, 0f);
                    prt.pivot = new Vector2(0f, 0f);
                    prt.anchoredPosition = new Vector2(__mX + 46f, __mY - 20f);
                    prt.sizeDelta = new Vector2(380f, 430f);
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
                        rrt.anchoredPosition = new Vector2(0f, -16f - k * 66f);
                        rrt.sizeDelta = new Vector2(-30f, 60f);
                    }
                    Text tx = (Text)row.GetComponent(typeof(Text));
                    if (tx != null)
                    {
                        tx.font = fnt;
                        tx.fontSize = 30;
                        tx.alignment = TextAnchor.MiddleLeft;
                        tx.color = new Color(0.9f, 0.95f, 1f, 1f);
                        tx.raycastTarget = false;
                        tx.text = "ROW " + k;
                    }
                    lb[k] = tx;
                }
                __mLabels = lb;
            }

            // ============ 2. cam ung ============
            GameObject panelGo = (GameObject)__mPanel;
            int tc = Input.touchCount;
            if (tc > 0)
            {
                int lim = tc > 2 ? 2 : tc;
                for (int i = 0; i < lim; i++)
                {
                    Touch t = Input.GetTouch(i);
                    if (t.phase != TouchPhase.Began) continue;

                    float dx = t.position.x - __mX;
                    float dy = t.position.y - __mY;
                    if (dx * dx + dy * dy < 56f * 56f)
                    {
                        __mOpen = !__mOpen;
                        if (panelGo != null) panelGo.SetActive(__mOpen);
                        __mTouch = 1;
                        continue;
                    }

                    if (__mOpen && panelGo != null)
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
                                if (lp.x >= rr.xMin && lp.x <= rr.xMax
                                    && lp.y >= rr.yMin && lp.y <= rr.yMax)
                                {
                                    int row = (int)((rr.yMax - lp.y - 16f) / 66f);
                                    __mTouch = 2;

                                    if (row == 0)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.ESP.Enabled.v1", 0);
                                        PlayerPrefs.SetInt("iFix.ESP.Enabled.v1", v == 0 ? 1 : 0);
                                        PlayerPrefs.Save();
                                    }
                                    else if (row == 1)
                                    {
                                        float z = PlayerPrefs.GetFloat("iFix.Camera.Zoom.v1", 1.6f);
                                        z += 0.2f;
                                        if (z > 5.0f) z = 1.0f;
                                        PlayerPrefs.SetFloat("iFix.Camera.Zoom.v1", z);
                                        PlayerPrefs.Save();
                                    }
                                    else if (row == 2)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.AIM.Enabled.v1", 0);
                                        PlayerPrefs.SetInt("iFix.AIM.Enabled.v1", v == 0 ? 1 : 0);
                                        PlayerPrefs.Save();
                                    }
                                    else if (row == 3)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.Privacy.Off.v1", 0);
                                        PlayerPrefs.SetInt("iFix.Privacy.Off.v1", v == 0 ? 1 : 0);
                                        PlayerPrefs.Save();
                                    }
                                    else if (row == 4)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.FakeHost.v1", 0);
                                        PlayerPrefs.SetInt("iFix.FakeHost.v1", v == 0 ? 1 : 0);
                                        PlayerPrefs.Save();
                                    }
                                    else if (row == 5)
                                    {
                                        int v = PlayerPrefs.GetInt("iFix.AutoSmite.Enabled.v1", 0);
                                        PlayerPrefs.SetInt("iFix.AutoSmite.Enabled.v1", v == 0 ? 1 : 0);
                                        PlayerPrefs.Save();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ============ 3. cap nhat chu (sau khi doi trang thai) ============
            if (__mLabels != null)
            {
                Text[] lb2 = (Text[])__mLabels;
                float zz = PlayerPrefs.GetFloat("iFix.Camera.Zoom.v1", 1.6f);

                lb2[0].text = "ESP        " +
                    (PlayerPrefs.GetInt("iFix.ESP.Enabled.v1", 0) == 0 ? "OFF" : "ON");
                lb2[1].text = "ZOOM       " + zz + "x";
                lb2[2].text = "AIM        " +
                    (PlayerPrefs.GetInt("iFix.AIM.Enabled.v1", 0) == 0 ? "OFF" : "ON");
                lb2[3].text = "PRIVACY    " +
                    (PlayerPrefs.GetInt("iFix.Privacy.Off.v1", 0) == 0 ? "OFF" : "ON");
                lb2[4].text = "HOST       " +
                    (PlayerPrefs.GetInt("iFix.FakeHost.v1", 0) == 0 ? "OFF" : "ON");
                lb2[5].text = "SMITE      " +
                    (PlayerPrefs.GetInt("iFix.AutoSmite.Enabled.v1", 0) == 0 ? "OFF" : "ON");
            }

            return fs;
        }
    }
}

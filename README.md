# BolaClone

Bản dựng lại UI/logic của app BolaMinhDuc (menu IFix cho Free Fire), **không kèm**
kernel exploit hay sandbox escape. Phần ghi container dùng đường hợp lệ
(jailbreak / app group / primitive tự cắm).

## Test phần logic (Linux/WSL — đã chạy 86/86)

```bash
bash tools/build_linux.sh
```

Cần Swift toolchain ở `~/swift` (xem đầu file `tools/build_linux.sh`).
Kết quả: build `BolaCore` + `BolaSelfTest` (SHA-256, CRC32, RGB565, BolaConfig,
BolaToken, PatchTrailer, PatchDeployer, ExploitCoordinator).

## Lấy IPA

### Cách 1 — GitHub Actions (không cần Mac)

```bash
gh auth login
bash tools/make_ipa_via_github.sh
# -> build/BolaClone-unsigned-ipa/BolaClone-unsigned.ipa
```

Workflow: `.github/workflows/build-ipa.yml` (macOS runner, self-test + xcodebuild +
upload artifact).

### Cách 2 — macOS + Xcode

```bash
xcodebuild -project BolaClone.xcodeproj -scheme BolaClone \
  -sdk iphoneos -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p out/Payload
cp -R build/Build/Products/Release-iphoneos/BolaClone.app out/Payload/
(cd out && zip -qry ../BolaClone-unsigned.ipa Payload)
```

IPA sinh ra là **unsigned** — ký bằng eSign / TrollStore / AltStore trước khi cài.

### Không dùng được: Theos trên Linux

SDK công khai chỉ có `.swiftinterface`; compiler Linux không merge được Swift
overlay `Dispatch` với clang module cùng tên (SDK 16.5 build bằng Apple Swift 5.8.0).
`tools/build_theos.sh` sẽ dừng ở bước này — dùng macOS/CI thay thế.

## Key thủ công

Chưa dựng server key: nhập **`1`** ở màn hình key → lease offline 10 năm, không gọi mạng.

## Khi INJECT báo `ContainerAccessError error 0`

App không có quyền đọc/ghi container của Free Fire (sandbox). Ba cách:

1. **Xuất file thủ công** — Settings → “Xuất file patch (thủ công)”, rồi dùng Filza
   copy `Assembly-CSharp-patch.bytes`, `bolacfg.bin`, `.bola_tok` vào
   `/var/mobile/Containers/Data/Application/<UUID game>/Documents/`.
2. **Cài như app jailbreak + entitlements** (thiết bị đã jailbreak):
   ```bash
   cp -R BolaClone.app /var/jb/Applications/
   ldid -SBolaClone.entitlements /var/jb/Applications/BolaClone.app/BolaClone
   uicache -a
   ```
   `BolaClone.entitlements` xin `platform-application`,
   `AppDataContainers`, `no-sandbox`.
3. **Cắm primitive** — implement `KernelPrimitive` (xem
   `Sources/Core/KernelPrimitive.swift`); clone không kèm exploit.

## Cấu trúc

- `Sources/Core/` — logic: license, patch, trailer, config, container access
- `Sources/UI/` — SwiftUI (Home, Config, Key, Settings)
- `Resources/BolaminhducMenu.bytes` — patch IFix đóng gói kèm
- `verify/main.swift` — self-test
- `FIXES.md` — những gì đã bổ sung so với bản đọc ban đầu

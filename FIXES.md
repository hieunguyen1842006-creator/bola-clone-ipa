# BolaClone — những gì còn thiếu và đã bổ sung

Bản đọc ngày 2026-10-18. Đối chiếu 23 file Swift, `verify/main.swift`, `README`-less,
và symbol gốc trong `RE/swift_symbols.txt`.

## 1. Lỗi biên dịch (đã sửa)

| File | Lỗi | Sửa |
|---|---|---|
| `Sources/App/AppModel.swift` | `access.clearCaches?()` — protocol không có method, optional chaining trên non-optional | Thêm `clearCaches()` vào `ContainerAccess` + default rỗng |
| `Sources/Core/License.swift` | `Date().timeIntervalSince(last).hours` — `Double` không có `.hours` | `timeIntervalSince(last) / 86_400` |
| `Sources/Support/Theme.swift`, `Sources/UI/ConfigView.swift`, `Sources/UI/KeyScreenView.swift` | dùng `UIColor`/`UIApplication` mà chỉ import SwiftUI | thêm `#if canImport(UIKit) import UIKit #endif` |

## 2. Thiếu hẳn trailer license (đã bổ sung)

Đây là lỗi chức năng nặng nhất: clone ghi patch nguyên bản, không có 64 byte cuối.
Menu trong game đọc `patch[len-64 ..< len]` và đòi `|BOLATK1|` → luôn rơi vào nhánh
`⚠ CHƯA KÍCH HOẠT`.

- Thêm `Sources/Core/PatchTrailer.swift`:
  - decode/encode đúng 64 byte, marker `|BOLATK1|`
  - segment 1 = `hex(SHA256(.bola_tok))[:16]`
  - segment 2 = expiry Unix (giây)
  - segment 3 = `hex(SHA256(patch body))[:8]`
  - `attach` tự bóc trailer cũ (idempotent), `strip`, `isValid`
- `PatchDeployer.install`: ghi `.bola_tok` trước, gắn trailer sau, rồi mới ghi patch.
- `PatchDeployer.resyncTokenIfNeeded`: đổi key/gia hạn → ký lại trailer tại chỗ.
- `PatchDeployer.installedPatchInfo`: mô tả trailer đang cài.
- `PatchLibrary.hasValidTrailer(_:license:)`, `latest()`, `remoteURL`.
- `PatchLibrary.refreshRemote(completion:)`, `refreshFromGitHub(completion:)`.

## 3. Thiếu file patch trong bundle (đã bổ sung)

- Copy `BolaminhducMenu.bytes` (74.587 B, IFix) vào `Resources/`.
- `project.yml`: bỏ khai báo trùng ở `sources`, resource không còn `optional`.
- `tools/gen_pbxproj.py`: thêm fileRef/buildFile + Resources phase.
- `tools/check_project.py`: thêm mục 5b kiểm magic IFix, kích thước, tính đa dạng byte.

## 4. API gốc còn thiếu (đã thêm)

`Installer`:
- `patchExists(for:)`
- `containerPath(for:)`
- `hasAccess(to:)` / `canWriteIntoGame(_:)`
- `installedPatchInfo(for:)`
- `resyncTokenIfNeeded(for:)`
- `restore(game:)`

`AppModel`:
- `writeConfig()`
- `selfHealToken()`
- `attemptMHA()`
- `refreshKeyCard()`
- `refreshPatchRemote()`
- `restore()`
- `setEspThick`, `setHeadRate`, `setSilentFov`, `setCamFov`
- alias `append`, `showToast`

`LicenseGate`:
- `afterAuthorized()` + callback `onAuthorized`
- `LeaseStore.markServerOK()` / `lastOkKey()`

`ContainerAccess`:
- `documentsPath(for:)` (Direct / AppGroup / Chain / Path)

## 5. Cửa sổ offline (đã sửa)

`LicenseGate.isAuthorized` trước đây chỉ so hạn key, bỏ qua cache offline.
Giờ: quá `BolaOfflineMaxDays` (3 ngày) kể từ lần server xác nhận cuối → phải check lại.
Mọi lần activate/check thành công đều gọi `afterAuthorized()` để gia hạn mốc.

## 6. UI version gate (đã sửa)

`BolaCloneApp` chỉ chặn khi `killed`; server trả `blocked` (bản cũ) thì không hiện gì.
Giờ hiện `VersionGateView` cho cả `killed` và `blocked`.

## 7. Test (đã thêm)

`verify/main.swift` thêm nhóm kiểm tra `PatchTrailer`:
attach +64 byte, marker, decode, validate đúng/sai license, sửa body, strip,
attach lần 2 không cộng dồn, hết hạn, `hasValidTrailer`, và resync trong pipeline.

## 7b. Các lỗi nhỏ khác (đã sửa)

- `AppModel.defaultServer` đọc `BolaOfflineMaxDays` + `TserverPkgToken` từ Info.plist
  thay vì hard-code (`packageToken` trước đây luôn rỗng).
- `AppModel.inject`: `mhaActive` tính sai (`!skippedKernel`); giờ dựa vào
  `coordinator.lastMessage == "mha"`.
- `VersionGate.check`: reset `blocked/message` khi server báo bản mới đã ổn.
- `SettingsView` viết lại nút "Xoá" thành 2 statement (bỏ `;` giữa dòng).
- `Installer` giữ `access` để trả `containerPath(for:)`; `PathContainerAccess`
  đổi property nội bộ thành `documents` để không trùng tên method protocol.
- `PatchDeployer.install`: chỉ gắn trailer khi `.bola_tok` ghi thành công
  (trước đó vẫn gắn dù file token ghi lỗi → hash lệch).
- `BolaConfig` sửa comment CRC: file 28 byte → CRC ở offset 24 (không phải 16).

## 9. Build & test

### Linux/WSL — core logic (đã chạy thật)

- Swift 6.1.3 tải tay vào `~/swift` (Ubuntu 26.04 không có sẵn, không cần sudo).
- Ubuntu 26.04 thiếu `libxml2.so.2` và `libicu74`; giải nén cục bộ vào
  `~/swift-deps/root/usr/lib/x86_64-linux-gnu` rồi đưa vào `LD_LIBRARY_PATH`.
- `tools/build_linux.sh` → `swift build` + `swift run BolaSelfTest`.
- Kết quả: **86 checks, 0 failures** (SHA-256, CRC32, RGB565, BolaConfig, BolaToken,
  PatchTrailer, PatchDeployer, ExploitCoordinator, ContainerAccess).

### iOS app — chặn ở SDK, không phải ở code

Đã thử Theos (`iPhoneOS16.5.sdk`) + Swift 6.1.3 và Swift 5.8.1, nhiều tổ hợp
`-resource-dir` / `-I`, kể cả:
- resource-dir lai (`clang` của toolchain + `iphoneos` của SDK),
- toolchain macOS 6.1.3 (lấy binary `lib/swift/iphoneos`),
- patch `Dispatch.swiftinterface` để đổi clang module sang `CDispatch`.

Kết quả: SDK 16.5 được Apple build bằng **Apple Swift 5.8.0 (swiftlang-5.8.0)**;
compiler Linux (5.8.1 / 6.1.3) bị chặn bởi version check và/hoặc không merge được
overlay `Dispatch`:

```
Dispatch.swiftinterface: no type named 'DispatchQueue' in module 'Dispatch'
failed to build module 'Dispatch'; this SDK is not supported by the compiler
```

Đây là giới hạn toolchain/SDK, không phải lỗi source.

Cách lấy IPA: workflow `.github/workflows/bola-clone-ipa.yml` chạy trên macOS runner:
self-test → `xcodebuild` → đóng gói `BolaClone-unsigned.ipa` → upload Artifact.

## 10. Giới hạn còn lại (không tự bịa)

- **Giải mã `bolacfg.bin`**: IL có vòng biến đổi byte với hằng `0x5A` + `j*0x37` và
  các opcode chưa verify (`0x93`, `0x64`). Clone hiện ghi bản `plain` (magic `BOLA`
  + CRC32). Nếu patch thật giải mã trước khi so magic thì cần chốt opcode trước khi
  đổi writer — xem `BolaConfig.Obfuscation`.
- **Giải mã patch server**: binary gốc có `PatchClient.decrypt(_:secret:license:device:)`
  và `/api/client/secret`. Clone chưa có vì chưa có đặc tả server; hook đã có chỗ cắm
  (`PatchLibrary.fetchServerPatch`).
- **Kernel exploit / sandbox escape**: giữ nguyên ranh giới — chỉ có protocol
  `KernelPrimitive`, không kèm primitive chiếm quyền.

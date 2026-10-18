// BolaSelfTest — kiểm tra tầng logic: SHA-256, CRC32, RGB565, BolaConfig, BolaToken.
// Chạy: swift run BolaSelfTest     (0 = pass hết)
import Foundation
#if canImport(BolaCore)
import BolaCore
#endif

var failures = 0
var checks = 0

func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    checks += 1
    if ok {
        print("  ✅ \(name)")
    } else {
        failures += 1
        print("  ❌ \(name) \(detail)")
    }
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

print("=== SHA-256 (vector chuẩn) ===")
check("sha256(\"\") == e3b0c442…b855",
      SHA256.hexDigest("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
check("sha256(\"abc\") == ba7816bf…ad15",
      SHA256.hexDigest("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("sha256(448-bit) == 248d6a61…f3d2",
      SHA256.hexDigest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
        == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")

print("=== CRC32 (IEEE) ===")
check("crc32(\"123456789\") == CBF43926",
      CRC32.hash(Array("123456789".utf8)) == 0xCBF4_3926,
      String(format: "got %08X", CRC32.hash(Array("123456789".utf8))))

print("=== RGB565 (AppModel.pack565) ===")
let p = Pack565.pack(r: 255, g: 0, b: 0)
check("pack(255,0,0) == 0xF800", p == 0xF800, String(format: "got %04X", p))
let (r_, g_, b_) = Pack565.unpack(0x07E0)
check("unpack(0x07E0) ≈ (0,255,0)", r_ == 0 && g_ == 255 && b_ == 0,
      "got (\(r_),\(g_),\(b_))")

print("=== BolaConfig — writer phải khớp reader của patch ===")
let cfg = BolaConfig(flags: [.box, .hp],
                     extra: [.aim, .silent],
                     misc1: [.fastfire],
                     misc2: [.speedrun],
                     bone: .neck,
                     espThick: 120,
                     silentFov: 45,
                     aimFov: 60,
                     camFov: 95,
                     headRate: 80,
                     boxColor: 0xF800,
                     lineColor: 0x07E0,
                     boneColor: 0x001F)
let bytes = cfg.encoded()
let plain: [UInt8] = bytes[0..<24].enumerated().map { i, b in BolaConfig.obfuscate(i, b) }
check("độ dài == 28 (ngưỡng đọc của patch)", bytes.count == BolaConfig.size, "got \(bytes.count)")
check("magic \"BOLA\" sau khi bỏ XOR",
      Array(plain[0..<4]) == Array("BOLA".utf8),
      hex(Array(plain[0..<4])))
check("version == 1 ở offset 4", plain[4] == 1, String(format: "%02X", plain[4]))
check("ESP flags offset 5 = box|hp", plain[5] == 0b101, String(format: "%02X", plain[5]))
check("espThick offset 6 = 120", plain[6] == 120)
check("extra offset 7 = aim|silent", plain[7] == 0b101, String(format: "%02X", plain[7]))
check("bone offset 8 = 1 (neck)", plain[8] == 1)
check("RGB565 little-endian ở 9..14",
      plain[9] == 0x00 && plain[10] == 0xF8
      && plain[11] == 0xE0 && plain[12] == 0x07
      && plain[13] == 0x1F && plain[14] == 0x00)
check("silentFov offset 15 = 45", plain[15] == 45)
check("misc1 offset 16 = fastfire", plain[16] == 1)
check("misc2 offset 17 = speedrun", plain[17] == 32)
check("camFov/aimFov/headRate ở 18/19/20",
      plain[18] == 95 && plain[19] == 60 && plain[20] == 80)
check("CRC32 ở 4 byte CUỐI (offset 24, LE)",
      UInt32(bytes[24]) | UInt32(bytes[25]) << 8 | UInt32(bytes[26]) << 16 | UInt32(bytes[27]) << 24
        == CRC32.hash(Array(bytes[0..<24])))

let back = try? BolaConfig.decode(bytes)
check("decode(encode(x)) == x", back == cfg, "got \(String(describing: back))")

var bad = bytes; bad[0] ^= 0xFF
check("decode từ chối magic sai", (try? BolaConfig.decode(bad)) == nil)
var bad2 = bytes; bad2[4] ^= 0xFF
check("decode từ chối version sai", (try? BolaConfig.decode(bad2)) == nil)
var bad3 = bytes; bad3[10] ^= 0xFF
check("decode từ chối CRC sai", (try? BolaConfig.decode(bad3)) == nil)
check("decode từ chối file < 28 byte", (try? BolaConfig.decode(Array(bytes[0..<20]))) == nil)
check("crcOffset = len-4 (28→24, 24→20, 20→16)",
      BolaConfig.crcOffset(for: 28) == 24 && BolaConfig.crcOffset(for: 24) == 20
        && BolaConfig.crcOffset(for: 20) == 16)
check("XOR keystream đối xứng",
      (0..<24).allSatisfy { BolaConfig.obfuscate($0, BolaConfig.obfuscate($0, 0x42)) == 0x42 })
let clamped = BolaConfig(espThick: 250, silentFov: 250).encoded()
let clampedPlain: [UInt8] = clamped[0..<24].enumerated().map { i, b in BolaConfig.obfuscate(i, b) }
check("clamp espThick 50…200 / silentFov 5…100",
      clampedPlain[6] == 200 && clampedPlain[15] == 100)

print("=== BolaToken — khớp gate trong game (vm4) ===")
let key = "BOLA-TEST-0001"
let sig = SHA256.hexDigest(key)
let token = BolaToken(key: key, expiryUnix: 4_100_000_000, sig: sig)
let text = token.encodedString()
check("có prefix \(BolaToken.prefix)", text.hasPrefix(BolaToken.prefix), text)
check("sig = SHA256(key) hex (đúng cách patch hex-encode)",
      token.signatureIsValid())
check("độ dài sig = 64 hex", sig.count == 64)
let parsed = try? BolaToken.decode(text)
check("decode(encode) == x", parsed == token, "got \(String(describing: parsed))")
check("key sai → sig không hợp lệ",
      !BolaToken(key: key + "X", expiryUnix: 1, sig: sig).signatureIsValid())
check("hạn dùng: đã hết hạn", BolaToken(key: key, expiryUnix: 1_000_000, sig: sig).isExpired())
check("hạn dùng: còn sống", !BolaToken(key: key, expiryUnix: 4_100_000_000, sig: sig).isExpired())
check("ticks .NET epoch → unix 0", BolaToken.unixSeconds(fromDotNetTicks: 621_355_968_000_000_000) == 0)
check("ticks epoch + 10^7 → unix 1",
      BolaToken.unixSeconds(fromDotNetTicks: 621_355_968_000_000_000 + 10_000_000) == 1)
check("hoursLeft làm tròn giờ",
      BolaToken(key: key, expiryUnix: Int64(Date().timeIntervalSince1970) + 7200, sig: sig)
        .hoursLeft() == 2)

print("=== PatchTrailer — 64 byte cuối của Assembly-CSharp-patch.bytes ===")
let bodyData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
let licenseText = token.encodedString()
let attached = (try? PatchTrailer.attach(to: bodyData, license: licenseText,
                                         expiryUnix: 4_100_000_000)) ?? Data()
check("attach thêm đúng 64 byte", attached.count == bodyData.count + 64,
      "got \(attached.count)")
let tailText = String(data: attached.suffix(64), encoding: .utf8) ?? ""
check("64 byte cuối bắt đầu bằng \(PatchTrailer.marker)",
      tailText.hasPrefix(PatchTrailer.marker), tailText)
check("decode được trailer", PatchTrailer.decode(from: attached) != nil)
check("validate khớp license + body", PatchTrailer.isValid(patch: attached, license: licenseText))
check("validate sai license → false",
      !PatchTrailer.isValid(patch: attached, license: licenseText + "X"))
var tampered = attached
tampered[0] ^= 0xFF
check("sửa body → bodySig sai", !PatchTrailer.isValid(patch: tampered, license: licenseText))
check("strip trả lại đúng body", PatchTrailer.strip(from: attached) == bodyData)
let reattached = (try? PatchTrailer.attach(to: attached, license: licenseText,
                                           expiryUnix: 4_100_000_000)) ?? Data()
check("attach lần 2 không cộng dồn trailer", reattached.count == attached.count,
      "got \(reattached.count)")
check("trailer hết hạn → false",
      !PatchTrailer.isValid(patch: attached, license: licenseText,
                            now: Date(timeIntervalSince1970: 4_200_000_000)))
check("patch không có trailer → decode nil", PatchTrailer.decode(from: bodyData) == nil)
let trailerFile = NSTemporaryDirectory() + "bola-trailer-test.bytes"
try? attached.write(to: URL(fileURLWithPath: trailerFile))
let libForTrailer = PatchLibrary(config: ServerConfig(baseURL: URL(string: "https://example.invalid")!))
check("PatchLibrary.hasValidTrailer(license:) đúng",
      libForTrailer.hasValidTrailer(URL(fileURLWithPath: trailerFile), license: licenseText))
check("PatchLibrary.hasValidTrailer sai license → false",
      !libForTrailer.hasValidTrailer(URL(fileURLWithPath: trailerFile), license: "khac"))
try? FileManager.default.removeItem(atPath: trailerFile)

print("=== KeyMask ===")
check("mask giữ đầu/cuối", KeyMask.mask("ABCDEFGH1234") == "ABCD-••••-1234",
      KeyMask.mask("ABCDEFGH1234"))
check("mask key ngắn", KeyMask.mask("abc").contains("•"))

print("=== PatchDeployer / ContainerAccess (fake container) ===")
final class MemAccess: ContainerAccess {
    var store: [String: Data] = [:]
    let label = "memory"
    func isAvailable(for game: GameTarget) -> Bool { true }
    func write(_ data: Data, to name: String, in game: GameTarget) throws { store[name] = data }
    func read(_ name: String, in game: GameTarget) throws -> Data? { store[name] }
    func remove(_ name: String, in game: GameTarget) throws { store.removeValue(forKey: name) }
}
let mem = MemAccess()
let lib = PatchLibrary(config: ServerConfig(baseURL: URL(string: "https://example.invalid")!))
let dep = PatchDeployer(access: mem, library: lib)
_ = dep.install(patchData: Data([0x01, 0x02, 0x03]), config: cfg, token: token, game: .freefireMAX)
check("patch ghi đúng tên Assembly-CSharp-patch.bytes",
      mem.store["Assembly-CSharp-patch.bytes"] != nil)
check("patch đã được gắn trailer (+64 byte)",
      mem.store["Assembly-CSharp-patch.bytes"]?.count == 3 + PatchTrailer.length,
      "got \(mem.store["Assembly-CSharp-patch.bytes"]?.count ?? -1)")
check("trailer khớp token đã ghi",
      mem.store["Assembly-CSharp-patch.bytes"].map {
          PatchTrailer.isValid(patch: $0, license: token.encodedString())
      } ?? false)
check("nvhcfg.bin ghi đúng 28 byte", mem.store[PatchLibrary.configFileName]?.count == 28)
check("nvhcfg.bin decode lại được",
      (try? BolaConfig.decode([UInt8](mem.store[PatchLibrary.configFileName]!))) != nil)
check(".nvhtok ghi đúng nội dung",
      (mem.store[PatchLibrary.tokenFileName].flatMap { String(data: $0, encoding: .utf8) } ?? "")
        .hasPrefix(BolaToken.prefix))
let removed = dep.uninstall(game: .freefireMAX)
check("uninstall xoá 3 file (patch + cfg + token)", removed == 3, "got \(removed)")
check("isInstalled = false sau khi gỡ", !dep.isInstalled(game: .freefireMAX))

print("=== Version.compare ===")
check("1.0.0 < 1.0.1", Version.compare("1.0.0", "1.0.1") < 0)
check("1.2 == 1.2.0", Version.compare("1.2", "1.2.0") == 0)
check("2.0 > 1.9.9", Version.compare("2.0", "1.9.9") > 0)

print("=== Container layer — ExploitCoordinator + primitive (mock) ===")
let tmpRoot = NSTemporaryDirectory() + "bola-selftest"
try? FileManager.default.removeItem(atPath: tmpRoot)
try? FileManager.default.createDirectory(atPath: tmpRoot, withIntermediateDirectories: true)

// a) chua cam primitive -> phai that bai va KHONG ghi gi
let emptyChain = ContainerAccessChain([])
let c1 = ExploitCoordinator(directProviders: [emptyChain], primitive: nil)
let r1 = await c1.ensureReady(for: .freefireMAX)
var r1Failed = false
if case .failure = r1 { r1Failed = true }
check("chưa cắm primitive -> failure (không ghi gì)", r1Failed)

// b) cam mock primitive -> chay du 2 tang, ra duong ghi that
let mock = MockContainerPrimitive(label: "selftest-mock", documentsRoot: tmpRoot)
let c2 = ExploitCoordinator(directProviders: [emptyChain], primitive: mock)
var logs2: [String] = []
c2.onLog = { logs2.append($0) }
let r2 = await c2.ensureReady(for: .freefireMAX)
var access2: ContainerAccess?
if case .success(let a) = r2 { access2 = a }
check("cắm primitive -> success", access2 != nil)
check("có chạy tầng 1 (kernel r/w)", mock.kernelPrepared)
check("có chạy tầng 2 cho đúng game", mock.containerPrepared.contains(.freefireMAX))
check("log có 'exploit: 1/2 kernel r/w'",
      logs2.contains { $0.contains("exploit: 1/2 kernel r/w") }, logs2.joined(separator: " | "))
check("log có 'exploit: 2/2 sandbox escape (3105 build)'",
      logs2.contains { $0.contains("exploit: 2/2 sandbox escape (3105 build)") })
check("log có 'exploit: kernel r/w established'",
      logs2.contains { $0.contains("exploit: kernel r/w established") })

// c) full pipeline qua access vua co: patch + cfg + token + verify marker
if let acc = access2 {
    let dep2 = PatchDeployer(access: acc, library: lib)
    let out2 = dep2.install(patchData: Data([0xAA, 0xBB, 0xCC]), config: cfg, token: token,
                            game: .freefireMAX)
    check("pipeline qua primitive: cài thành công", out2.ok, out2.message)
    let pBytes = (try? acc.read("Assembly-CSharp-patch.bytes", in: .freefireMAX)) ?? nil
    check("patch đọc lại đúng body (bỏ 64 byte trailer)",
          pBytes.map { PatchTrailer.strip(from: $0) } == Data([0xAA, 0xBB, 0xCC]))
    check("trailer của patch đọc lại hợp lệ",
          pBytes.map { PatchTrailer.isValid(patch: $0, license: token.encodedString()) } ?? false)
    check("patchExists(for:) thấy patch",
          dep2.isInstalled(game: .freefireMAX))
    check("installedPatchInfo có mô tả trailer",
          dep2.installedPatchInfo(for: .freefireMAX)?.contains("trailer") == true)
    let newer = BolaToken(key: key, expiryUnix: 4_100_000_500, sig: sig)
    check("resyncTokenIfNeeded ký lại khi token đổi",
          dep2.resyncTokenIfNeeded(for: .freefireMAX, token: newer))
    let resynced = (try? acc.read("Assembly-CSharp-patch.bytes", in: .freefireMAX)) ?? nil
    check("sau resync trailer khớp token mới",
          resynced.map {
              PatchTrailer.isValid(patch: $0, license: newer.encodedString())
          } ?? false)
    let cfgBack = (try? acc.read(PatchLibrary.configFileName, in: .freefireMAX)) ?? nil
    check("nvhcfg.bin đọc lại decode được",
          (try? BolaConfig.decode([UInt8](cfgBack ?? Data()))) != nil)
    let tokBack = (try? acc.read(PatchLibrary.tokenFileName, in: .freefireMAX)) ?? nil
    check("token đọc lại verify được chữ ký",
          ((try? BolaToken.decode(String(data: tokBack ?? Data(), encoding: .utf8) ?? ""))?.signatureIsValid() ?? false))
    check("gỡ patch xoá đủ 3 file", dep2.uninstall(game: .freefireMAX) == 3)
}

// d) duong an toan truoc: direct access co san -> BO QUA kernel
final class AlwaysAccess: ContainerAccess {
    let label = "always"
    func isAvailable(for game: GameTarget) -> Bool { true }
    func write(_ d: Data, to n: String, in g: GameTarget) throws {}
    func read(_ n: String, in g: GameTarget) throws -> Data? { nil }
    func remove(_ n: String, in g: GameTarget) throws {}
}
let mock2 = MockContainerPrimitive(label: "must-not-run", documentsRoot: tmpRoot)
let c3 = ExploitCoordinator(directProviders: [AlwaysAccess()], primitive: mock2)
var logs3: [String] = []
c3.onLog = { logs3.append($0) }
_ = await c3.ensureReady(for: .freefireMAX)
check("đường direct có sẵn -> bỏ qua kernel", c3.skippedKernel && !mock2.kernelPrepared)
check("log có 'bỏ qua kernel (an toàn hơn)'",
      logs3.contains { $0.contains("bỏ qua kernel (an toàn hơn)") })

// e) kernel stage lỗi -> KHÔNG chạy tầng 2, có teardown
let mockBad = MockContainerPrimitive(label: "bad-kernel", documentsRoot: tmpRoot, failKernel: true)
let c4 = ExploitCoordinator(directProviders: [emptyChain], primitive: mockBad)
let r4 = await c4.ensureReady(for: .freefireMAX)
var r4Failed = false
if case .failure = r4 { r4Failed = true }
check("kernel stage lỗi -> failure", r4Failed)
check("kernel stage lỗi -> KHÔNG chạy tầng 2", mockBad.containerPrepared.isEmpty)
check("kernel stage lỗi -> đã teardown", mockBad.tornDown)

// f) SandboxGrant: hợp lệ/không hợp lệ + consume với token rỗng
check("grant rỗng -> không dùng được", !SandboxGrant(containerDocuments: nil, token: Data()).isUsable)
check("grant có path -> dùng được", SandboxGrant(containerDocuments: "/tmp/x").isUsable)
check("grant có token -> dùng được", SandboxGrant(containerDocuments: nil, token: Data([1, 2])).isUsable)
check("consume() token rỗng -> true (không cần consume)", SandboxGrant(containerDocuments: "/tmp").consume())

// g) PathContainerAccess kiem chung quyen that
let pacc = PathContainerAccess(documentsPath: tmpRoot, label: "tmp")
check("PathContainerAccess thấy thư mục ghi được", pacc.isAvailable(for: .freefireMAX))
let paccBad = PathContainerAccess(documentsPath: "/khong-ton-tai-\(UUID().uuidString)", label: "bad")
check("PathContainerAccess từ chối đường dẫn không tồn tại", !paccBad.isAvailable(for: .freefireMAX))
try? FileManager.default.removeItem(atPath: tmpRoot)

print("")
print("checks: \(checks) | failures: \(failures)")
exit(failures == 0 ? 0 : 1)

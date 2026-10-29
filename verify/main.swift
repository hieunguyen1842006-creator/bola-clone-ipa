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
let plain: [UInt8] = bytes[0..<BolaConfig.payloadSize].enumerated().map { i, b in BolaConfig.obfuscate(i, b) }
check("độ dài == BolaConfig.size", bytes.count == BolaConfig.size, "got \(bytes.count)")
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
check("textScale/drawDist ở 23/24 = 100/100",
      plain[23] == 100 && plain[24] == 100)
let cStart = BolaConfig.payloadSize
let cEnd = bytes.count - 4
check("CRC32 ở 4 byte CUỐI, LE",
      UInt32(bytes[cStart]) | UInt32(bytes[cStart + 1]) << 8
        | UInt32(bytes[cStart + 2]) << 16 | UInt32(bytes[cStart + 3]) << 24
        == CRC32.hash(Array(bytes[0..<cStart])) && cEnd == cStart)

let back = try? BolaConfig.decode(bytes)
check("decode(encode(x)) == x", back == cfg, "got \(String(describing: back))")

var bad = bytes; bad[0] ^= 0xFF
check("decode từ chối magic sai", (try? BolaConfig.decode(bad)) == nil)
var bad2 = bytes; bad2[4] ^= 0xFF
check("decode từ chối version sai", (try? BolaConfig.decode(bad2)) == nil)
var bad3 = bytes; bad3[10] ^= 0xFF
check("decode từ chối CRC sai", (try? BolaConfig.decode(bad3)) == nil)
check("decode từ chối file ngắn (< BolaConfig.minSize)",
      (try? BolaConfig.decode(Array(bytes[0..<20]))) == nil)

// Bản cũ ghi 28 byte (24 payload): byte 21/22/23 = 0, không có byte 24.
var legacy = Array(bytes[0..<24])
for i in 21...23 { legacy[i] = BolaConfig.obfuscate(i, 0) }
let lcrc = CRC32.hash(legacy)
var legacyFile = legacy
legacyFile.append(contentsOf: [UInt8(lcrc & 0xFF), UInt8((lcrc >> 8) & 0xFF),
                               UInt8((lcrc >> 16) & 0xFF), UInt8((lcrc >> 24) & 0xFF)])
let legacyCfg = try? BolaConfig.decode(legacyFile)
check("decode file 28 byte cũ ⇒ textScale/drawDist về 100, drag/wall tắt",
      legacyCfg?.textScale == 100 && legacyCfg?.drawDist == 100
        && legacyCfg?.dragHead == false && legacyCfg?.wallCheck == false,
      String(describing: legacyCfg))

check("crcOffset = len-4 (30→26, 28→24, 20→16)",
      BolaConfig.crcOffset(for: 28) == 24 && BolaConfig.crcOffset(for: 24) == 20
        && BolaConfig.crcOffset(for: 20) == 16)
check("XOR keystream đối xứng",
      (0..<BolaConfig.payloadSize).allSatisfy { BolaConfig.obfuscate($0, BolaConfig.obfuscate($0, 0x42)) == 0x42 })
let clamped = BolaConfig(espThick: 250, silentFov: 250).encoded()
let clampedPlain: [UInt8] = clamped[0..<BolaConfig.payloadSize].enumerated().map { i, b in BolaConfig.obfuscate(i, b) }
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
check("nvhcfg.bin ghi đúng BolaConfig.size",
      mem.store[PatchLibrary.configFileName]?.count == BolaConfig.size)
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

print("=== DNSBlocklist — blocklist JSON → denylist ===")
let abRules = DNSBlocklist.load(Data(DNSBlocklist.defaultJSON.utf8))
check("parse defaultJSON == 1 rule", abRules.count == 1, "got \(abRules.count)")
check("rule giữ nguyên url gốc (\\. sau sanitize)",
      abRules.first?.url.contains(#"\."#) == true, abRules.first?.url ?? "nil")
let abDomains = DNSBlocklist.domains(fromPattern: abRules.first?.url ?? "")
check("4 apex domains (telemetry only)",
      abDomains == ["adjust.com", "app-measurement.com", "appsflyer.com",
                    "crashlytics.com"],
      "got \(abDomains)")
// Regression guard v3: KHÔNG được chặn API/CDN tài nguyên của game
// (chặn freefiremobile.com / garenanow.com là game không tải được tài nguyên).
check("denylist ADG KHÔNG chặn API/CDN game",
      !DNSBlocklist.denylistADG(abDomains).contains("||freefiremobile.com^")
      && !DNSBlocklist.denylistADG(abDomains).contains("||garenanow.com^"))
check("denylist hosts có 0.0.0.0 app-measurement.com",
      DNSBlocklist.denylistHosts(abDomains).contains("0.0.0.0 app-measurement.com"))
check("denylistADG(rules) bỏ rule disabled",
      DNSBlocklist.denylistADG([abRules[0],
                                DNSBlocklistRule(enabled: false, name: "x", note: "", url: #"evil\.example"#, script: "")])
        .contains("||evil.example^") == false)
check("JSON escape không hợp lệ (\\.) vẫn parse được", !abRules.isEmpty)

print("=== AES-128 (FIPS-197 vector) ===")
let aesKey: [UInt8] = (0...15).map { UInt8($0) }
let aesPt: [UInt8] = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                      0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
let aesW = AES128.expandKey(aesKey)
var aesBlock = aesPt
AES128.encryptBlock(&aesBlock, roundKeys: aesW)
check("AES-128 encrypt FIPS-197",
      aesBlock == [0x69, 0xC4, 0xE0, 0xD8, 0x6A, 0x7B, 0x04, 0x30,
                   0xD8, 0xCD, 0xB7, 0x80, 0x70, 0xB4, 0xC5, 0x5A],
      hex(aesBlock))
var aesBack = aesBlock
AES128.decryptBlock(&aesBack, roundKeys: aesW)
check("AES-128 decrypt trả về bản rõ", aesBack == aesPt, hex(aesBack))

let cbcIv = [UInt8](repeating: 0, count: 16)
let cbcPt: [UInt8] = Array("NVH-TEST-PATCH-PAYLOAD-0123456789".utf8) // 33 byte
check("CBC từ chối độ dài lẻ", AES128.cbcEncrypt(key: aesKey, iv: cbcIv, data: cbcPt) == nil)

print("=== ResD — khoá + container ===")
check("dotNetHash(\"HeroSkin_1\") == d62be269",
      ResD.dotNetHashUpper("HeroSkin_1") == 0xD62B_E269,
      String(format: "%08x", ResD.dotNetHashUpper("HeroSkin_1")))
check("mixedKey(\"HeroSkin_1\") == f0869a66…",
      Array(ResD.mixedKey(resName: "HeroSkin_1").prefix(4)) == [0xF0, 0x86, 0x9A, 0x66],
      hex(ResD.mixedKey(resName: "HeroSkin_1")))
check("hash không phân biệt hoa/thường",
      ResD.dotNetHashUpper("heroskin_1") == ResD.dotNetHashUpper("HeroSkin_1"))
check("resName(forFile:) bỏ đuôi + thư mục",
      ResD.resName(forFile: "Thanos/HeroSkin_1.bytes") == "HeroSkin_1")

// vector mã hoá cố định (Python tạo): plain 33 byte + tag 103 + resName TestSkin_1
let resdBlob: [UInt8] = [
    0x22, 0x4A, 0x67, 0x00, 0x21, 0x00, 0x00, 0x00,
    0x4C, 0x5E, 0x1A, 0x80, 0xE1, 0x9E, 0xFA, 0xBA,
    0x9A, 0xBC, 0xB4, 0x18, 0xCB, 0xCE, 0x22, 0xE5,
    0x61, 0xA8, 0x39, 0xE0, 0x19, 0xC0, 0x0B, 0xE9,
    0xCB, 0xF3, 0xAF, 0x16, 0x7B, 0x53, 0x8C, 0xD0,
    0x5F, 0x74, 0x7A, 0x70, 0x49, 0x27, 0x0C, 0x18,
    0x99, 0x7E, 0x75, 0x61, 0x97, 0xA2, 0xA0, 0xB5,
]
let dec = try? ResD.decrypt(resdBlob, resName: "TestSkin_1")
check("ResD decrypt ra đúng plaintext 33 byte",
      (dec?.plain ?? []) == cbcPt, "\(dec?.plain.count ?? -1) byte")
check("ResD decrypt giữ tag 103 + encrypted=true",
      dec?.tag == 103 && dec?.encrypted == true)
let reEnc = dec.map { ResD.encrypt($0.plain, resName: "TestSkin_1", tag: $0.tag) } ?? []
check("ResD encrypt round-trip byte-exact", reEnc == resdBlob,
      "len \(reEnc.count) vs \(resdBlob.count)")
check("ResD từ chối magic sai", (try? ResD.decrypt([0x00, 0x00, 0, 0, 0, 0, 0, 0], resName: "x")) == nil)
check("ResD từ chối body lệch block",
      (try? ResD.decrypt([0x22, 0x4A, 0x67, 0x00, 0xFF, 0, 0, 0] + [UInt8](repeating: 1, count: 17),
                         resName: "x")) == nil)

// container plain (kiểu LQHud: tag 0, body là IFix trần)
let fakeIFixPlain: [UInt8] = Lqmb.magicLqmb + [UInt8](repeating: 0x41, count: 16)
let plainContainer = ResD.encrypt(fakeIFixPlain, resName: "LQHud", tag: 0, encrypt: false)
check("ResD container plain: head đúng magic + origLen",
      Array(plainContainer.prefix(8)) == [0x22, 0x4A, 0x00, 0x00,
                                          24, 0, 0, 0],
      hex(Array(plainContainer.prefix(8))))
let plainBack = try? ResD.decrypt(plainContainer, resName: "LQHud")
check("ResD plain round-trip giữ nguyên body + encrypted=false",
      (plainBack?.plain ?? []) == fakeIFixPlain && plainBack?.encrypted == false)

print("=== Lqmb — parse/serialize/round-trip ===")
// Dựng một patch tối thiểu đúng layout rồi round-trip (không cần file thật trong CI).
var synth = Lqmb.Patch()
synth.bridge = "IFix.Bridge"
synth.types = ["A.B, Asm", "CameraSystem, Asm"]
synth.nextAlloc = 1
var blk0 = Lqmb.Block()
blk0.instrs = [LqOpcode.blockHeader, 0x0001_0002,
               LqOpcode.ldstr, 0,
               LqOpcode.ldcR4, Int32(bitPattern: Float(1.599).bitPattern),
               LqOpcode.ret, 1]
blk0.handlers = [[0, 0, 1, 0, 0, 0]]
synth.blocks = [blk0]
var m0 = Lqmb.MethodRec()
m0.declType = 1
m0.name = "GetZoomRate"
m0.params = [Lqmb.Param(isName: false, id: 0, name: "")]
synth.methods = [m0]
synth.strings = ["iFix.Camera.Zoom.v1"]
var f0 = Lqmb.FieldRec()
f0.isNew = false
f0.declType = 0
f0.name = "cache"
synth.fields = [f0]
synth.fsvm = [(1, 2)]
var an0 = Lqmb.AnonType()
an0.fieldIds = [0]
an0.ctor = 1
an0.paramCount = 2
an0.interfaces = [(3, 4)]
an0.vtable = [5]
synth.anon = [an0]
synth.wrapper = "wrapper"
synth.idmap = "idmap"
var hook0 = Lqmb.Hook()
hook0.method = m0
hook0.vm = 0
synth.interpret = [hook0]
synth.newClasses = ["New.Class"]
synth.trailer = [0xDE, 0xAD, 0xBE, 0xEF]

let ser = (try? Lqmb.serialize(synth)) ?? []
check("serialize ra blob bắt đầu bằng magic LQMB",
      Array(ser.prefix(8)) == Lqmb.magicLqmb, hex(Array(ser.prefix(8))))
let reparsed = try? Lqmb.parse(ser)
check("parse(serialize(x)) giữ số block/instr/hook",
      reparsed?.blocks.count == 1
        && reparsed?.totalInstructions == 4
        && reparsed?.interpret.count == 1,
      "blocks=\(reparsed?.blocks.count ?? -1) instr=\(reparsed?.totalInstructions ?? -1)")
check("parse giữ nguyên trailer thô",
      (reparsed?.trailer ?? []) == [0xDE, 0xAD, 0xBE, 0xEF])
check("serialize(parse(serialize(x))) byte-exact",
      (reparsed.flatMap { try? Lqmb.serialize($0) }) == ser)
check("qualifiedName đúng dạng Owner::Method",
      reparsed?.qualifiedName(hook0.method) == "CameraSystem::GetZoomRate",
      reparsed?.qualifiedName(hook0.method) ?? "nil")
check("parse từ chối magic lạ",
      (try? Lqmb.parse([0x00, 0, 0, 0, 0, 0, 0, 0] + [UInt8](repeating: 0, count: 32))) == nil)
var badNext = synth
badNext.nextAlloc = 5
check("serialize từ chối next_alloc lệch", (try? Lqmb.serialize(badNext)) == nil)

print("=== LqPatcher — sửa zoom / privacy / host / tag ===")
var patchTarget = synth
let zoomRep = LqPatcher.apply(&patchTarget,
                              config: LqConfig(zoom: 2.0, privacyOff: true,
                                               fakeHost: true, tagText: "NVH v4!"))
check("patch zoom ghi đè Ldc_R4 → bits của 2.0f",
      patchTarget.blocks[0].instrs[5] == Int32(bitPattern: Float(2.0).bitPattern),
      String(format: "0x%08X", UInt32(bitPattern: patchTarget.blocks[0].instrs[5])))
check("có ít nhất 1 site zoom được báo", zoomRep.zoomSites >= 1, "\(zoomRep.zoomSites)")
check("không đổi số lệnh sau patch",
      patchTarget.blocks[0].instrs.count == blk0.instrs.count)
let patchedSer = (try? Lqmb.serialize(patchTarget)) ?? []
check("patch xong vẫn round-trip được",
      (try? Lqmb.parse(patchedSer))?.blocks.count == 1)
var tagTarget = synth
tagTarget.strings = ["prefix [skin v4] suffix"]
let tagRep = LqPatcher.apply(&tagTarget, config: LqConfig(tagText: "NVH v4!"))
check("tag cùng độ dài → thay được", tagRep.stringSites == 1, "\(tagRep.stringSites)")
check("tag giữ nguyên độ dài UTF-8 của chuỗi",
      tagTarget.strings[0].utf8.count == "prefix [skin v4] suffix".utf8.count)
var tagBad = synth
tagBad.strings = ["[skin v4]"]
let tagBadRep = LqPatcher.apply(&tagBad, config: LqConfig(tagText: "TOO-LONG-TAG"))
check("tag khác độ dài → từ chối + ghi note",
      tagBadRep.stringSites == 0 && tagBad.strings[0] == "[skin v4]"
        && !tagBadRep.notes.isEmpty)
check("config rỗng → isEmpty true", LqConfig().isEmpty)
check("config có zoom → isEmpty false", !LqConfig(zoom: 2).isEmpty)

print("=== LienQuanDeployer — lọc file + bundle LQ2 ===")
check("patchableFiles chỉ nhận HeroSkin_*.bytes",
      LienQuanDeployer.patchableFiles(in: ["HeroSkin_1.bytes", "HeroSkin_2.bytes",
                                           ".nvh_probe", "readme.txt",
                                           "HeroSkin_1.bytes.bak"]) == ["HeroSkin_1.bytes",
                                                                        "HeroSkin_2.bytes"],
      "\(LienQuanDeployer.patchableFiles(in: ["HeroSkin_1.bytes", "HeroSkin_2.bytes", ".nvh_probe", "readme.txt", "HeroSkin_1.bytes.bak"]))")
check("gói runtime không cần payload trong app",
      !LQPack.runtime.usesBundledPayload && LQPack.runtime.vaultResource == nil)
check("gói bundled vẫn trỏ vault đúng",
      LQPack.hudFull.vaultResource == "LQHud"
        && LQPack.nvhBeta.vaultResource == "NVHLQ"
        && LQPack.unlockSkin.vaultResource == "LQUnlock")

print("=== LqGenerator — sinh patch tu zero ===")
var genCfg = LqConfig()
genCfg.zoom = 2.0
let genPatch = LqGenerator.zoomPatch(zoom: 2.0)
check("zoomPatch sinh được 1 block + 1 hook",
      genPatch.blocks.count == 1 && genPatch.interpret.count == 1,
      "blocks=\(genPatch.blocks.count) hooks=\(genPatch.interpret.count)")
check("hook trỏ đúng CameraSystem::GetZoomRate",
      genPatch.interpret.first.map {
          genPatch.qualifiedName($0.method) == "CameraSystem::GetZoomRate"
      } ?? false,
      genPatch.interpret.first.map { genPatch.qualifiedName($0.method) } ?? "nil")
let genCheck = LqGenerator.verify(genPatch)
check("patch tự sinh verify OK (round-trip byte-exact)", genCheck.ok, genCheck.detail)
check("blob tự sinh bắt đầu bằng magic LQMB",
      ((try? Lqmb.serialize(genPatch))?.prefix(8)).map(Array.init) == Lqmb.magicLqmb)
check("IL zoom có Ldc_R4 = bits của 2.0f",
      genPatch.blocks.first?.instrs.contains(Int32(bitPattern: Float(2.0).bitPattern)) ?? false)
check("IL zoom gọi PlayerPrefs::GetFloat",
      genPatch.methods.contains { $0.name == "GetFloat" })
check("IL zoom gọi CameraSystem::get_ZoomRateFromAge",
      genPatch.methods.contains { $0.name == "get_ZoomRateFromAge" })
check("key PlayerPrefs nằm trong strings",
      genPatch.strings.contains(LqGenerator.zoomPrefKey),
      genPatch.strings.joined(separator: ","))

var fullCfg = LqConfig()
fullCfg.zoom = 3.0
fullCfg.privacyOff = true
fullCfg.fakeHost = true
let fullPatch = LqGenerator.makePatch(fullCfg)
check("makePatch đủ 3 tính năng → 4 hook (zoom + 2 privacy + host)",
      fullPatch?.interpret.count == 4, "\(fullPatch?.interpret.count ?? -1)")
check("patch đầy đủ verify OK",
      fullPatch.map { LqGenerator.verify($0).ok } ?? false)
check("có 2 overload IsPrivaceOn",
      fullPatch?.interpret.filter {
          fullPatch?.qualifiedName($0.method).hasSuffix("IsPrivaceOn") ?? false
      }.count == 2)
check("config rỗng → makePatch trả nil", LqGenerator.makePatch(LqConfig()) == nil)
check("ResD bọc patch tự sinh rồi giải lại khớp",
      {
          guard let p = fullPatch, let blob = try? Lqmb.serialize(p) else { return false }
          let wrapped = ResD.encrypt(blob, resName: "HeroSkin_1", tag: 103)
          guard let back = try? ResD.decrypt(wrapped, resName: "HeroSkin_1") else { return false }
          return back.plain == blob && back.tag == 103
      }())

// ── assembly: patch tự sinh phải nằm trong file cùng assembly ─────────────
print("=== LqGenerator — chọn file theo assembly ===")
check("generatorAssembly == Project_d (nơi có CameraSystem)",
      LienQuanDeployer.generatorAssembly == "Project_d")
check("generatedFileName == HeroSkin_1.bytes",
      LienQuanDeployer.generatedFileName == "HeroSkin_1.bytes")
check("patch tự sinh khai bridge Project_d",
      genPatch.bridge.contains(", Project_d,"),
      genPatch.bridge)
// assemblyOf phải đọc đúng tên assembly từ bridge
let bridgeSample = ResD.Container(tag: 103, origLen: 0, plain: [], encrypted: true)
check("assemblyOf trả nil với container rỗng (không parse được)",
      LienQuanDeployer.assemblyOf(bridgeSample) == nil)
check("blob tự sinh parse lại giữ nguyên bridge",
      (try? Lqmb.parse((try? Lqmb.serialize(genPatch)) ?? []))?.bridge == genPatch.bridge)

// Type string phải khớp CHÍNH XÁC với game — sai namespace/assembly là game treo.
print("=== LqGenerator — type string khớp game ===")
check("CameraSystem ở Project_d",
      LqGenerator.tCamSys == "CameraSystem, Project_d, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null",
      LqGenerator.tCamSys)
check("PlayerPrefs ở UnityEngine.CoreModule",
      LqGenerator.tPrefs.hasPrefix("UnityEngine.PlayerPrefs, UnityEngine.CoreModule,"),
      LqGenerator.tPrefs)
check("CRoleInfoManager ở Project_d",
      LqGenerator.tRoleMgr.hasPrefix("Assets.Scripts.GameSystem.CRoleInfoManager, Project_d,"),
      LqGenerator.tRoleMgr)
check("CPlayerProfile ở Project_d",
      LqGenerator.tProfile.hasPrefix("Assets.Scripts.GameSystem.CPlayerProfile, Project_d,"),
      LqGenerator.tProfile)
// BUG ĐÃ SỬA: COM_USER_PRIVACY_MASK ở CSProtocol/AovTdr, không phải Project_d
check("COM_USER_PRIVACY_MASK ở CSProtocol + AovTdr (không phải Project_d)",
      LqGenerator.tPrivMask == "CSProtocol.COM_USER_PRIVACY_MASK, AovTdr, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null",
      LqGenerator.tPrivMask)
check("patch privacy dùng đúng type mask",
      fullPatch?.types.contains(LqGenerator.tPrivMask) ?? false,
      (fullPatch?.types ?? []).filter { $0.contains("PRIVACY") }.joined(separator: ","))
check("GetFloat khai 2 param (String, Single)",
      fullPatch?.methods.first { $0.name == "GetFloat" }.map { $0.params.count == 2 } ?? false)

print("")
print("checks: \(checks) | failures: \(failures)")
exit(failures == 0 ? 0 : 1)

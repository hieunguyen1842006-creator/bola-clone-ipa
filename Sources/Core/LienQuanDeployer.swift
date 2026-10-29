import Foundation

/// Gói hotfix của Liên Quân.
///
/// Hai kiểu:
///   - **bundled**: payload IFix đóng sẵn trong vault (gói của người khác, ghi nguyên file).
///   - **runtime**: đọc file `.bytes` gốc **trong máy game**, giải mã, sửa IL theo cấu hình,
///     mã hoá lại rồi ghi — không cần payload đóng sẵn.
public enum LQPack: String, CaseIterable, Identifiable {
    case runtime = "runtime"
    case hudFull = "hud"
    case nvhBeta = "nvhbeta"
    case unlockSkin = "unlock"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .runtime: return "Patch máy (runtime)"
        case .hudFull: return "Full HUD"
        case .nvhBeta: return "CAMXA FullSkin"
        case .unlockSkin: return "4in1 LiqiMobi"
        }
    }

    public var subtitle: String {
        switch self {
        case .runtime:
            return "Đọc file gốc trong game → giải mã → sửa zoom/privacy/host → ghi lại. Không cần payload ngoài."
        case .hudFull:
            return "HUD địch: máu, tên, CD chiêu, vòng + icon 5 hero, kèm unlock skin"
        case .nvhBeta:
            return "FullSkin + ESP Liqi — bản 20/10 (ghi HeroSkin_1 + HeroSkin_2)"
        case .unlockSkin:
            return "Gói 4in1 LiqiMobi 16/10 (FullSkin/HUD/ESP) — HeroSkin_1 + HeroSkin_2"
        }
    }

    public var symbol: String {
        switch self {
        case .runtime: return "wand.and.stars"
        case .hudFull: return "rectangle.on.rectangle"
        case .nvhBeta: return "bolt.fill"
        case .unlockSkin: return "paintpalette"
        }
    }

    /// nil với gói runtime (không đọc vault).
    public var vaultResource: String? {
        switch self {
        case .runtime: return nil
        case .hudFull: return "LQHud"
        case .nvhBeta: return "NVHLQ"
        case .unlockSkin: return "LQUnlock"
        }
    }

    /// Cần payload đóng sẵn trong app?
    public var usesBundledPayload: Bool { vaultResource != nil }
}

public enum LQError: Error, CustomStringConvertible {
    case resourcesNotFound
    case thanosNotFound(String)
    case noHeroSkinFiles(String)
    case notResD(String)
    case notIFix(String)
    case patchFailed(String)

    public var description: String {
        switch self {
        case .resourcesNotFound:
            return "Không thấy Documents/Resources — mở Liên Quân 1 lần rồi thử lại"
        case .thanosNotFound(let v):
            return "Không thấy thư mục Thanos trong Resources/\(v)"
        case .noHeroSkinFiles(let v):
            return "Không thấy HeroSkin_*.bytes trong Resources/\(v)/Thanos"
        case .notResD(let f):
            return "\(f) không phải container ResD (game chưa tải resource?)"
        case .notIFix(let f):
            return "\(f) giải mã ra không phải patch IFix — không sửa được"
        case .patchFailed(let why):
            return "Patch lỗi: \(why)"
        }
    }
}

/// Ghi/gỡ hotfix payload của Liên Quân:
///   `Documents/Resources/<ver>/Thanos/HeroSkin_2.bytes`
///
/// Trước khi ghi luôn backup bản gốc (nếu có) vào sandbox của app; UN INJECT
/// khôi phục đúng bản đó, không đụng file lạ.
public final class LienQuanDeployer {

    public static let targetFileName = "HeroSkin_2.bytes"

    /// Assembly chứa các type mà `LqGenerator` hook (`CameraSystem`,
    /// `CRoleInfoManager`, `CPlayerProfile`). Patch tự sinh PHẢI ghi vào file
    /// cùng assembly này — mỗi file HeroSkin thuộc một assembly khác nhau:
    ///   HeroSkin_1 → Project_d, HeroSkin_2 → Project.Plugins_d,
    ///   HeroSkin_3 → ResCore.Runtime, HeroSkin_4 → AovUISys.
    /// Ghi sai file = game load patch, không tìm thấy bridge → treo.
    public static let generatorAssembly = "Project_d"
    /// File mặc định cho patch tự sinh (thuộc Project_d ở LQ 1.64.1).
    public static let generatedFileName = "HeroSkin_1.bytes"
    private static let backupFolder = "NVH-LQ-Backup"
    private static let versionKey = "nvh.lq.version."
    private static let shaKey = "nvh.lq.sha."
    private static let filesKey = "nvh.lq.files."

    public var onLog: ((String) -> Void)?

    private let access: ContainerAccess
    private let game: GameTarget
    private let fm = FileManager.default

    public init(access: ContainerAccess, game: GameTarget) {
        self.access = access
        self.game = game
    }

    // MARK: - dò thư mục đích

    public struct Target {
        public let version: String
        public let relativePath: String        // Resources/<ver>/Thanos
        public var filePath: String { "\(relativePath)/\(LienQuanDeployer.targetFileName)" }
    }

    /// Tìm version đang có file hotfix (HeroSkin_*); nếu chưa có thì dùng version mới nhất.
    public func resolveTarget() throws -> Target {
        let versions = ((try? access.list("Resources", in: game)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted(by: >)
        guard let newest = versions.first else { throw LQError.resourcesNotFound }

        for v in versions {
            let rel = "Resources/\(v)/Thanos"
            let entries = (try? access.list(rel, in: game)) ?? []
            if Self.patchableFiles(in: entries).isEmpty == false
                || entries.contains(Self.targetFileName) {
                return Target(version: v, relativePath: rel)
            }
        }

        // Chưa thấy payload nào → tạo Thanos trong version mới nhất (game sẽ tạo khi cần).
        let rel = "Resources/\(newest)/Thanos"
        try access.write(Data(), toRelative: "\(rel)/.nvh_probe", in: game)
        try access.remove(relativePath: "\(rel)/.nvh_probe", in: game)
        return Target(version: newest, relativePath: rel)
    }

    /// Version đã ghi lần trước (hiển thị UI).
    public func installedVersion() -> String? {
        if let saved = UserDefaults.standard.string(forKey: Self.versionKey + game.bundleID) {
            return saved
        }
        return (try? resolveTarget())?.version
    }

    // MARK: - trạng thái

    /// Gói nhiều file: "LQ2\0" + u32 số file + [u8 lenTên][tên][u32 size][data]…
    public static func parseBundle(_ data: Data) -> [(name: String, data: Data)]? {
        let b = [UInt8](data)
        guard b.count >= 9, b[0] == 0x4C, b[1] == 0x51, b[2] == 0x32, b[3] == 0 else { return nil }
        func u32(_ p: Int) -> Int {
            Int(b[p]) | Int(b[p + 1]) << 8 | Int(b[p + 2]) << 16 | Int(b[p + 3]) << 24
        }
        var o = 4
        let n = u32(o)
        o += 4
        guard n > 0, n <= 8 else { return nil }
        var out: [(String, Data)] = []
        for _ in 0..<n {
            guard o < b.count else { return nil }
            let nl = Int(b[o])
            o += 1
            guard nl > 0, nl <= 64, o + nl + 4 <= b.count else { return nil }
            guard let name = String(bytes: b[o..<(o + nl)], encoding: .utf8) else { return nil }
            o += nl
            let sz = u32(o)
            o += 4
            guard sz > 0, o + sz <= b.count else { return nil }
            out.append((name, Data(b[o..<(o + sz)])))
            o += sz
        }
        return out
    }

    /// Tên các file đã ghi (bản cũ chỉ có HeroSkin_2).
    private var installedNames: [String] {
        UserDefaults.standard.stringArray(forKey: Self.filesKey + game.bundleID) ?? [Self.targetFileName]
    }

    // MARK: - patch runtime (đọc file gốc trong game → sửa IL → ghi lại)

    /// Kết quả một file được patch runtime.
    public struct RuntimeResult {
        public let file: String
        public let container: String       // "resd-aes" | "plain"
        public let report: LqPatchReport
    }

    /// Tên file hotfix có thể patch (HeroSkin_1..N.bytes) trong thư mục Thanos.
    public static func patchableFiles(in list: [String]) -> [String] {
        list.filter { name in
            name.hasSuffix(".bytes") && name.hasPrefix("HeroSkin_")
                && !name.hasPrefix(".")
        }.sorted()
    }

    /// Có hook nào trong danh sách tên cần thiết không.
    static func hasHook(_ pf: Lqmb.Patch, _ suffix: String) -> Bool {
        pf.interpret.contains { pf.qualifiedName($0.method).hasSuffix(suffix) }
    }

    /// Đọc assembly mà một container HeroSkin khai trong `bridge`.
    /// Trả chuỗi ngắn gọn (`Project_d`, `Project.Plugins_d`, …) hoặc nil.
    public static func assemblyOf(_ container: ResD.Container) -> String? {
        guard let pf = try? Lqmb.parse(container.plain) else { return nil }
        // bridge = "IFix.ILFixInterfaceBridge, Project_d, Version=..."
        let parts = pf.bridge.components(separatedBy: ", ")
        return parts.count > 1 ? parts[1] : nil
    }

    /// Tìm file HeroSkin thuộc assembly `Project_d` (chứa CameraSystem…).
    /// Trả (tên file, container) hoặc nil nếu không file nào khớp.
    func findGeneratorTarget(in target: Target) -> (name: String, container: ResD.Container)? {
        let entries = (try? access.list(target.relativePath, in: game)) ?? []
        for name in Self.patchableFiles(in: entries) {
            let rel = "\(target.relativePath)/\(name)"
            guard let cur = (try? access.read(relativePath: rel, in: game)) ?? nil,
                  let c = try? ResD.decrypt([UInt8](cur),
                                            resName: ResD.resName(forFile: name)),
                  let asm = Self.assemblyOf(c) else { continue }
            if asm.hasPrefix(Self.generatorAssembly) {
                return (name, c)
            }
        }
        return nil
    }

    /// Ghi patch **tự sinh** vào file HeroSkin cùng assembly với type được hook.
    ///
    /// Khác `installRuntime`: hàm này không đọc IL gốc để sửa, mà tự dựng patch
    /// tối giản chỉ chứa đúng hook cần dùng (xem `LqGenerator`). Dùng khi file
    /// trong máy là bản vanilla của game (không có hook nào để sửa).
    ///
    /// QUAN TRỌNG: mỗi file HeroSkin thuộc một assembly khác nhau. Patch khai
    /// bridge `Project_d` nên phải nằm trong file cũng thuộc `Project_d`
    /// (HeroSkin_1), nếu ghi sang HeroSkin_2 (Project.Plugins_d) game sẽ treo.
    @discardableResult
    public func installGenerated(config: LqConfig) -> InstallOutcome {
        guard let pf = LqGenerator.makePatch(config) else {
            return .bad("Chưa chọn tuỳ chọn nào để tạo patch")
        }
        let check = LqGenerator.verify(pf)
        guard check.ok else {
            log("lq: patch tự sinh KHÔNG hợp lệ — \(check.detail)")
            return .bad("Patch tự sinh lỗi: \(check.detail)")
        }
        log("lq: tự sinh patch — \(check.detail) [\(LqGenerator.summary(pf))]")

        do {
            let target = try resolveTarget()

            // Chọn file cùng assembly; nếu không file nào khớp thì dùng file mặc định.
            let chosen: String
            if let hit = findGeneratorTarget(in: target) {
                chosen = hit.name
                log("lq: chọn \(chosen) (assembly \(Self.generatorAssembly))")
            } else {
                chosen = Self.generatedFileName
                log("lq: không thấy file thuộc \(Self.generatorAssembly) — dùng \(chosen)")
            }

            let rel = "\(target.relativePath)/\(chosen)"
            let resName = ResD.resName(forFile: chosen)

            // Backup bản đang có (nếu chưa backup lần nào).
            if let cur = (try? access.read(relativePath: rel, in: game)) ?? nil {
                try rememberOriginal(cur, version: target.version, name: chosen)
            }

            guard let blob = try? Lqmb.serialize(pf) else {
                return .bad("Serialize patch thất bại")
            }
            let out = ResD.encrypt(blob, resName: resName, tag: 103)
            try access.write(Data(out), toRelative: rel, in: game)

            guard let back = (try? access.read(relativePath: rel, in: game)) ?? nil,
                  back == Data(out) else {
                return .bad("Ghi xong nhưng đọc lại không khớp — thử lại")
            }

            let d = UserDefaults.standard
            d.set(target.version, forKey: Self.versionKey + game.bundleID)
            d.set([chosen], forKey: Self.filesKey + game.bundleID)
            d.set(SHA256.hex(out), forKey: Self.shaKey + game.bundleID + "." + chosen)

            var rep = LqPatchReport()
            rep.zoomSites = LqPatcher.blocks(hookedTo: "CameraSystem::GetZoomRate", in: pf).count
            rep.privacySites = LqPatcher.blocks(hookedTo: "CRoleInfoManager::IsPrivaceOn", in: pf).count
            rep.hostSites = LqPatcher.blocks(hookedTo: "CPlayerProfile::get_IsHostProfile", in: pf).count

            log("lq: ghi patch tự sinh → \(rel) (\(out.count) B, \(rep.summary))")
            return .good("Đã tạo patch \(rep.summary) — mở game để áp dụng")
        } catch {
            let msg = (error as? LQError)?.description ?? error.localizedDescription
            log("lq: tạo patch lỗi — \(msg)")
            return .bad(msg)
        }
    }

    /// Patch thông minh: thử sửa file có sẵn trước; nếu file không có hook nào
    /// dùng được (bản vanilla) thì tự sinh patch từ zero.
    @discardableResult
    public func installSmart(config: LqConfig) -> InstallOutcome {
        // Kiểm tra nhanh xem file trong máy có hook cần thiết không.
        if let target = try? resolveTarget(),
           let entries = try? access.list(target.relativePath, in: game) {
            let names = Self.patchableFiles(in: entries)
            for name in names {
                let rel = "\(target.relativePath)/\(name)"
                guard let cur = (try? access.read(relativePath: rel, in: game)) ?? nil,
                      let c = try? ResD.decrypt([UInt8](cur),
                                                resName: ResD.resName(forFile: name)),
                      let pf = try? Lqmb.parse(c.plain) else { continue }
                let want: [String] = (config.zoom ?? 0) > 0
                    ? ["CameraSystem::GetZoomRate"] : []
                let needPrivacy = config.privacyOff == true
                let needHost = config.fakeHost != nil
                let have = want.allSatisfy { Self.hasHook(pf, $0) }
                    && (!needPrivacy || Self.hasHook(pf, "CRoleInfoManager::IsPrivaceOn"))
                    && (!needHost || Self.hasHook(pf, "CPlayerProfile::get_IsHostProfile"))
                if have {
                    log("lq: \(name) có đủ hook → sửa tại chỗ")
                    return installRuntime(config: config)
                }
            }
        }
        log("lq: file trong máy là bản gốc (không có hook) → tự sinh patch")
        return installGenerated(config: config)
    }

    /// Patch tại chỗ các file `HeroSkin_*.bytes` **đang có trong máy game**:
    /// giải mã ResD → parse IFix → sửa theo `config` → serialize (byte-exact) →
    /// mã hoá lại → ghi đè. Bản gốc được backup trước khi ghi.
    ///
    /// Nếu lần trước đã patch, hàm sẽ khôi phục backup trước để tránh patch chồng.
    @discardableResult
    public func installRuntime(config: LqConfig) -> InstallOutcome {
        do {
            let target = try resolveTarget()
            let entries = (try? access.list(target.relativePath, in: game)) ?? []
            let names = Self.patchableFiles(in: entries)
            guard !names.isEmpty else { throw LQError.noHeroSkinFiles(target.version) }

            var results: [RuntimeResult] = []
            var skipped: [String] = []

            for name in names {
                let rel = "\(target.relativePath)/\(name)"
                // 1. Ưu tiên bản gốc đã backup; nếu chưa có thì đọc file hiện tại.
                var raw: [UInt8]
                if let url = backupURL(version: target.version, name: name),
                   fm.fileExists(atPath: url.path),
                   let original = fm.contents(atPath: url.path) {
                    raw = [UInt8](original)
                } else {
                    guard let cur = (try? access.read(relativePath: rel, in: game)) ?? nil else {
                        skipped.append(name); continue
                    }
                    raw = [UInt8](cur)
                    try rememberOriginal(cur, version: target.version, name: name)
                }

                // 2. ResD → IFix
                let resName = ResD.resName(forFile: name)
                let container: ResD.Container
                do {
                    container = try ResD.decrypt(raw, resName: resName)
                } catch {
                    log("lq: \(name) — \(error)")
                    skipped.append(name); continue
                }
                guard Lqmb.isLqmb(container.plain) else {
                    log("lq: \(name) — body không phải IFix LQMB (head "
                        + container.plain.prefix(4).map { String(format: "%02x", $0) }.joined() + ")")
                    skipped.append(name); continue
                }

                // 3. parse → patch → serialize → verify
                var pf: Lqmb.Patch
                do {
                    pf = try Lqmb.parse(container.plain)
                } catch {
                    log("lq: \(name) parse lỗi — \(error)")
                    skipped.append(name); continue
                }
                guard let before = try? Lqmb.serialize(pf) else {
                    log("lq: \(name) không serialize được → bỏ")
                    skipped.append(name); continue
                }
                guard before == container.plain else {
                    log("lq: \(name) round-trip không byte-exact → không đụng để an toàn")
                    skipped.append(name); continue
                }

                let rep = LqPatcher.apply(&pf, config: config)
                for n in rep.notes { log("lq: \(name) — \(n)") }
                if rep.totalSites == 0 {
                    // Không có gì để sửa: nếu đã có backup thì trả file về bản gốc
                    // (người dùng vừa tắt hết tuỳ chọn), tránh để patch cũ nằm lại.
                    if let url = backupURL(version: target.version, name: name),
                       fm.fileExists(atPath: url.path),
                       let original = fm.contents(atPath: url.path),
                       original != Data(raw) {
                        try access.write(original, toRelative: rel, in: game)
                        log("lq: \(name) — không còn tuỳ chọn nào, đã khôi phục bản gốc")
                    } else {
                        log("lq: \(name) — không có site nào khớp, bỏ qua")
                    }
                    skipped.append(name); continue
                }

                let newPlain: [UInt8]
                do {
                    newPlain = try Lqmb.serialize(pf)
                } catch {
                    log("lq: \(name) serialize lỗi — \(error)")
                    skipped.append(name); continue
                }
                // verify: parse lại phải ra cùng số block/hook
                guard let re = try? Lqmb.parse(newPlain),
                      re.blocks.count == pf.blocks.count,
                      re.interpret.count == pf.interpret.count else {
                    log("lq: \(name) verify sau patch thất bại → bỏ")
                    skipped.append(name); continue
                }

                // 4. đóng gói lại đúng kiểu container gốc
                let outBytes = ResD.encrypt(newPlain, resName: resName,
                                            tag: container.tag,
                                            encrypt: container.encrypted)
                try access.write(Data(outBytes), toRelative: rel, in: game)

                guard let back = (try? access.read(relativePath: rel, in: game)) ?? nil,
                      back == Data(outBytes) else {
                    return .bad("Ghi xong nhưng đọc lại không khớp (\(name)) — thử lại")
                }
                results.append(RuntimeResult(
                    file: name,
                    container: container.encrypted ? "resd-aes" : "plain",
                    report: rep))
                log("lq: \(name) ← \(rep.summary) (\(container.encrypted ? "AES" : "plain"))")
            }

            guard !results.isEmpty else {
                return .bad("Không patch được file nào — game chưa tải resource HeroSkin?")
            }

            let d = UserDefaults.standard
            d.set(target.version, forKey: Self.versionKey + game.bundleID)
            d.set(results.map { $0.file }, forKey: Self.filesKey + game.bundleID)
            for r in results {
                let rel = "\(target.relativePath)/\(r.file)"
                if let data = (try? access.read(relativePath: rel, in: game)) ?? nil {
                    d.set(SHA256.hex([UInt8](data)),
                          forKey: Self.shaKey + game.bundleID + "." + r.file)
                }
            }
            try? access.remove("lqcfg.txt", in: game)

            let total = results.reduce(0) { $0 + $1.report.totalSites }
            var msg = "Đã patch \(game.name): \(results.map { $0.file }.joined(separator: ", ")) "
                + "• \(total) điểm"
            if !skipped.isEmpty { msg += " • bỏ \(skipped.count) file" }
            log("lq: runtime xong → " + results.map {
                "\($0.file)[\($0.report.summary)]"
            }.joined(separator: " "))
            return .good(msg)
        } catch {
            let msg = (error as? LQError)?.description ?? error.localizedDescription
            log("lq: runtime lỗi — \(msg)")
            return .bad(msg)
        }
    }

    /// Đọc thông tin patch hiện có trong game (để UI hiện file + trạng thái).
    public func inspectRuntime() -> [RuntimeResult] {
        guard let target = try? resolveTarget(),
              let entries = try? access.list(target.relativePath, in: game) else { return [] }
        var out: [RuntimeResult] = []
        for name in Self.patchableFiles(in: entries) {
            let rel = "\(target.relativePath)/\(name)"
            guard let cur = (try? access.read(relativePath: rel, in: game)) ?? nil else { continue }
            let resName = ResD.resName(forFile: name)
            guard let c = try? ResD.decrypt([UInt8](cur), resName: resName),
                  let pf = try? Lqmb.parse(c.plain) else { continue }
            var rep = LqPatchReport()
            // đếm site thật: mỗi block hook vào GetZoomRate / IsPrivaceOn / IsHostProfile
            rep.zoomSites = LqPatcher.blocks(hookedTo: "CameraSystem::GetZoomRate", in: pf).count
            rep.privacySites = LqPatcher.blocks(hookedTo: "CRoleInfoManager::IsPrivaceOn", in: pf).count
            rep.hostSites = LqPatcher.blocks(hookedTo: "CPlayerProfile::get_IsHostProfile", in: pf).count
            out.append(RuntimeResult(
                file: name,
                container: c.encrypted ? "resd-aes" : "plain",
                report: rep))
        }
        return out
    }

    /// Đã inject = mọi file trong game khớp SHA-256 của payload mình đã ghi.
    public func isInstalled() -> Bool {
        guard let target = try? resolveTarget() else { return false }
        let d = UserDefaults.standard
        for name in installedNames {
            guard let data = (try? access.read(relativePath: "\(target.relativePath)/\(name)", in: game)) ?? nil,
                  let expected = d.string(forKey: Self.shaKey + game.bundleID + "." + name),
                  SHA256.hex([UInt8](data)) == expected
            else { return false }
        }
        return true
    }

    // MARK: - cài / gỡ

    @discardableResult
    public func install(_ payload: Data, pack: LQPack, config: String? = nil) -> InstallOutcome {
        let files = Self.parseBundle(payload) ?? [(Self.targetFileName, payload)]
        return write(files, pack: pack, config: config)
    }

    private func write(_ files: [(name: String, data: Data)],
                       pack: LQPack, config: String?) -> InstallOutcome {
        do {
            let target = try resolveTarget()
            for f in files {
                let rel = "\(target.relativePath)/\(f.name)"
                if let cur = (try? access.read(relativePath: rel, in: game)) ?? nil {
                    try rememberOriginal(cur, version: target.version, name: f.name)
                } else {
                    clearOriginal(version: target.version, name: f.name)
                }
            }
            for f in files {
                try access.write(f.data, toRelative: "\(target.relativePath)/\(f.name)", in: game)
            }

            if let config {
                try access.write(Data(config.utf8), to: "lqcfg.txt", in: game)
            } else {
                try? access.remove("lqcfg.txt", in: game)
            }

            for f in files {
                let rel = "\(target.relativePath)/\(f.name)"
                guard let back = (try? access.read(relativePath: rel, in: game)) ?? nil else {
                    return .bad("Ghi xong nhưng không đọc lại được — thử lại")
                }
                guard back == f.data else {
                    return .bad("Đọc lại không khớp (\(f.name): \(back.count) B ≠ \(f.data.count) B)")
                }
            }

            let d = UserDefaults.standard
            d.set(target.version, forKey: Self.versionKey + game.bundleID)
            d.set(files.map { $0.name }, forKey: Self.filesKey + game.bundleID)
            for f in files {
                d.set(SHA256.hex([UInt8](f.data)), forKey: Self.shaKey + game.bundleID + "." + f.name)
            }
            log("lq: đã ghi \(target.relativePath) • \(pack.title) • \(files.map { $0.name }.joined(separator: " + "))")
            return .good("Đã inject \(game.name) (\(pack.title)) — mở game để áp dụng")
        } catch {
            let msg = (error as? LQError)?.description ?? error.localizedDescription
            log("lq: lỗi \(msg)")
            return .bad(msg)
        }
    }

    @discardableResult
    public func uninstall() -> InstallOutcome {
        do {
            let target = try targetForRemoval()
            let d = UserDefaults.standard
            let names = installedNames
            var restored = 0
            var removed = 0
            var kept = 0

            for name in names {
                let rel = "\(target.relativePath)/\(name)"
                let current = (try? access.read(relativePath: rel, in: game)) ?? nil
                if let url = backupURL(version: target.version, name: name),
                   fm.fileExists(atPath: url.path),
                   let original = fm.contents(atPath: url.path) {
                    try access.write(original, toRelative: rel, in: game)
                    try? fm.removeItem(at: url)
                    restored += 1
                } else if let current,
                          let expected = d.string(forKey: Self.shaKey + game.bundleID + "." + name),
                          SHA256.hex([UInt8](current)) == expected {
                    try access.remove(relativePath: rel, in: game)
                    removed += 1
                } else if current != nil {
                    kept += 1
                }
            }

            d.removeObject(forKey: Self.filesKey + game.bundleID)
            d.removeObject(forKey: Self.versionKey + game.bundleID)
            for name in names {
                d.removeObject(forKey: Self.shaKey + game.bundleID + "." + name)
            }
            try? access.remove("lqcfg.txt", in: game)
            log("lq: gỡ xong — khôi phục \(restored), xoá \(removed), giữ \(kept)")
            if kept > 0, restored == 0, removed == 0 {
                return .bad("File trong game không phải của NVH — không xoá để tránh hỏng game")
            }
            return .good(restored > 0
                         ? "Đã gỡ LQ — khôi phục file gốc. Mở lại game nhé."
                         : "Đã gỡ LQ. Mở lại game nhé.")
        } catch {
            let msg = (error as? LQError)?.description ?? error.localizedDescription
            log("lq: lỗi gỡ — \(msg)")
            return .bad(msg)
        }
    }

    // MARK: - config cho patch NVH Beta (lqcfg.txt)

    @discardableResult
    public func writeConfig(_ text: String) -> Bool {
        do {
            try access.write(Data(text.utf8), to: "lqcfg.txt", in: game)
            return true
        } catch {
            log("lq: không ghi được lqcfg.txt — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - backup

    private func targetForRemoval() throws -> Target {
        let saved = UserDefaults.standard.string(forKey: Self.versionKey + game.bundleID)
        if let saved, !saved.isEmpty {
            let rel = "Resources/\(saved)/Thanos"
            if (try? access.list(rel, in: game)) != nil {
                return Target(version: saved, relativePath: rel)
            }
        }
        return try resolveTarget()
    }

    private var backupRoot: URL? {
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent(Self.backupFolder, isDirectory: true)
            .appendingPathComponent(game.bundleID, isDirectory: true)
    }

    private func backupURL(version: String, name: String) -> URL? {
        backupRoot?.appendingPathComponent("\(version)-\(name)")
    }

    /// Chỉ lưu bản gốc lần đầu — không để bản mod ghi đè backup thật.
    private func rememberOriginal(_ data: Data, version: String, name: String) throws {
        guard let url = backupURL(version: version, name: name) else { return }
        guard !fm.fileExists(atPath: url.path) else { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        log("lq: đã backup bản gốc \(version)/\(name) (\(data.count) B)")
    }

    private func clearOriginal(version: String, name: String) {
        if let url = backupURL(version: version, name: name) { try? fm.removeItem(at: url) }
    }

    private func log(_ text: String) { onLog?(text) }
}

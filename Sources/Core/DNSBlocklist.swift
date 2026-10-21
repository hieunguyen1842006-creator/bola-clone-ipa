import Foundation

/// DNSBlocklistRule — định dạng config "antiban" (vd: antiban-nvh.json):
///   [{ enabled, name, note, url (regex khớp host), script (onRequest/onResponse stub) }]
///
/// Tầng DNS chỉ dùng được phần `url`: NEDNSSettingsManager/DoH không có chỗ chạy JS
/// (script rewrite HTTP là việc của proxy engine). Blocklist được biên dịch thành
/// denylist domain gốc để dán vào resolver có lọc (NextDNS / AdGuard dashboard),
/// sau đó trỏ DoH về resolver đó — tức là chặn đúng những domain rule muốn chặn.
public struct DNSBlocklistRule: Identifiable, Codable, Equatable {
    public var id: String { name }
    public var enabled: Bool
    public var name: String
    public var note: String
    public var url: String
    public var script: String

    enum CodingKeys: String, CodingKey {
        case enabled, name, note, url, script
    }

    public init(enabled: Bool, name: String, note: String, url: String, script: String) {
        self.enabled = enabled
        self.name = name
        self.note = note
        self.url = url
        self.script = script
    }

    /// Decode khoan dung: thiếu field nào thì lấy mặc định.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        name = (try? c.decode(String.self, forKey: .name)) ?? "rule"
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        script = (try? c.decode(String.self, forKey: .script)) ?? ""
    }
}

public enum DNSBlocklist {

    /// Config mặc định — nguyên văn antiban-nvh.json (NVH Antiban v2).
    public static let defaultJSON = #"""
    [{"enabled":true,"name":"NVH Antiban","note":"NVH antiban v2 - block FF client/CDN/rtc + telemetry (pure block, no pass-through)","url":"client\.[a-z0-9]+\.freefiremobile\.com|ff\.[a-z0-9]+\.grtc\.garenanow\.com|dl\.[a-z0-9]+\.freefiremobile\.com|(cdn|dl)(\.[a-z0-9]+)?\.garenanow\.com|gin\.freefiremobile\.com|common\.freefiremobile\.com|app-measurement\.com|firebase-settings\.crashlytics\.com|appsflyer\.com|adjust\.com","script":"function onRequest(a,b){return null;}function onResponse(a,b,c){return c;}"}]
    """#

    /// Parse JSON (mảng rule hoặc 1 rule đơn). File thật chứa escape không hợp lệ
    /// chuẩn JSON (`\.`) — chuẩn hoá thành `\\.` trước khi decode.
    public static func load(_ data: Data) -> [DNSBlocklistRule] {
        guard var text = String(data: data, encoding: .utf8) else { return [] }
        if let re = try? NSRegularExpression(pattern: #"\\(?!["\\/bfnrtu])"#) {
            text = re.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: #"\\\\"#
            )
        }
        guard let d = text.data(using: .utf8) else { return [] }
        if let rules = try? JSONDecoder().decode([DNSBlocklistRule].self, from: d) { return rules }
        if let one = try? JSONDecoder().decode(DNSBlocklistRule.self, from: d) { return [one] }
        return []
    }

    /// Biên dịch regex domain → danh sách domain gốc (2 nhãn cuối).
    /// `client\.[a-z0-9]+\.freefiremobile\.com` → `freefiremobile.com`.
    /// Chặn apex là phủ đủ mọi pattern con mà rule liệt kê (blocklist chặn cả subdomain).
    public static func domains(fromPattern pattern: String) -> [String] {
        var s = pattern.replacingOccurrences(of: "\\.", with: ".")
        s = s.replacingOccurrences(of: #"\[[^\]]*\]\+?"#, with: "*", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\([^\)]*\)\?"#, with: "", options: .regularExpression)

        var out: Set<String> = []
        for variant in expandGroups(s) {
            for alt in variant.components(separatedBy: "|") {
                let labels = alt.components(separatedBy: ".").map { l -> String in
                    var l = l
                    if l.contains("[") || l.contains("*") { return "*" }
                    return l.trimmingCharacters(in: CharacterSet(charactersIn: "()+?*^$"))
                }.filter { !$0.isEmpty }
                guard !labels.isEmpty else { continue }

                // Đuôi sau dấu * cuối cùng = phần chắc chắn bị khớp
                let candidate: String
                if let idx = labels.lastIndex(of: "*") {
                    candidate = labels[(labels.index(after: idx))...].joined(separator: ".")
                } else {
                    candidate = labels.joined(separator: ".")
                }
                let parts = candidate.components(separatedBy: ".")
                guard parts.count >= 2 else { continue }
                out.insert(parts.suffix(2).joined(separator: "."))
            }
        }
        return out.sorted()
    }

    /// Nở group literal `(a|b)` thành các biến thể (giới hạn tổ hợp).
    private static func expandGroups(_ input: String) -> [String] {
        var current = [input]
        for _ in 0..<8 {
            guard let base = current.first,
                  let r = base.range(of: #"\(([^\(\)]*)\)"#, options: .regularExpression)
            else { break }
            var next: [String] = []
            for b in current {
                let inner = String(b[r]).dropFirst().dropLast()
                for o in inner.components(separatedBy: "|") where !o.isEmpty {
                    next.append(b.replacingCharacters(in: r, with: o))
                    if next.count >= 32 { break }
                }
            }
            if next.isEmpty { break }
            current = next
        }
        return current
    }

    /// Denylist dạng AdGuard / Pi-hole wildcard: `||domain^`
    public static func denylistADG(_ domains: [String]) -> String {
        domains.map { "||\($0)^" }.joined(separator: "\n")
    }

    /// Denylist dạng hosts: `0.0.0.0 domain`
    public static func denylistHosts(_ domains: [String]) -> String {
        domains.map { "0.0.0.0 \($0)" }.joined(separator: "\n")
    }

    /// Gộp denylist từ rules (chỉ rule enabled), sẵn sàng dán vào dashboard.
    public static func denylistADG(_ rules: [DNSBlocklistRule]) -> String {
        denylistADG(rules.filter { $0.enabled }.flatMap { domains(fromPattern: $0.url) }.sorted())
    }
}

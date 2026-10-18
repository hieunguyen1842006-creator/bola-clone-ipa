import Foundation
import Combine

// MARK: - LicenseGate (class + State{started, activated, starting, needKey, authorized})

@MainActor
public final class LicenseGate: ObservableObject {

    public enum State: String, Equatable {
        case started
        case needKey
        case starting
        case activated
        case authorized
    }

    // Field đúng tên trong binary: _state _statusText _remainingText _busy _errorText
    @Published public private(set) var state: State = .started
    @Published public private(set) var statusText: String = "Đang kết nối hệ thống key…"
    @Published public private(set) var remainingText: String = ""
    @Published public private(set) var busy: Bool = false
    @Published public private(set) var errorText: String = ""

    /// Còn hiện được nhờ cache offline trong bao nhiêu ngày (Info.plist: BolaOfflineMaxDays = 3)
    public let offlineMaxDays: Int
    public let packageToken: String
    public let productId: String

    public private(set) var lease: Lease?
    public var leaseExpiryUnix: Int64 { lease?.expiryUnix ?? 0 }

    /// Log ra console UI (bản gốc: "tserver terminal: %@", "tserver key info: %@")
    public var onLog: ((String) -> Void)?

    private let client: LicenseClient
    private let store: LeaseStore
    private var timer: Timer?

    public init(client: LicenseClient,
                store: LeaseStore = LeaseStore(),
                offlineMaxDays: Int,
                packageToken: String,
                productId: String) {
        self.client = client
        self.store = store
        self.offlineMaxDays = offlineMaxDays
        self.packageToken = packageToken
        self.productId = productId
    }

    // MARK: vòng đời

    public func start() {
        state = .started
        if let cached = store.load() {
            lease = cached
            state = .activated
            refreshTexts()
            onLog?("tserver terminal: dùng bản cache offline (còn \(offlineDaysLeft()) ngày)")
            verifyInBackground()
        } else {
            state = .needKey
            statusText = "Nhập key để kích hoạt menu"
        }
        startTimer()
    }

    public func submit(key raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = "License key is empty"
            state = .needKey
            return
        }
        busy = true
        errorText = ""
        state = .starting
        statusText = "Đang kiểm tra key và thiết bị…"
        onLog?("tserver key info: \(KeyMask.mask(key))")

        Task {
            do {
                let lease = try await client.activate(key: key,
                                                      packageToken: packageToken,
                                                      productId: productId)
                await MainActor.run {
                    self.lease = lease
                    self.busy = false
                    self.errorText = ""
                    self.store.save(lease)
                    self.state = .activated
                    self.afterAuthorized()
                    self.onLog?("Dang kich hoat key... OK — active")
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.state = .needKey
                    self.errorText = LicenseErrorText.text(for: error)
                    self.onLog?("tserver terminal: \(self.errorText)")
                }
            }
        }
    }

    public func deactivate() {
        lease = nil
        store.clear()
        state = .needKey
        statusText = "Nhập key để kích hoạt menu"
        remainingText = ""
        errorText = ""
    }

    public var isAuthorized: Bool {
        guard let lease else { return false }
        if lease.isLifetime { return true }
        guard lease.expiryUnix > Int64(Date().timeIntervalSince1970) else { return false }
        // cửa sổ offline: quá offlineMaxDays kể từ lần server xác nhận cuối thì phải check lại
        guard let last = store.lastServerOK() else { return true }
        return Date().timeIntervalSince(last) <= Double(offlineMaxDays) * 86_400
    }

    /// Gọi sau khi server xác nhận key (activate/check) — bản gốc: `afterAuthorized`.
    public func afterAuthorized() {
        store.markServerOK()
        refreshTexts()
        onAuthorized?()
    }

    /// Callback để AppModel tự heal token/patch ngay khi key được xác nhận.
    public var onAuthorized: (() -> Void)?

    // MARK: text

    private func refreshTexts() {
        guard let lease = self.lease else { return }
        if lease.isLifetime {
            statusText = "Key hợp lệ (vĩnh viễn)"
            remainingText = "∞"
            return
        }
        let left = lease.expiryUnix - Int64(Date().timeIntervalSince1970)
        if left <= 0 {
            statusText = "Key hết hạn hoặc bị thu hồi — nhập key mới."
            remainingText = "0h"
            state = .needKey
            return
        }
        statusText = "Key hợp lệ"
        let h = left / 3600
        let d = h / 24
        remainingText = d > 0 ? "\(d) ngày \(h % 24)h" : "\(h)h \((left % 3600) / 60)m"
    }

    private func offlineDaysLeft() -> Int {
        // cửa sổ offline: từ lần server xác nhận gần nhất (bola_last_server_ok)
        guard let last = store.lastServerOK() else { return 0 }
        let elapsedDays = Int(Date().timeIntervalSince(last) / 86_400)
        return max(0, offlineMaxDays - elapsedDays)
    }

    private func verifyInBackground() {
        guard let lease = self.lease else { return }
        Task {
            if let fresh = try? await client.check(key: lease.key, packageToken: packageToken) {
                await MainActor.run {
                    self.lease = fresh
                    self.store.save(fresh)
                    self.afterAuthorized()
                }
            } else {
                await MainActor.run {
                    self.onLog?("Cần kết nối mạng để xác thực (\(self.offlineDaysLeft()) ngày cache còn lại)")
                }
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTexts() }
        }
    }
}

// MARK: - error → text (đúng các câu trong bảng chuỗi của bản gốc)

public enum LicenseErrorText {
    public static func text(for error: Error) -> String {
        if let api = error as? LicenseClient.APIError {
            switch api {
            case .serverStatus(let code):
                switch code {
                case "TRIAL_ALREADY_USED": return "Key này đã được liên kết với thiết bị khác."
                case "BAD_CLIENT_SIGNATURE", "BAD_RESPONSE_SIGNATURE": return "Phản hồi server sai chữ ký."
                case "TRANSPORT_SESSION_REQUIRED", "TRANSPORT_HANDSHAKE_FAILED":
                    return "Phiên bảo mật thất bại — thử lại sau."
                case "KEY_NOT_FOUND", "INVALID_API_KEY": return "Key khong hop le"
                case "KEY_BANNED": return "Key nay da bi ban / thu hoi. Lien he nguoi ban de duoc ho tro."
                case "KEY_EXPIRED": return "Key da het han"
                default: return "Server key dang tam tat. Vui long thu lai sau."
                }
            case .transport(let m): return "Cần kết nối mạng để xác thực (\(m))"
            case .decoding: return "Phản hồi server không hợp lệ."
            }
        }
        return "Có lỗi — thử lại nhé"
    }
}

// MARK: - LeaseStore (cache + mốc server OK: bola_last_server_ok / lastOkKey)

public final class LeaseStore {
    private let defaults: UserDefaults
    private let leaseKey = "bola_lease_payload"
    private let okKey = "bola_last_server_ok"
    private let lastOkKeyKey = "lastOkKey"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ lease: Lease) {
        if let data = try? JSONEncoder().encode(lease) {
            defaults.set(data, forKey: leaseKey)
        }
        defaults.set(Date(), forKey: okKey)
        defaults.set(lease.key, forKey: lastOkKeyKey)
    }

    public func load() -> Lease? {
        guard let data = defaults.data(forKey: leaseKey) else { return nil }
        return try? JSONDecoder().decode(Lease.self, from: data)
    }

    public func lastServerOK() -> Date? {
        defaults.object(forKey: okKey) as? Date
    }

    /// Ghi mốc "server vừa xác nhận key" — dùng cho cửa sổ offline.
    public func markServerOK() {
        defaults.set(Date(), forKey: okKey)
    }

    public func lastOkKey() -> String? {
        defaults.string(forKey: lastOkKeyKey)
    }

    /// "Xoá Bộ Nhớ Đệm" trong SettingsView
    public func clear() {
        defaults.removeObject(forKey: leaseKey)
    }

    public func clearAllCaches() {
        defaults.removeObject(forKey: leaseKey)
        defaults.removeObject(forKey: okKey)
        defaults.removeObject(forKey: lastOkKeyKey)
    }
}

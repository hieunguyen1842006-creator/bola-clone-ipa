import Foundation

import Foundation

// MARK: - Logger (khung log "tserver terminal: …" của bản gốc)

public final class Logger {
    public static let shared = Logger()

    public struct Line: Identifiable, Equatable {
        public let id = UUID()
        public let time: Date
        public let text: String

        public var stamp: String {
            Logger.formatter.string(from: time)
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public private(set) var lines: [Line] = []
    public var onChange: (([Line]) -> Void)?
    private let maxLines = 400

    public func log(_ text: String) {
        let line = Line(time: Date(), text: text)
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        onChange?(lines)
    }

    public func clear() {
        lines.removeAll()
        onChange?(lines)
    }

    public var plainText: String {
        lines.map { "\($0.stamp)  \($0.text)" }.joined(separator: "\n")
    }
}

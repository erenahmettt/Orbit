import Foundation
import SwiftUI

/// Uygulamanın widget için yazdığı özet. Bu dosya hem uygulamaya hem widget uzantısına derlenir.
struct WidgetSnapshot: Codable {
    struct WTask: Codable, Identifiable {
        var id: String
        var title: String
        var due: Date?
        var hasTime: Bool
        var done: Bool
        var completedAt: Date?
        var priority: Int // 0 low … 3 urgent
        var projectColor: String?
    }
    struct WEvent: Codable, Identifiable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var color: String
    }
    struct WFocus: Codable {
        var phase: String // focus | shortBreak | longBreak
        var end: Date?
        var pausedRemaining: Double?
        var duration: Double
        var taskTitle: String
    }

    var generated: Date
    var userName: String
    var accent: String
    var tasks: [WTask]
    var events: [WEvent]
    var focus: WFocus?
    var focusMinutesToday: Int

    static let empty = WidgetSnapshot(generated: .distantPast, userName: "", accent: "#6558F5", tasks: [], events: [], focus: nil, focusMinutesToday: 0)

    /// Gerçek ev dizini (widget sandbox içindeyken bile)
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }
    static var fileURL: URL {
        URL(fileURLWithPath: realHome).appending(path: "Library/Application Support/Orbit/widget.json")
    }

    static func load() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }

    func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        guard let data = try? enc.encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: Widget'ın render anında hesapladıkları

    func todayTasks(at now: Date = Date()) -> [WTask] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        return tasks.filter { t in
            if t.done { return t.completedAt.map { cal.isDate($0, inSameDayAs: now) } ?? false }
            guard let d = t.due else { return false }
            return d < start.addingTimeInterval(86400)
        }
        .sorted { a, b in
            if a.done != b.done { return !a.done }
            let ao = a.due.map { $0 < start } ?? false, bo = b.due.map { $0 < start } ?? false
            if ao != bo { return ao }
            if a.priority != b.priority { return a.priority > b.priority }
            return (a.due ?? .distantFuture) < (b.due ?? .distantFuture)
        }
    }

    func upcomingEvents(at now: Date = Date(), limit: Int = 4) -> [WEvent] {
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(86400 * 2)
        return events.filter { $0.end > now && $0.start < end }.sorted { $0.start < $1.start }.prefix(limit).map { $0 }
    }
}

extension Color {
    init(wHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

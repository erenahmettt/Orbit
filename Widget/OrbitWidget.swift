import WidgetKit
import SwiftUI

// Orbit masaüstü widget'ları. build.sh bu dosyayı Shared/WidgetSnapshot.swift ile birlikte
// OrbitWidget.appex olarak derleyip Orbit.app/Contents/PlugIns içine koyar.

struct OrbitEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct OrbitProvider: TimelineProvider {
    func placeholder(in context: Context) -> OrbitEntry { OrbitEntry(date: Date(), snap: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (OrbitEntry) -> Void) {
        let s = WidgetSnapshot.load()
        completion(OrbitEntry(date: Date(), snap: context.isPreview && s.generated == .distantPast ? .preview : s))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<OrbitEntry>) -> Void) {
        let s = WidgetSnapshot.load()
        var refresh = Date().addingTimeInterval(15 * 60)
        if let end = s.focus?.end, end > Date() { refresh = min(refresh, end.addingTimeInterval(2)) }
        // Gece yarısında "bugün" değişsin
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400 + 5)
        refresh = min(refresh, midnight)
        completion(Timeline(entries: [OrbitEntry(date: Date(), snap: s)], policy: .after(refresh)))
    }
}

let coral = Color(wHex: "#FF786B")
let success = Color(wHex: "#35B88A")
let warning = Color(wHex: "#F2B84B")
let info = Color(wHex: "#55A7E8")

func priorityColor(_ p: Int) -> Color {
    switch p { case 3: coral; case 2: warning; case 0: info; default: .secondary }
}

let timeFmt: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.setLocalizedDateFormatFromTemplate("HHmm")
    return f
}()
let dayFmt: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
    return f
}()

// MARK: - Bugün widget'ı

struct TodayWidgetView: View {
    let entry: OrbitEntry
    @Environment(\.widgetFamily) var family

    var tasks: [WidgetSnapshot.WTask] { entry.snap.todayTasks(at: entry.date) }
    var open: [WidgetSnapshot.WTask] { tasks.filter { !$0.done } }
    var ratio: Double { tasks.isEmpty ? 0 : Double(tasks.count - open.count) / Double(tasks.count) }
    var accent: Color { Color(wHex: entry.snap.accent) }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemLarge, .systemExtraLarge: large
            default: medium
            }
        }
        .widgetURL(URL(string: "orbit://today"))
    }

    var ring: some View {
        ZStack {
            Circle().stroke(success.opacity(0.18), lineWidth: 6)
            Circle().trim(from: 0, to: max(0.001, ratio))
                .stroke(success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(ratio * 100))%").font(.system(size: 12, weight: .bold, design: .rounded))
        }
    }

    var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max.fill").foregroundStyle(warning)
            Text("Bugün").font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            Text(dayFmt.string(from: entry.date)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ring.frame(width: 46, height: 46)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(open.count)").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(accent)
                    Text("açık görev").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let t = open.first {
                Text("Sıradaki").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(t.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            } else {
                Text(tasks.isEmpty ? "Bugün plan yok" : "Hepsi bitti 🎉").font(.system(size: 13, weight: .semibold))
            }
        }
    }

    var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ring.frame(width: 54, height: 54)
                Spacer(minLength: 0)
                Text("\(tasks.count - open.count)/\(tasks.count)").font(.system(size: 15, weight: .bold, design: .rounded))
                Text("tamamlandı").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                header
                taskList(limit: 4)
                Spacer(minLength: 0)
            }
        }
    }

    var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ring.frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snap.userName.isEmpty ? "Bugün" : "Merhaba, \(entry.snap.userName)").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(open.count) açık görev · \(dayFmt.string(from: entry.date))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            taskList(limit: 6)
            let events = entry.snap.upcomingEvents(at: entry.date, limit: 3)
            if !events.isEmpty {
                Divider()
                Text("PROGRAM").font(.system(size: 9.5, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
                ForEach(events) { e in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(wHex: e.color)).frame(width: 3, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text("\(Calendar.current.isDateInToday(e.start) ? "Bugün" : "Yarın") \(timeFmt.string(from: e.start))–\(timeFmt.string(from: e.end))")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder func taskList(limit: Int) -> some View {
        if tasks.isEmpty {
            Text("Bugün için görev yok.\nOrbit'te ⇧⌘N ile ekle.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        ForEach(tasks.prefix(limit)) { t in
            let overdue = !t.done && (t.due.map { $0 < Calendar.current.startOfDay(for: entry.date) } ?? false)
            HStack(spacing: 7) {
                Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(t.done ? success : priorityColor(t.priority))
                Text(t.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .strikethrough(t.done).foregroundStyle(t.done ? .secondary : .primary)
                Spacer(minLength: 4)
                if overdue {
                    Text("gecikti").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(coral)
                } else if t.hasTime, let d = t.due {
                    Text(timeFmt.string(from: d)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                if let c = t.projectColor { Circle().fill(Color(wHex: c)).frame(width: 6, height: 6) }
            }
        }
        if tasks.count > limit {
            Text("+\(tasks.count - limit) görev daha").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitToday", provider: OrbitProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(wHex: entry.snap.accent).opacity(0.16), Color(wHex: entry.snap.accent).opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Orbit · Bugün")
        .description("Bugünün görevleri, ilerleme ve yaklaşan program.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Odak (Pomodoro) widget'ı

struct FocusWidgetView: View {
    let entry: OrbitEntry
    var f: WidgetSnapshot.WFocus? { entry.snap.focus }

    var phaseTitle: String {
        switch f?.phase { case "shortBreak": "Kısa mola"; case "longBreak": "Uzun mola"; case "focus": "Odak"; default: "Pomodoro" }
    }
    var color: Color {
        switch f?.phase { case "shortBreak": success; case "longBreak": info; default: coral }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "timer").foregroundStyle(color)
                Text(phaseTitle).font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
            }
            Spacer(minLength: 0)
            if let f, let end = f.end, end > entry.date {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(color)
                ProgressView(timerInterval: end.addingTimeInterval(-f.duration)...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(color)
            } else if let f, let p = f.pausedRemaining {
                Text(String(format: "%02d:%02d", Int(p) / 60, Int(p) % 60))
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                Text("Duraklatıldı").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("\(entry.snap.focusMinutesToday) dk").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(color)
                Text("bugün odaklanıldı").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let t = f?.taskTitle, !t.isEmpty {
                Text(t).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(.secondary)
            } else if f == nil {
                Text("Başlatmak için dokun").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: "orbit://focus"))
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitFocus", provider: OrbitProvider()) { entry in
            FocusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [coral.opacity(0.18), coral.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Orbit · Odak")
        .description("Pomodoro geri sayımı ve bugünkü odak süresi.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct OrbitWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FocusWidget()
    }
}

extension WidgetSnapshot {
    /// Widget galerisinde gösterilen örnek görünüm
    static var preview: WidgetSnapshot {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        return WidgetSnapshot(generated: now, userName: "", accent: "#6558F5", tasks: [
            .init(id: "1", title: "Günlük planlama", due: today.addingTimeInterval(9 * 3600), hasTime: true, done: true, completedAt: now, priority: 2, projectColor: "#6558F5"),
            .init(id: "2", title: "Sunumu hazırla", due: today.addingTimeInterval(14 * 3600), hasTime: true, done: false, completedAt: nil, priority: 3, projectColor: "#F2B84B"),
            .init(id: "3", title: "Spor", due: today, hasTime: false, done: false, completedAt: nil, priority: 1, projectColor: "#35B88A"),
        ], events: [], focus: nil, focusMinutesToday: 50)
    }
}

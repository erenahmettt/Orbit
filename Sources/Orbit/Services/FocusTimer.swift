import Foundation
import SwiftData
import SwiftUI
import AppKit
import UserNotifications

enum FocusPhase: String, Codable {
    case idle, focus, shortBreak, longBreak
    var title: String {
        switch self {
        case .idle: "Hazır"
        case .focus: "Odak"
        case .shortBreak: "Kısa mola"
        case .longBreak: "Uzun mola"
        }
    }
    var icon: String {
        switch self {
        case .idle: "timer"
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }
    var color: Color {
        switch self {
        case .idle, .focus: Palette.secondary
        case .shortBreak: Palette.success
        case .longBreak: Palette.info
        }
    }
}

/// Pomodoro zamanlayıcısı. Durum UserDefaults'ta tutulur; uygulama yeniden açılınca kaldığı yerden devam eder.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    @Published private(set) var phase: FocusPhase = .idle
    /// Sıradaki faz (idle iken "Başlat" neyi başlatacak)
    @Published private(set) var upcoming: FocusPhase = .focus
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var phaseStart: Date?
    @Published private(set) var phaseDuration: TimeInterval = 25 * 60
    @Published var taskID: UUID?
    @Published var taskTitle: String = ""
    @Published private(set) var round = 0
    @Published private(set) var now = Date()

    var container: ModelContainer?
    private var ticker: Timer?
    private let d = UserDefaults.standard

    var focusMinutes: Int { max(1, d.object(forKey: "pomo.focus") as? Int ?? 25) }
    var shortMinutes: Int { max(1, d.object(forKey: "pomo.short") as? Int ?? 5) }
    var longMinutes: Int { max(1, d.object(forKey: "pomo.long") as? Int ?? 15) }
    var roundsBeforeLong: Int { max(2, d.object(forKey: "pomo.rounds") as? Int ?? 4) }
    var autoStart: Bool { d.object(forKey: "pomo.autostart") as? Bool ?? true }

    var isRunning: Bool { phase != .idle && pausedRemaining == nil }
    var isPaused: Bool { phase != .idle && pausedRemaining != nil }
    var isActive: Bool { phase != .idle }

    var remaining: TimeInterval {
        if let p = pausedRemaining { return p }
        guard let e = endDate else { return minutes(for: upcoming) * 60 }
        return max(0, e.timeIntervalSince(now))
    }
    var progress: Double {
        guard phase != .idle, phaseDuration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / phaseDuration))
    }
    var remainingText: String {
        let r = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", r / 60, r % 60)
    }

    init() {
        restore()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func minutes(for p: FocusPhase) -> Double {
        switch p {
        case .focus, .idle: Double(focusMinutes)
        case .shortBreak: Double(shortMinutes)
        case .longBreak: Double(longMinutes)
        }
    }

    // MARK: Kontroller

    func start(task: TaskItem? = nil) {
        if let task { setTask(task) }
        begin(.focus)
    }

    func setTask(_ task: TaskItem?) {
        taskID = task?.id
        taskTitle = task?.title ?? ""
        persist()
    }

    func startUpcoming() { begin(upcoming) }

    func pause() {
        guard isRunning, let e = endDate else { return }
        pausedRemaining = max(0, e.timeIntervalSinceNow)
        endDate = nil
        cancelNotification()
        persist()
    }

    func resume() {
        guard let p = pausedRemaining else { return }
        endDate = Date().addingTimeInterval(p)
        pausedRemaining = nil
        scheduleNotification()
        persist()
    }

    /// Fazı atlar (odak atlanırsa kayıt tutulmaz)
    func skip() {
        guard phase != .idle else { upcoming = upcoming == .focus ? .shortBreak : .focus; persist(); return }
        advance(recordFocus: false)
    }

    func stop() {
        cancelNotification()
        phase = .idle
        upcoming = .focus
        endDate = nil
        pausedRemaining = nil
        phaseStart = nil
        round = 0
        persist()
        WidgetBridge.refreshSoon()
    }

    // MARK: İç işleyiş

    private func begin(_ p: FocusPhase) {
        let target: FocusPhase = p == .idle ? .focus : p
        phase = target
        phaseDuration = minutes(for: target) * 60
        phaseStart = Date()
        endDate = Date().addingTimeInterval(phaseDuration)
        pausedRemaining = nil
        now = Date()
        scheduleNotification()
        persist()
        WidgetBridge.refreshSoon()
    }

    private func tick() {
        now = Date()
        guard isRunning, let e = endDate, e <= now else { return }
        advance(recordFocus: true)
    }

    private func advance(recordFocus: Bool) {
        let finished = phase
        cancelNotification()
        var next: FocusPhase = .focus
        if finished == .focus {
            if recordFocus { record() }
            round += 1
            next = round % roundsBeforeLong == 0 ? .longBreak : .shortBreak
            if recordFocus { NSSound(named: "Glass")?.play() }
        } else {
            next = .focus
            if recordFocus { NSSound(named: "Hero")?.play() }
        }
        if autoStart && recordFocus {
            begin(next)
        } else {
            phase = .idle
            upcoming = next
            endDate = nil
            pausedRemaining = nil
            phaseStart = nil
            persist()
            WidgetBridge.refreshSoon()
        }
    }

    private func record() {
        guard let ctx = container?.mainContext else { return }
        let mins = Int((phaseDuration / 60).rounded())
        ctx.insert(FocusSession(start: phaseStart ?? Date().addingTimeInterval(-phaseDuration), minutes: mins, taskID: taskID, taskTitle: taskTitle))
        var projectID: UUID?
        if let id = taskID, let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
            t.focusMinutes += mins
            projectID = t.projectID
        }
        Store.log(ctx, "\(mins) dk odaklanıldı" + (taskTitle.isEmpty ? "" : ": **\(taskTitle)**"), icon: "timer", color: "#FF786B", projectID: projectID)
        try? ctx.save()
        AppState.shared.show(Toast(text: "Pomodoro tamamlandı · \(mins) dk 🎉", icon: "timer", color: Palette.success))
    }

    private func scheduleNotification() {
        guard Notifier.available, let e = endDate else { return }
        let c = UNMutableNotificationContent()
        switch phase {
        case .focus:
            c.title = "🍅 Odak süresi bitti"
            c.body = (taskTitle.isEmpty ? "" : "\(taskTitle) · ") + "Mola zamanı!"
        default:
            c.title = "⏰ Mola bitti"
            c.body = "Yeni bir odak turuna hazır mısın?"
        }
        c.sound = .default
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(1, e.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "focus-end", content: c, trigger: t))
    }

    private func cancelNotification() {
        guard Notifier.available else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus-end"])
    }

    // MARK: Kalıcılık

    private func persist() {
        d.set(phase.rawValue, forKey: "pomo.state.phase")
        d.set(upcoming.rawValue, forKey: "pomo.state.upcoming")
        d.set(endDate?.timeIntervalSince1970, forKey: "pomo.state.end")
        d.set(pausedRemaining, forKey: "pomo.state.paused")
        d.set(phaseStart?.timeIntervalSince1970, forKey: "pomo.state.start")
        d.set(phaseDuration, forKey: "pomo.state.duration")
        d.set(taskID?.uuidString, forKey: "pomo.state.task")
        d.set(taskTitle, forKey: "pomo.state.taskTitle")
        d.set(round, forKey: "pomo.state.round")
    }

    private func restore() {
        phase = FocusPhase(rawValue: d.string(forKey: "pomo.state.phase") ?? "") ?? .idle
        upcoming = FocusPhase(rawValue: d.string(forKey: "pomo.state.upcoming") ?? "") ?? .focus
        endDate = (d.object(forKey: "pomo.state.end") as? Double).map { Date(timeIntervalSince1970: $0) }
        pausedRemaining = d.object(forKey: "pomo.state.paused") as? Double
        phaseStart = (d.object(forKey: "pomo.state.start") as? Double).map { Date(timeIntervalSince1970: $0) }
        phaseDuration = d.object(forKey: "pomo.state.duration") as? Double ?? 25 * 60
        taskID = d.string(forKey: "pomo.state.task").flatMap(UUID.init)
        taskTitle = d.string(forKey: "pomo.state.taskTitle") ?? ""
        round = d.integer(forKey: "pomo.state.round")
        // Uygulama kapalıyken süre dolduysa sessizce bitir
        if phase != .idle, pausedRemaining == nil, endDate == nil { phase = .idle }
    }
}

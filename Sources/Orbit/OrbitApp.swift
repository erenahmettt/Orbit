import SwiftUI
import SwiftData
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // swift run ile çalıştırıldığında da normal bir uygulama gibi davransın
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let d = UserDefaults.standard
        if d.bool(forKey: "onboarded") { Notifier.requestAuthorization() }
        if d.object(forKey: "dailyPlanningEnabled") == nil { d.set(true, forKey: "dailyPlanningEnabled") }
        Notifier.scheduleDailyPlanning(enabled: d.bool(forKey: "dailyPlanningEnabled"), hour: d.object(forKey: "dailyPlanningHour") as? Int ?? 9, minute: 0)
        Task { @MainActor in Snapshot.runIfRequested() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var app = AppState.shared
    @StateObject private var focus = FocusTimer.shared
    @AppStorage("theme") private var theme: AppTheme = .system
    @AppStorage("accent") private var accent: String = "#6558F5"
    @AppStorage("showMenuBar") private var showMenuBar = true

    let container: ModelContainer = {
        // ORBIT_DATA_DIR: geliştirme/test için ayrı bir veri klasörü
        let dir = ProcessInfo.processInfo.environment["ORBIT_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL.applicationSupportDirectory.appending(path: "Orbit", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: Schema(allModels), url: dir.appending(path: "Orbit.store"))
        do {
            return try ModelContainer(for: Schema(allModels), configurations: config)
        } catch {
            fatalError("Veritabanı açılamadı: \(error)")
        }
    }()

    var body: some Scene {
        Window("Orbit", id: "main") {
            RootView()
                .environmentObject(app)
                .environmentObject(focus)
                .environmentObject(AppleCalendar.shared)
                .tint(Color(hex: accent))
                .accentColor(Color(hex: accent))
                .preferredColorScheme(theme.scheme)
                .frame(minWidth: 1080, minHeight: 680)
                .onAppear {
                    Seed.cleanup(container.mainContext)
                    focus.container = container
                    WidgetBridge.shared.attach(container)
                }
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 880)
        .commands { OrbitCommands(app: app, container: container) }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environmentObject(app)
                .environmentObject(focus)
                .modelContainer(container)
                .tint(Color(hex: accent))
                .preferredColorScheme(theme.scheme)
        } label: {
            MenuBarLabel(focus: focus)
        }
        .menuBarExtraStyle(.window)
    }
}

struct OrbitCommands: Commands {
    let app: AppState
    let container: ModelContainer

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Yeni Not") { app.newNote(context: container.mainContext) }
                .keyboardShortcut("n", modifiers: .command)
            Button("Yeni Görev") { app.newTask() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Ara / Komut Paleti") { app.showPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Home") { app.go(.home) }.keyboardShortcut("1", modifiers: .command)
            Button("Today") { app.go(.today) }.keyboardShortcut("2", modifiers: .command)
            Button("Calendar") { app.go(.calendar) }.keyboardShortcut("3", modifiers: .command)
            Button("Tasks") { app.go(.tasks) }.keyboardShortcut("4", modifiers: .command)
            Button("Notes") { app.go(.notes) }.keyboardShortcut("5", modifiers: .command)
            Button("Journal") { app.go(.journal) }.keyboardShortcut("6", modifiers: .command)
            Button("Projects") { app.go(.projects) }.keyboardShortcut("7", modifiers: .command)
            Button("Focus") { app.go(.focus) }.keyboardShortcut("8", modifiers: .command)
            Divider()
            Button("Pomodoro başlat / duraklat") {
                let f = FocusTimer.shared
                if f.isRunning { f.pause() } else if f.isPaused { f.resume() } else { f.startUpcoming() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .appSettings) {
            Button("Ayarlar…") { app.go(.settings) }.keyboardShortcut(",", modifiers: .command)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @AppStorage("onboarded") var onboarded = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            ZStack {
                AppBackground()
                DetailRouter()
            }
        }
        .overlay {
            if app.showPalette {
                CommandPalette()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .overlay(alignment: .topTrailing) { FocusPill() }
        .onOpenURL { url in
            // orbit://today, orbit://focus, orbit://calendar, orbit://new-task
            switch url.host {
            case "today": app.go(.today)
            case "focus": app.go(.focus)
            case "calendar": app.go(.calendar)
            case "new-task": app.newTask(due: Date().startOfDay)
            default: app.go(.home)
            }
        }
        .overlay {
            if !onboarded {
                OnboardingView().transition(.opacity)
            }
        }
        .sheet(item: $app.editingTask) { task in
            TaskEditor(task: task).environmentObject(app)
        }
        .sheet(item: $app.newTaskDraft) { draft in
            NewTaskSheet(draft: draft).environmentObject(app)
        }
        .animation(.snappy(duration: 0.18), value: app.showPalette)
    }
}

struct DetailRouter: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Group {
            switch app.selection ?? .home {
            case .home: HomeView()
            case .inbox: TaskCollectionView(scope: .inbox)
            case .today: TaskCollectionView(scope: .today)
            case .upcoming: TaskCollectionView(scope: .upcoming)
            case .tasks: TaskCollectionView(scope: .all)
            case .calendar: CalendarScreen()
            case .projects: ProjectsView()
            case .project(let id): ProjectDetailView(projectID: id)
            case .notes: NotesView()
            case .journal: JournalView()
            case .focus: FocusView()
            case .archive: ArchiveView(mode: .archive)
            case .trash: ArchiveView(mode: .trash)
            case .settings: SettingsView()
            }
        }
        .id(app.selection)
        .transition(.opacity)
    }
}

struct ToastView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        if let t = app.toast {
            HStack(spacing: 10) {
                Image(systemName: t.icon)
                    .foregroundStyle(t.color)
                    .symbolEffect(.bounce, value: t.id)
                Text(t.text).font(.callout.weight(.medium)).lineLimit(1)
                if let undo = t.undo {
                    Button("Geri al") {
                        undo()
                        withAnimation { app.toast = nil }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.callout.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(t.color.opacity(0.35)))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(t.id)
        }
    }
}

/// Menü çubuğu ikonu: pomodoro çalışırken kalan süreyi gösterir
struct MenuBarLabel: View {
    @ObservedObject var focus: FocusTimer
    var body: some View {
        if focus.isActive {
            HStack(spacing: 3) {
                Image(systemName: focus.isPaused ? "pause.circle" : "timer")
                Text(focus.remainingText).monospacedDigit()
            }
        } else {
            Image(systemName: "circle.circle")
        }
    }
}

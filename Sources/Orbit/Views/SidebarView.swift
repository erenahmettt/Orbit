import SwiftUI
import SwiftData

struct SidebarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query(sort: \Project.sortIndex) var projects: [Project]
    @Query var tasks: [TaskItem]
    @Query var notes: [Note]
    @State private var showNewProject = false

    private var live: [TaskItem] { tasks.filter { $0.isLive && !$0.isDone } }

    func count(_ item: SidebarItem) -> Int? {
        let n: Int
        switch item {
        case .inbox: n = live.filter { $0.status == .inbox }.count + notes.filter { $0.isLive && $0.projectID == nil && $0.folderID == nil }.count
        case .today: n = live.filter { $0.isToday || $0.isOverdue }.count
        case .upcoming: n = live.filter { ($0.dueDate ?? .distantPast) > Date().startOfDay.adding(days: 1) }.count
        default: return nil
        }
        return n == 0 ? nil : n
    }

    var body: some View {
        List(selection: $app.selection) {
            Button { app.showPalette = true } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Ara veya komut…").foregroundStyle(.secondary)
                    Spacer()
                    Text("⌘K").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .padding(.bottom, 4)

            Section {
                ForEach([SidebarItem.home, .inbox, .today, .upcoming, .calendar, .tasks, .projects, .notes, .journal, .focus], id: \.self) { item in
                    row(item)
                }
            }

            Section {
                ForEach(projects.filter(\.isLive)) { p in
                    HStack(spacing: 9) {
                        ProjectBadge(project: p, size: 20)
                        Text(p.name).lineLimit(1)
                        Spacer()
                        let open = tasks.filter { $0.projectID == p.id && $0.isLive && !$0.isDone }.count
                        if open > 0 { Text("\(open)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .tag(SidebarItem.project(p.id))
                    .dropDestination(for: String.self) { ids, _ in
                        moveTasks(ids, to: p)
                    }
                    .contextMenu {
                        Button("Arşivle") { p.archived = true }
                        Button("Çöpe taşı", role: .destructive) { p.deletedAt = Date() }
                    }
                }
                .onMove { from, to in
                    var arr = projects.filter(\.isLive)
                    arr.move(fromOffsets: from, toOffset: to)
                    for (i, p) in arr.enumerated() { p.sortIndex = i }
                }
            } header: {
                HStack {
                    Text("Projeler")
                    Spacer()
                    Button { showNewProject = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .help("Yeni proje")
                }
            }

            Section {
                row(.archive)
                row(.trash)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                OrbitLogo().frame(width: 26, height: 26)
                Text("Orbit").font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Button { app.newTask() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor.gradient))
                }
                .buttonStyle(.plain)
                .help("Yeni görev (⇧⌘N)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 34)
            .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom) {
            Button { app.go(.settings) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "gearshape.fill").foregroundStyle(.secondary)
                    Text("Settings")
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(app.selection == .settings ? Color.accentColor.opacity(0.15) : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .sheet(isPresented: $showNewProject) { ProjectEditor(project: nil) }
    }

    @ViewBuilder func row(_ item: SidebarItem) -> some View {
        HStack(spacing: 9) {
            Image(systemName: item.icon)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(item.color.gradient))
            Text(item.title)
            Spacer()
            if let c = count(item) {
                Text("\(c)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item == .today && live.contains(where: \.isOverdue) ? Palette.warning : .secondary)
            }
        }
        .tag(item)
        .modifier(DateDropModifier(item: item, onDrop: { ids, day in moveTasks(ids, toDay: day) }))
    }

    func moveTasks(_ ids: [String], to project: Project) -> Bool {
        let found = tasks.filter { ids.contains($0.id.uuidString) }
        for t in found {
            t.projectID = project.id
            if t.status == .inbox { t.status = .todo }
            Store.log(context, "**\(t.title)** → \(project.name)", icon: "arrow.right.circle.fill", color: project.colorHex, projectID: project.id)
        }
        return !found.isEmpty
    }

    func moveTasks(_ ids: [String], toDay day: Date) -> Bool {
        let found = tasks.filter { ids.contains($0.id.uuidString) }
        found.forEach { Store.reschedule($0, to: day, context: context) }
        return !found.isEmpty
    }
}

/// Today / Upcoming öğelerine görev bırakınca tarihini değiştirir.
struct DateDropModifier: ViewModifier {
    let item: SidebarItem
    let onDrop: ([String], Date) -> Bool
    func body(content: Content) -> some View {
        switch item {
        case .today: content.dropDestination(for: String.self) { ids, _ in onDrop(ids, Date().startOfDay) }
        case .upcoming: content.dropDestination(for: String.self) { ids, _ in onDrop(ids, Date().startOfDay.adding(days: 1)) }
        default: content
        }
    }
}

struct OrbitLogo: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Palette.primary, Palette.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(6)
            Ellipse()
                .stroke(LinearGradient(colors: [Palette.secondary, Palette.warning], startPoint: .leading, endPoint: .trailing), lineWidth: 2)
                .frame(height: 10)
                .rotationEffect(.degrees(-28))
            Circle().fill(Palette.secondary).frame(width: 5, height: 5).offset(x: 10, y: -5)
        }
    }
}

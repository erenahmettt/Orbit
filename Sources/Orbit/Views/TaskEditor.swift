import SwiftUI
import SwiftData

struct NewTaskSheet: View {
    let draft: NewTaskDraft
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var app: AppState
    @State private var task: TaskItem?

    var body: some View {
        Group {
            if let task { TaskEditor(task: task, isNew: true, onCancel: { context.delete(task); dismiss() }) }
            else { Color.clear.frame(width: 640, height: 560) }
        }
        .onAppear {
            guard task == nil else { return }
            let t = TaskItem(title: "", status: draft.status ?? (draft.projectID == nil && draft.due == nil ? .inbox : .todo), due: draft.due, hasTime: draft.hasTime, projectID: draft.projectID)
            t.isDraft = true
            context.insert(t)
            task = t
        }
    }
}

struct TaskEditor: View {
    @Bindable var task: TaskItem
    var isNew = false
    var onCancel: (() -> Void)? = nil
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var app: AppState
    @Query(sort: \Project.sortIndex) var projects: [Project]
    @Query(sort: \Note.updatedAt, order: .reverse) var notes: [Note]
    @State private var newSubtask = ""
    @State private var newTag = ""
    @State private var original: (Date?, String)?
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CompletionCheckbox(done: task.isDone, color: task.priority.color, size: 22) {
                    Store.toggleComplete(task, context: context, app: app)
                }
                TextField("Görev başlığı", text: $task.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .focused($titleFocused)
                Spacer()
                if !isNew {
                    Menu {
                        Button("Arşivle") { task.archived = true; dismiss() }
                        Button("Çöpe taşı", role: .destructive) { Store.trash(task, context: context, app: app); dismiss() }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Durum ve öncelik
                    HStack(spacing: 16) {
                        field("Durum") {
                            Picker("", selection: Binding(get: { task.status }, set: { Store.setStatus(task, $0, context: context, app: app) })) {
                                ForEach(TaskStatus.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                            }.labelsHidden()
                        }
                        field("Öncelik") {
                            Picker("", selection: $task.priority) {
                                ForEach(TaskPriority.allCases.reversed()) { p in
                                    Label(p.title, systemImage: p.flag).tag(p)
                                }
                            }.labelsHidden()
                        }
                        field("Proje") {
                            Picker("", selection: $task.projectID) {
                                Text("Yok").tag(UUID?.none)
                                ForEach(projects.filter(\.isLive)) { p in Text(p.name).tag(Optional(p.id)) }
                            }.labelsHidden()
                        }
                    }

                    // Tarihler
                    HStack(alignment: .top, spacing: 16) {
                        field("Başlangıç") { optionalDate($task.startDate, time: false) }
                        field("Son teslim") {
                            VStack(alignment: .leading, spacing: 6) {
                                optionalDate($task.dueDate, time: task.hasTime)
                                if task.dueDate != nil {
                                    Toggle("Saat belirle", isOn: $task.hasTime).toggleStyle(.checkbox).font(.caption)
                                    HStack(spacing: 4) {
                                        ForEach([("Bugün", 0), ("Yarın", 1), ("+7", 7)], id: \.0) { label, d in
                                            Button(label) { Store.snooze(task, days: d, context: context) }.controlSize(.small)
                                        }
                                    }
                                }
                            }
                        }
                        field("Tahmini süre") {
                            Picker("", selection: $task.estimateMinutes) {
                                Text("—").tag(0)
                                ForEach([5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 480], id: \.self) { Text(Fmt.duration($0)).tag($0) }
                            }.labelsHidden()
                        }
                    }

                    // Hatırlatıcı ve tekrar
                    HStack(alignment: .top, spacing: 16) {
                        field("Hatırlatıcı") {
                            VStack(alignment: .leading, spacing: 6) {
                                if let _ = task.reminder {
                                    HStack {
                                        DatePicker("", selection: Binding(get: { task.reminder ?? Date() }, set: { task.reminder = $0 }), displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                                        Button { task.reminder = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Menu("Ekle") {
                                        Button("30 dk sonra") { task.reminder = Date().adding(minutes: 30) }
                                        Button("1 saat sonra") { task.reminder = Date().adding(minutes: 60) }
                                        if let due = task.dueDate {
                                            Button("Teslimden 1 saat önce") { task.reminder = (task.hasTime ? due : due.at(hour: 9)).adding(minutes: -60) }
                                            Button("Teslim günü 09:00") { task.reminder = due.at(hour: 9) }
                                        }
                                        Button("Yarın 09:00") { task.reminder = Date().startOfDay.adding(days: 1).at(hour: 9) }
                                    }.fixedSize()
                                }
                                if !Notifier.available {
                                    Text("Bildirimler .app paketinde çalışır").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        field("Tekrarlama") { RecurrenceEditor(recurrence: $task.recurrence) }
                    }

                    // Açıklama
                    field("Açıklama") {
                        TextEditor(text: $task.details)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 70)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
                    }

                    // Alt görevler
                    field("Alt görevler \(task.subtasks.isEmpty ? "" : "· \(task.subtaskProgress.0)/\(task.subtaskProgress.1)")") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach($task.subtasks) { $s in
                                HStack(spacing: 8) {
                                    CompletionCheckbox(done: s.done, color: .secondary, size: 15) { s.done.toggle() }
                                    TextField("", text: $s.title).textFieldStyle(.plain)
                                        .strikethrough(s.done).foregroundStyle(s.done ? .secondary : .primary)
                                    Button { task.subtasks.removeAll { $0.id == s.id } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                                }
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 19)
                                TextField("Alt görev ekle", text: $newSubtask).textFieldStyle(.plain)
                                    .onSubmit {
                                        let t = newSubtask.trimmingCharacters(in: .whitespaces)
                                        guard !t.isEmpty else { return }
                                        task.subtasks.append(Subtask(title: t))
                                        newSubtask = ""
                                    }
                            }
                        }
                    }

                    // Etiketler
                    field("Etiketler") {
                        FlowLayout(spacing: 6) {
                            ForEach(task.tags, id: \.self) { tag in
                                HStack(spacing: 3) {
                                    Text("#\(tag)")
                                    Button { task.tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
                                }
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.purple)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Palette.purple.opacity(0.12)))
                            }
                            TextField("etiket ekle", text: $newTag).textFieldStyle(.plain).frame(width: 110)
                                .onSubmit {
                                    let t = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").lowercased()
                                    if !t.isEmpty && !task.tags.contains(t) { task.tags.append(t) }
                                    newTag = ""
                                }
                        }
                    }

                    // İlişkili notlar
                    field("İlişkili notlar") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(notes.filter { task.relatedNoteIDs.contains($0.id) }) { n in
                                HStack {
                                    Button {
                                        app.selectedNoteID = n.id
                                        dismiss()
                                        app.go(.notes)
                                    } label: { Label(n.title.isEmpty ? "Başlıksız" : n.title, systemImage: "doc.text") }
                                    .buttonStyle(.link)
                                    Spacer()
                                    Button { task.relatedNoteIDs.removeAll { $0 == n.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(.tertiary)
                                }
                            }
                            Menu("Not bağla") {
                                ForEach(notes.filter { $0.isLive && !task.relatedNoteIDs.contains($0.id) }.prefix(30)) { n in
                                    Button(n.title.isEmpty ? "Başlıksız" : n.title) { task.relatedNoteIDs.append(n.id) }
                                }
                            }.fixedSize()
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                if !isNew {
                    Text("Oluşturuldu \(Fmt.ago(task.createdAt))").font(.caption).foregroundStyle(.tertiary)
                    if task.focusMinutes > 0 {
                        Label("\(Fmt.duration(task.focusMinutes)) odaklanıldı", systemImage: "timer").font(.caption).foregroundStyle(Palette.secondary)
                    }
                    if !task.isDone {
                        Button {
                            FocusTimer.shared.start(task: task)
                            dismiss()
                            app.go(.focus)
                        } label: { Label("Odaklan", systemImage: "play.fill") }
                    }
                }
                Spacer()
                if isNew {
                    Button("Vazgeç") { onCancel?() }.keyboardShortcut(.cancelAction)
                    Button("Görev oluştur") { commitNew() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button("Bitti") { commitEdit() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(width: 660, height: 640)
        .onAppear {
            original = (task.dueDate, task.title)
            if isNew { titleFocused = true }
        }
        .onExitCommand { isNew ? onCancel?() : commitEdit() }
    }

    func commitNew() {
        task.isDraft = false
        task.createdAt = Date()
        if task.status == .inbox && (task.projectID != nil || task.dueDate != nil) { task.status = .todo }
        if task.dueDate != nil && !task.hasTime { task.dueDate = task.dueDate?.startOfDay }
        let pname = Store.projectName(context, task.projectID).map { "\($0) projesine" } ?? "Inbox'a"
        Store.log(context, "\(pname) yeni görev eklendi: **\(task.title)**", icon: "plus.circle.fill", color: "#55A7E8", projectID: task.projectID)
        Notifier.schedule(task: task)
        app.show(Toast(text: "Görev oluşturuldu", icon: "plus.circle.fill", color: Palette.info))
        dismiss()
    }

    func commitEdit() {
        task.updatedAt = Date()
        if task.dueDate != nil && !task.hasTime { task.dueDate = task.dueDate?.startOfDay }
        if let o = original, o.0 != task.dueDate {
            let label = task.dueDate.map { Fmt.relative($0) } ?? "tarihsiz"
            Store.log(context, "Görev tarihi değiştirildi: **\(task.title)** → \(label)", icon: "calendar.badge.clock", color: "#F2B84B", projectID: task.projectID)
        }
        if let pid = task.projectID, let p = projects.first(where: { $0.id == pid }) { p.updatedAt = Date() }
        Notifier.schedule(task: task)
        dismiss()
    }

    @ViewBuilder func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased(with: Fmt.locale)).font(.system(size: 10.5, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func optionalDate(_ binding: Binding<Date?>, time: Bool) -> some View {
        if binding.wrappedValue != nil {
            HStack(spacing: 4) {
                DatePicker("", selection: Binding(get: { binding.wrappedValue ?? Date() }, set: { binding.wrappedValue = $0 }), displayedComponents: time ? [.date, .hourAndMinute] : [.date])
                    .labelsHidden()
                Button { binding.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        } else {
            Button("Tarih ekle") { binding.wrappedValue = Date().startOfDay }
        }
    }
}

struct RecurrenceEditor: View {
    @Binding var recurrence: Recurrence

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $recurrence.kind) {
                ForEach(RecurrenceKind.allCases) { Text($0.title).tag($0) }
            }.labelsHidden()
            switch recurrence.kind {
            case .weekdays:
                HStack(spacing: 4) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                        let on = recurrence.weekdays.contains(wd)
                        Button {
                            if on { recurrence.weekdays.removeAll { $0 == wd } } else { recurrence.weekdays.append(wd) }
                        } label: {
                            Text(Fmt.weekdaySymbol(wd).prefix(2))
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 24)
                                .foregroundStyle(on ? .white : .primary)
                                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : Color.primary.opacity(0.07)))
                        }.buttonStyle(.plain)
                    }
                }
            case .interval:
                HStack {
                    Text("Her")
                    Stepper(value: $recurrence.interval, in: 1...365) { Text("\(recurrence.interval)").monospacedDigit() }
                    Picker("", selection: $recurrence.unit) {
                        ForEach(IntervalUnit.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().fixedSize()
                }
            default: EmptyView()
            }
            if recurrence.isActive {
                Text("Tamamlandığında bir sonraki görev otomatik oluşur.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Basit akış (wrap) düzeni
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

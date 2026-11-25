import SwiftUI
import SwiftData

enum NoteFilter: Hashable {
    case all, favorites, pinned, inbox, folder(UUID), tag(String), project(UUID)
}

struct NotesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query(sort: \Note.updatedAt, order: .reverse) var notes: [Note]
    @Query(sort: \NoteFolder.sortIndex) var folders: [NoteFolder]
    @Query(sort: \Project.sortIndex) var projects: [Project]
    @State private var filter: NoteFilter = .all
    @State private var search = ""
    @State private var newFolder = ""
    @State private var addingFolder = false

    var live: [Note] { notes.filter(\.isLive) }
    var allTags: [String] { Array(Set(live.flatMap(\.tags))).sorted() }

    var filtered: [Note] {
        var r: [Note]
        switch filter {
        case .all: r = live
        case .favorites: r = live.filter(\.favorite)
        case .pinned: r = live.filter(\.pinned)
        case .inbox: r = live.filter { $0.folderID == nil && $0.projectID == nil }
        case .folder(let id): r = live.filter { $0.folderID == id }
        case .tag(let t): r = live.filter { $0.tags.contains(t) }
        case .project(let id): r = live.filter { $0.projectID == id }
        }
        if !search.isEmpty {
            r = r.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) || $0.tags.contains { $0.localizedCaseInsensitiveContains(search) } }
        }
        return r.sorted { ($0.pinned ? 1 : 0, $0.updatedAt) > ($1.pinned ? 1 : 0, $1.updatedAt) }
    }

    var body: some View {
        HStack(spacing: 0) {
            folderColumn.frame(width: 190)
            Divider()
            listColumn.frame(width: 260)
            Divider()
            Group {
                if let id = app.selectedNoteID, let n = notes.first(where: { $0.id == id }), n.deletedAt == nil {
                    NoteEditorView(note: n).id(n.id)
                } else {
                    EmptyState(icon: "note.text", title: "Bir not seç", subtitle: "veya ⌘N ile yeni not oluştur")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: Klasörler

    var folderColumn: some View {
        List(selection: Binding(get: { filter }, set: { if let v = $0 { filter = v } })) {
            Section {
                filterRow(.all, "Tüm notlar", "doc.text.fill", Palette.primary, live.count)
                filterRow(.favorites, "Favoriler", "star.fill", Palette.warning, live.filter(\.favorite).count)
                filterRow(.pinned, "Sabitlenmiş", "pin.fill", Palette.purple, live.filter(\.pinned).count)
                filterRow(.inbox, "Kategorisiz", "tray.fill", Palette.info, live.filter { $0.folderID == nil && $0.projectID == nil }.count)
            }
            Section {
                ForEach(folders) { f in
                    filterRow(.folder(f.id), f.name, f.icon, Color(hex: f.colorHex), live.filter { $0.folderID == f.id }.count)
                        .dropDestination(for: String.self) { ids, _ in
                            let found = notes.filter { ids.contains("note:" + $0.id.uuidString) }
                            found.forEach { $0.folderID = f.id }
                            return !found.isEmpty
                        }
                        .contextMenu {
                            Button("Klasörü sil", role: .destructive) {
                                notes.filter { $0.folderID == f.id }.forEach { $0.folderID = nil }
                                context.delete(f)
                                filter = .all
                            }
                        }
                }
                if addingFolder {
                    TextField("Klasör adı", text: $newFolder).onSubmit {
                        if !newFolder.isEmpty {
                            context.insert(NoteFolder(name: newFolder, icon: "folder", colorHex: Palette.projectColors[folders.count % Palette.projectColors.count], sortIndex: folders.count))
                        }
                        newFolder = ""; addingFolder = false
                    }
                }
            } header: {
                HStack {
                    Text("Klasörler")
                    Spacer()
                    Button { addingFolder = true } label: { Image(systemName: "plus") }.buttonStyle(.plain)
                }
            }
            Section("Projeler") {
                ForEach(projects.filter(\.isLive)) { p in
                    filterRow(.project(p.id), p.name, p.icon, p.color, live.filter { $0.projectID == p.id }.count)
                }
            }
            if !allTags.isEmpty {
                Section("Etiketler") {
                    ForEach(allTags, id: \.self) { t in
                        HStack {
                            Text("#").foregroundStyle(Palette.purple).fontWeight(.bold)
                            Text(t)
                            Spacer()
                        }.tag(NoteFilter.tag(t))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    func filterRow(_ f: NoteFilter, _ title: String, _ icon: String, _ color: Color, _ count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            Text(title).lineLimit(1)
            Spacer()
            if count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
        }
        .tag(f)
    }

    // MARK: Liste

    var listColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Notlarda ara", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
                Button {
                    var folderID: UUID?, projectID: UUID?
                    if case .folder(let id) = filter { folderID = id }
                    if case .project(let id) = filter { projectID = id }
                    app.newNote(context: context, projectID: projectID, folderID: folderID)
                } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain).help("Yeni not (⌘N)")
            }
            .padding(12)
            .padding(.top, 22)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filtered) { n in
                        NoteListRow(note: n, selected: app.selectedNoteID == n.id, folder: folders.first { $0.id == n.folderID })
                            .onTapGesture { app.selectedNoteID = n.id }
                            .draggable("note:" + n.id.uuidString)
                            .contextMenu {
                                Button(n.pinned ? "Sabitlemeyi kaldır" : "Sabitle") { n.pinned.toggle() }
                                Button(n.favorite ? "Favoriden çıkar" : "Favorilere ekle") { n.favorite.toggle() }
                                Button("Arşivle") { n.archived = true }
                                Button("Çöpe taşı", role: .destructive) { n.deletedAt = Date() }
                            }
                    }
                    if filtered.isEmpty { EmptyState(icon: "doc.text.magnifyingglass", title: "Not yok") }
                }
                .padding(.horizontal, 10).padding(.bottom, 16)
            }
        }
    }
}

struct NoteListRow: View {
    let note: Note
    let selected: Bool
    let folder: NoteFolder?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Palette.purple) }
                Text(note.title.isEmpty ? "Başlıksız" : note.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Spacer()
                if note.favorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.warning) }
            }
            Text(note.preview.isEmpty ? "Boş not" : note.preview).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 6) {
                Text(Fmt.ago(note.updatedAt)).font(.caption2).foregroundStyle(.tertiary)
                if let folder {
                    Label(folder.name, systemImage: folder.icon).font(.caption2).foregroundStyle(Color(hex: folder.colorHex))
                }
                ForEach(note.tags.prefix(2), id: \.self) { Text("#\($0)").font(.caption2).foregroundStyle(Palette.purple) }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(selected ? Color.accentColor.opacity(0.45) : .clear))
        .contentShape(Rectangle())
    }
}

enum EditorMode: String, CaseIterable {
    case edit = "Düzenle", split = "Bölünmüş", preview = "Önizleme"
    var icon: String { switch self { case .edit: "pencil"; case .split: "rectangle.split.2x1"; case .preview: "eye" } }
}

struct NoteEditorView: View {
    @Bindable var note: Note
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query(sort: \Note.updatedAt, order: .reverse) var notes: [Note]
    @Query(sort: \NoteFolder.sortIndex) var folders: [NoteFolder]
    @Query(sort: \Project.sortIndex) var projects: [Project]
    @Query var tasks: [TaskItem]
    @StateObject private var editor = EditorController()
    @AppStorage("editorMode") var modeRaw = EditorMode.edit.rawValue
    @AppStorage("editorFont") var fontRaw = EditorTypography.Family.system.rawValue
    @AppStorage("editorSize") var fontSize = 15.0
    @AppStorage("editorLineHeight") var lineHeight = 1.45
    @AppStorage("editorReadable") var readable = true

    var typo: EditorTypography {
        EditorTypography(family: .init(rawValue: fontRaw) ?? .system, size: fontSize, lineHeight: lineHeight)
    }
    var maxTextWidth: CGFloat { readable ? 760 : .infinity }
    @State private var newTag = ""
    @State private var lastLogged = Date.distantPast

    var mode: EditorMode { EditorMode(rawValue: modeRaw) ?? .edit }

    var backlinks: [Note] {
        guard !note.title.isEmpty else { return [] }
        return notes.filter { $0.isLive && $0.id != note.id && $0.linkedTitles.contains { $0.caseInsensitiveCompare(note.title) == .orderedSame } }
    }
    var outgoing: [Note] {
        let titles = note.linkedTitles.map { $0.lowercased() }
        return notes.filter { $0.isLive && $0.id != note.id && titles.contains($0.title.lowercased()) }
    }
    var relatedTasks: [TaskItem] { tasks.filter { $0.isLive && $0.relatedNoteIDs.contains(note.id) } }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Başlık", text: $note.title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: max(26, typo.size * 2), weight: .bold, design: typo.family == .system ? .rounded : typo.family.design))
                        metaRow
                        if mode == .preview {
                            MarkdownPreview(text: note.body, typography: typo, onToggleCheckbox: toggleCheckbox, onOpenNote: openNote)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 36).padding(.top, 24)
                    .frame(maxWidth: maxTextWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    if mode != .preview {
                        MarkdownTextView(text: $note.body, controller: editor, focusToken: app.noteFocusRequest, typography: typo)
                            .frame(minHeight: 420)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: maxTextWidth + 8)
                            .frame(maxWidth: .infinity)
                    }
                    linksSection.padding(.horizontal, 36).padding(.bottom, 30)
                        .frame(maxWidth: maxTextWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                if mode == .split {
                    Divider()
                    ScrollView {
                        MarkdownPreview(text: note.body, typography: typo, onToggleCheckbox: toggleCheckbox, onOpenNote: openNote)
                            .padding(28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.02))
                }
            }
        }
        .onChange(of: note.body) { touch() }
        .onChange(of: note.title) { touch() }
    }

    func touch() {
        note.updatedAt = Date()
        // Aktivite akışını boğmamak için 10 dakikada bir "güncellendi" kaydı
        if Date().timeIntervalSince(lastLogged) > 600, !note.title.isEmpty {
            lastLogged = Date()
            Store.log(context, "Not güncellendi: **\(note.title)**", icon: "pencil", color: "#9B78E8", projectID: note.projectID)
        }
    }

    var toolbar: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
            Group {
                tb("H1", nil) { editor.linePrefix("# ") }
                tb("H2", nil) { editor.linePrefix("## ") }
                tb("H3", nil) { editor.linePrefix("### ") }
                sep
                tb(nil, "bold") { editor.wrap("**") }
                tb(nil, "italic") { editor.wrap("*") }
                tb(nil, "underline") { editor.wrap("<u>", "</u>") }
                sep
                tb(nil, "list.bullet") { editor.linePrefix("- ") }
                tb(nil, "list.number") { editor.linePrefix("", numbered: true) }
                tb(nil, "checklist") { editor.linePrefix("- [ ] ") }
            }
            Group {
                sep
                tb(nil, "chevron.left.forwardslash.chevron.right") { editor.codeBlock() }
                tb(nil, "text.quote") { editor.linePrefix("> ") }
                tb(nil, "link") { editor.wrap("[", "](https://)", placeholder: "bağlantı") }
                Menu {
                    ForEach(notes.filter { $0.isLive && $0.id != note.id && !$0.title.isEmpty }.prefix(40)) { n in
                        Button(n.title) { editor.insert("[[\(n.title)]]") }
                    }
                } label: { Image(systemName: "link.badge.plus") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Başka nota bağla [[…]]")
                tb(nil, "photo") { if let md = Attachments.pick(images: true) { editor.insert("\n\(md)\n") } }
                tb(nil, "paperclip") { if let md = Attachments.pick(images: false) { editor.insert(md) } }
            }
            .disabled(mode == .preview)
            }
            }
            .frame(minWidth: 60)
            .layoutPriority(-1)
            Spacer(minLength: 8)
            typographyMenu
            Button { note.pinned.toggle() } label: { Image(systemName: note.pinned ? "pin.fill" : "pin") }
                .buttonStyle(.plain).foregroundStyle(note.pinned ? Palette.purple : .secondary).help("Sabitle")
                .padding(.horizontal, 6)
            Button { note.favorite.toggle() } label: { Image(systemName: note.favorite ? "star.fill" : "star") }
                .buttonStyle(.plain).foregroundStyle(note.favorite ? Palette.warning : .secondary).help("Favori")
                .padding(.horizontal, 6)
            Picker("", selection: $modeRaw) {
                ForEach(EditorMode.allCases, id: \.self) { m in
                    Image(systemName: m.icon).help(m.rawValue).tag(m.rawValue)
                }
            }.pickerStyle(.segmented).fixedSize().help("Düzenle / Bölünmüş / Önizleme")
            Menu {
                Button("Arşivle") { note.archived = true; app.selectedNoteID = nil }
                Button("Çöpe taşı", role: .destructive) { note.deletedAt = Date(); app.selectedNoteID = nil }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .padding(.top, 18)
    }

    var typographyMenu: some View {
        Menu {
            Picker("Yazı tipi", selection: $fontRaw) {
                ForEach(EditorTypography.Family.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Boyut", selection: $fontSize) {
                ForEach([13.0, 14, 15, 16, 17, 18, 20, 22], id: \.self) { Text("\(Int($0)) pt").tag($0) }
            }
            Picker("Satır aralığı", selection: $lineHeight) {
                Text("Sıkı").tag(1.2)
                Text("Normal").tag(1.45)
                Text("Rahat").tag(1.7)
            }
            Toggle("Okunabilir genişlik", isOn: $readable)
        } label: {
            Text("Aa").font(.system(size: 13, weight: .semibold, design: typo.family.design))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Yazı tipi ve boyut")
        .padding(.horizontal, 6)
    }

    var sep: some View { Divider().frame(height: 16).padding(.horizontal, 4) }

    func tb(_ label: String?, _ icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let label { Text(label).font(.system(size: 12, weight: .bold)) }
                if let icon { Image(systemName: icon).font(.system(size: 12.5, weight: .medium)) }
            }
            .frame(width: 28, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.0001)))
    }

    var metaRow: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Klasör yok") { note.folderID = nil }
                ForEach(folders) { f in Button(f.name) { note.folderID = f.id } }
            } label: {
                let f = folders.first { $0.id == note.folderID }
                Label(f?.name ?? "Klasör", systemImage: f?.icon ?? "folder")
            }.menuStyle(.borderlessButton).fixedSize()
            Menu {
                Button("Proje yok") { note.projectID = nil }
                ForEach(projects.filter(\.isLive)) { p in Button(p.name) { note.projectID = p.id } }
            } label: {
                let p = projects.first { $0.id == note.projectID }
                Label(p?.name ?? "Proje", systemImage: p?.icon ?? "square.stack.3d.up")
            }.menuStyle(.borderlessButton).fixedSize()
            FlowLayout(spacing: 5) {
                ForEach(note.tags, id: \.self) { t in
                    HStack(spacing: 3) {
                        Text("#\(t)")
                        Button { note.tags.removeAll { $0 == t } } label: { Image(systemName: "xmark").font(.system(size: 7, weight: .bold)) }.buttonStyle(.plain)
                    }
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.purple)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Capsule().fill(Palette.purple.opacity(0.12)))
                }
                TextField("+ etiket", text: $newTag).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 70)
                    .onSubmit {
                        let t = newTag.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces).lowercased()
                        if !t.isEmpty, !note.tags.contains(t) { note.tags.append(t) }
                        newTag = ""
                    }
            }
            Spacer()
            Text("Düzenlendi \(Fmt.ago(note.updatedAt))").font(.caption).foregroundStyle(.tertiary)
        }
        .font(.callout)
    }

    @ViewBuilder var linksSection: some View {
        if !outgoing.isEmpty || !backlinks.isEmpty || !relatedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider().padding(.vertical, 8)
                if !outgoing.isEmpty || !backlinks.isEmpty {
                    Text("İLİŞKİLİ NOTLAR").font(.system(size: 10.5, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(outgoing) { n in linkChip(n, icon: "arrow.up.right") }
                        ForEach(backlinks) { n in linkChip(n, icon: "arrow.turn.up.left") }
                    }
                }
                if !relatedTasks.isEmpty {
                    Text("İLİŞKİLİ GÖREVLER").font(.system(size: 10.5, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
                    ForEach(relatedTasks) { TaskRow(task: $0, compact: true) }
                }
            }
        }
    }

    func linkChip(_ n: Note, icon: String) -> some View {
        Button { app.selectedNoteID = n.id } label: {
            Label(n.title, systemImage: icon).font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.1)))
        }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
    }

    func toggleCheckbox(_ line: Int) {
        var lines = note.body.components(separatedBy: "\n")
        guard line < lines.count else { return }
        if lines[line].contains("- [ ]") { lines[line] = lines[line].replacingOccurrences(of: "- [ ]", with: "- [x]") }
        else { lines[line] = lines[line].replacingOccurrences(of: "- [x]", with: "- [ ]").replacingOccurrences(of: "- [X]", with: "- [ ]") }
        note.body = lines.joined(separator: "\n")
    }

    func openNote(_ title: String) {
        if let n = notes.first(where: { $0.isLive && $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
            app.selectedNoteID = n.id
        } else {
            // Bağlantı verilen not yoksa oluştur
            let n = Store.createNote(context: context, title: title, body: "# \(title)\n\n", projectID: note.projectID, folderID: note.folderID)
            app.selectedNoteID = n.id
        }
    }
}

import SwiftUI
import SwiftData

struct StarterItem: Hashable {
    let name: String
    let icon: String
    let color: String
}

/// İlk açılışta gösterilen karşılama akışı
struct OnboardingView: View {
    @Environment(\.modelContext) var context
    @EnvironmentObject var app: AppState
    @AppStorage("onboarded") var onboarded = false
    @AppStorage("userName") var userName = ""
    @AppStorage("theme") var theme: AppTheme = .system
    @AppStorage("accent") var accent = "#6558F5"
    @Query var existingProjects: [Project]
    @Query var existingHabits: [Habit]

    @State private var step = 0
    @State private var forward = true
    @State private var pickedProjects: Set<StarterItem> = []
    @State private var pickedHabits: Set<StarterItem> = []
    @FocusState private var nameFocused: Bool

    static let projectOptions = [
        StarterItem(name: "Kişisel", icon: "person.fill", color: "#FF786B"),
        StarterItem(name: "İş", icon: "briefcase.fill", color: "#F2B84B"),
        StarterItem(name: "Okul", icon: "graduationcap.fill", color: "#35B88A"),
        StarterItem(name: "Yazılım", icon: "chevron.left.forwardslash.chevron.right", color: "#6558F5"),
        StarterItem(name: "Öğrenme", icon: "book.fill", color: "#55A7E8"),
        StarterItem(name: "Yan Projeler", icon: "lightbulb.fill", color: "#9B78E8"),
        StarterItem(name: "Sağlık", icon: "heart.fill", color: "#E86BA8"),
        StarterItem(name: "Ev", icon: "house.fill", color: "#4CC3C3"),
    ]
    static let habitOptions = [
        StarterItem(name: "Kitap okudum", icon: "book.fill", color: "#35B88A"),
        StarterItem(name: "Spor yaptım", icon: "figure.run", color: "#F2B84B"),
        StarterItem(name: "Kod yazdım", icon: "chevron.left.forwardslash.chevron.right", color: "#6558F5"),
        StarterItem(name: "Su içtim", icon: "drop.fill", color: "#55A7E8"),
        StarterItem(name: "Meditasyon", icon: "leaf.fill", color: "#4CC3C3"),
        StarterItem(name: "Erken kalktım", icon: "sunrise.fill", color: "#9B78E8"),
    ]

    let steps = 5

    var body: some View {
        ZStack {
            // Arka plan
            ZStack {
                AppBackground()
                Circle().fill(Color(hex: accent).opacity(0.35)).frame(width: 520).blur(radius: 140).offset(x: -320, y: -220)
                Circle().fill(Palette.info.opacity(0.28)).frame(width: 460).blur(radius: 140).offset(x: 360, y: 240)
                Circle().fill(Palette.purple.opacity(0.22)).frame(width: 380).blur(radius: 120).offset(x: 300, y: -260)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: nameStep
                    case 2: appearance
                    case 3: tour
                    default: setup
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                .frame(maxWidth: 760)
                Spacer(minLength: 20)
                footer
            }
            .padding(40)
        }
        .onAppear { if existingProjects.isEmpty && existingHabits.isEmpty { pickedProjects = [Self.projectOptions[0]] } }
    }

    // MARK: Adımlar

    var welcome: some View {
        VStack(spacing: 22) {
            OrbitLogo()
                .frame(width: 96, height: 96)
                .scaleEffect(1.6)
                .padding(.bottom, 20)
                .symbolEffect(.pulse)
            Text("Orbit'e hoş geldin")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("Görevlerin, takvimin, notların, projelerin ve günlüğün tek bir yerde.\nUygulamayı açtığında bugün ne yapacağını tek ekranda gör.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            HStack(spacing: 10) {
                badge("lock.fill", "Tamamen yerel")
                badge("wifi.slash", "İnternetsiz çalışır")
                badge("arrow.triangle.2.circlepath", "Otomatik kayıt")
            }
            .padding(.top, 6)
        }
    }

    var nameStep: some View {
        VStack(spacing: 18) {
            stepIcon("hand.wave.fill", Palette.warning)
            Text("Sana nasıl hitap edelim?").font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Ana ekrandaki karşılama mesajında kullanılır. İstersen boş bırakabilirsin.")
                .foregroundStyle(.secondary)
            TextField("Adın", text: $userName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14).padding(.horizontal, 20)
                .frame(width: 360)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: accent).opacity(nameFocused ? 0.6 : 0.15), lineWidth: 1.5))
                .focused($nameFocused)
                .onSubmit { next() }
                .onAppear { nameFocused = true }
            if !userName.isEmpty {
                Text("Günaydın, \(userName) 👋").font(.title3).foregroundStyle(.secondary).transition(.opacity)
            }
        }
        .animation(.snappy, value: userName.isEmpty)
    }

    var appearance: some View {
        VStack(spacing: 22) {
            stepIcon("paintpalette.fill", Palette.purple)
            Text("Görünümünü seç").font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Bunları daha sonra Ayarlar'dan değiştirebilirsin.").foregroundStyle(.secondary)
            HStack(spacing: 14) {
                ForEach(AppTheme.allCases) { t in
                    Button { withAnimation(.snappy) { theme = t } } label: {
                        VStack(spacing: 10) {
                            themePreview(t).frame(width: 150, height: 96)
                            Text(t.title).font(.callout.weight(.medium))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 16).fill(theme == t ? Color(hex: accent).opacity(0.14) : Color.primary.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme == t ? Color(hex: accent) : .clear, lineWidth: 2))
                    }.buttonStyle(.plain)
                }
            }
            VStack(spacing: 10) {
                Text("VURGU RENGİ").font(.system(size: 11, weight: .semibold)).kerning(1).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(Palette.accentChoices, id: \.self) { hex in
                        Circle().fill(Color(hex: hex).gradient).frame(width: 34, height: 34)
                            .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).opacity(accent == hex ? 1 : 0))
                            .scaleEffect(accent == hex ? 1.12 : 1)
                            .onTapGesture { withAnimation(.spring(duration: 0.3)) { accent = hex } }
                    }
                }
            }
        }
    }

    var tour: some View {
        VStack(spacing: 20) {
            stepIcon("sparkles", Palette.info)
            Text("Orbit'te neler var?").font(.system(size: 32, weight: .bold, design: .rounded))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                feature("house.fill", Palette.primary, "Home", "Günün özeti: odak görevler, program ve ilerleme.")
                feature("checkmark.circle.fill", Palette.success, "Tasks", "Liste, Kanban, öncelik görünümleri; tekrar eden görevler.")
                feature("calendar", Palette.info, "Calendar", "Gün, hafta, ay. Görevleri sürükleyip zamana taşı.")
                feature("square.stack.3d.up.fill", Palette.purple, "Projects", "Her proje kendi çalışma alanı ve aktivite akışı.")
                feature("note.text", Palette.warning, "Notes", "Markdown, klasörler, etiketler ve [[not bağlantıları]].")
                feature("book.closed.fill", Color(hex: "#E86BA8"), "Journal", "Günlük sayfa, ruh hali ve alışkanlık takibi.")
            }
            HStack(spacing: 18) {
                shortcut("⌘K", "Her şeyi ara")
                shortcut("⇧⌘N", "Yeni görev")
                shortcut("⌘N", "Yeni not")
                shortcut("⌘1–7", "Bölümler")
            }
            .padding(.top, 4)
        }
    }

    var setup: some View {
        VStack(spacing: 18) {
            stepIcon("square.stack.3d.up.fill", Palette.success)
            Text("Hızlı bir başlangıç yapalım").font(.system(size: 32, weight: .bold, design: .rounded))
            Text("İstediklerini seç; boş projeler ve alışkanlıklar oluşturulur. Hiçbirini seçmeden de devam edebilirsin.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                Text("PROJELER").font(.system(size: 11, weight: .semibold)).kerning(1).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(Self.projectOptions, id: \.self) { item in chip(item, selected: pickedProjects.contains(item)) { toggle(&pickedProjects, item) } }
                }
                Text("GÜNLÜK ALIŞKANLIKLAR").font(.system(size: 11, weight: .semibold)).kerning(1).foregroundStyle(.secondary).padding(.top, 8)
                FlowLayout(spacing: 8) {
                    ForEach(Self.habitOptions, id: \.self) { item in chip(item, selected: pickedHabits.contains(item)) { toggle(&pickedHabits, item) } }
                }
            }
            .padding(20)
            .frame(width: 620, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.primary.opacity(0.04)))
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill").foregroundStyle(Palette.warning)
                Text("Hatırlatıcılar için bitirdiğinde macOS bildirim izni isteyeceğiz.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Alt çubuk

    var footer: some View {
        HStack {
            if step > 0 {
                Button { go(step - 1) } label: { Label("Geri", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.leftArrow, modifiers: [])
            } else {
                Button("Atla") { finish() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule().fill(i == step ? Color(hex: accent) : Color.primary.opacity(0.15))
                        .frame(width: i == step ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: step)
            Spacer()
            Button { next() } label: {
                HStack(spacing: 6) {
                    Text(step == steps - 1 ? "Başlayalım" : (step == 0 ? "Hadi başlayalım" : "Devam"))
                    Image(systemName: step == steps - 1 ? "checkmark" : "arrow.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(Capsule().fill(Color(hex: accent).gradient))
                .shadow(color: Color(hex: accent).opacity(0.4), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: 760)
    }

    // MARK: Yardımcılar

    func next() { step < steps - 1 ? go(step + 1) : finish() }

    func go(_ s: Int) {
        forward = s > step
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { step = s }
    }

    func finish() {
        let existingNames = Set(existingProjects.map(\.name))
        let existingHabitNames = Set(existingHabits.map(\.name))
        Seed.starter(context,
                     projects: Self.projectOptions.filter { pickedProjects.contains($0) && !existingNames.contains($0.name) },
                     habits: Self.habitOptions.filter { pickedHabits.contains($0) && !existingHabitNames.contains($0.name) })
        Notifier.requestAuthorization()
        withAnimation(.easeInOut(duration: 0.4)) { onboarded = true }
        app.go(.home)
    }

    func toggle(_ set: inout Set<StarterItem>, _ item: StarterItem) {
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
    }

    func stepIcon(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.gradient))
            .shadow(color: color.opacity(0.4), radius: 14, y: 6)
    }

    func badge(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    func feature(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.gradient))
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .card(padding: 16)
    }

    func shortcut(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key).font(.system(.callout, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
    }

    func chip(_ item: StarterItem, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy(duration: 0.2)) { action() } }) {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark" : item.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(selected ? .white : Color(hex: item.color))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(selected ? Color(hex: item.color) : Color(hex: item.color).opacity(0.15)))
                    .contentTransition(.symbolEffect(.replace))
                Text(item.name).font(.system(size: 13.5, weight: .medium))
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .background(Capsule().fill(selected ? Color(hex: item.color).opacity(0.16) : Color.primary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(selected ? Color(hex: item.color).opacity(0.6) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    func themePreview(_ t: AppTheme) -> some View {
        let dark = Palette.darkBG, light = Palette.lightBG
        return ZStack {
            switch t {
            case .light: mini(bg: light, card: .white, line: .black.opacity(0.12))
            case .dark: mini(bg: dark, card: .white.opacity(0.08), line: .white.opacity(0.18))
            case .system:
                HStack(spacing: 0) {
                    mini(bg: light, card: .white, line: .black.opacity(0.12))
                    mini(bg: dark, card: .white.opacity(0.08), line: .white.opacity(0.18))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
    }

    func mini(bg: Color, card: Color, line: Color) -> some View {
        ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: accent).gradient).frame(height: 20)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4).fill(card)
                    RoundedRectangle(cornerRadius: 4).fill(card)
                }
                RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 40, height: 4)
            }
            .padding(9)
        }
    }
}

/// Yeni kullanıcı için Home'daki başlangıç rehberi; adımlar veriden otomatik işaretlenir
struct GettingStartedCard: View {
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @AppStorage("gettingStartedHidden") var hidden = false
    @AppStorage("usedPalette") var usedPalette = false
    @Query var tasks: [TaskItem]
    @Query var projects: [Project]
    @Query var notes: [Note]
    @Query var events: [CalEvent]
    @Query var journal: [JournalEntry]

    struct Step: Identifiable { let id: String; let title: String; let hint: String; let icon: String; let color: Color; let done: Bool; let action: () -> Void }

    var steps: [Step] {
        [
            Step(id: "task", title: "İlk görevini ekle", hint: "Yukarıdaki hızlı görev alanına yaz ya da ⇧⌘N", icon: "checkmark.circle.fill", color: Palette.success, done: tasks.contains { $0.isLive || $0.isDone }) { app.newTask(due: Date().startOfDay) },
            Step(id: "project", title: "Bir proje oluştur", hint: "Sol menüde Projeler yanındaki +", icon: "square.stack.3d.up.fill", color: Palette.purple, done: projects.contains(where: \.isLive)) { app.go(.projects) },
            Step(id: "note", title: "Bir not yaz", hint: "⌘N ile yeni not; [[başlık]] ile notları bağla", icon: "note.text", color: Palette.warning, done: notes.contains { !$0.body.isEmpty || !$0.title.isEmpty }) { app.newNote(context: context) },
            Step(id: "event", title: "Takvime bir etkinlik koy", hint: "Takvimde boş bir saate çift tıkla", icon: "calendar", color: Palette.info, done: !events.isEmpty) { app.go(.calendar) },
            Step(id: "journal", title: "Günlüğüne ilk sayfayı yaz", hint: "Hedefler, ruh hali, alışkanlıklar", icon: "book.closed.fill", color: Color(hex: "#E86BA8"), done: journal.contains { !$0.isEmpty }) { app.go(.journal) },
            Step(id: "palette", title: "⌘K ile her şeyi ara", hint: "Komut paleti: görev, not, proje, etiket…", icon: "command", color: Palette.primary, done: usedPalette) { app.showPalette = true },
        ]
    }

    var body: some View {
        let s = steps
        let done = s.filter(\.done).count
        if !hidden && done < s.count {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        ProgressRing(progress: Double(done) / Double(s.count), lineWidth: 5, color: Color.accentColor)
                        Text("\(done)/\(s.count)").font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Başlangıç rehberi").font(.system(size: 15, weight: .semibold))
                        Text("Orbit'i tanımak için birkaç küçük adım. Yaptıkça kendiliğinden işaretlenir.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { withAnimation { hidden = true } } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Rehberi gizle")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                    ForEach(s) { step in
                        Button(action: step.action) {
                            HStack(spacing: 10) {
                                Image(systemName: step.done ? "checkmark" : step.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(step.done ? Palette.success.gradient : step.color.gradient))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(step.title).font(.system(size: 13, weight: .semibold))
                                        .strikethrough(step.done).foregroundStyle(step.done ? .secondary : .primary)
                                    Text(step.hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(step.done ? Palette.success.opacity(0.08) : Color.primary.opacity(0.04)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(step.done)
                    }
                }
            }
            .card()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

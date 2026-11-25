import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) var context
    @State private var day = Date().startOfDay
    @State private var entry: JournalEntry?
    @Query(sort: \JournalEntry.day, order: .reverse) var entries: [JournalEntry]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let entry { JournalPage(entry: entry, day: day) }
                }
                .padding(28)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            Divider()
            history.frame(width: 250)
        }
        .onAppear(perform: load)
        .onChange(of: day) { load() }
    }

    func load() { entry = Store.journal(for: day, context: context) }

    var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#E86BA8").gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("Journal").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(Fmt.longDate.string(from: day)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                Button { day = day.adding(days: -1) } label: { Image(systemName: "chevron.left") }
                Button("Bugün") { day = Date().startOfDay }.disabled(Calendar.current.isDateInToday(day))
                Button { day = day.adding(days: 1) } label: { Image(systemName: "chevron.right") }
            }
        }
    }

    var history: some View {
        let written = entries.filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            Text("GEÇMİŞ").font(.system(size: 10.5, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
                .padding(.top, 34)
            // Son 5 haftanın ısı haritası
            let start = Date().startOfWeek.adding(days: -28)
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { w in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            let d = start.adding(days: w * 7 + i)
                            let e = written.first { Calendar.current.isDate($0.day, inSameDayAs: d) }
                            RoundedRectangle(cornerRadius: 4)
                                .fill(e.map { moodColor($0.mood).opacity(0.85) } ?? Color.primary.opacity(d > Date() ? 0.02 : 0.07))
                                .frame(width: 26, height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Calendar.current.isDate(d, inSameDayAs: day) ? Color.accentColor : .clear, lineWidth: 2))
                                .onTapGesture { if d <= Date() { day = d.startOfDay } }
                                .help(Fmt.dayMonth.string(from: d))
                        }
                    }
                }
            }
            Divider().padding(.vertical, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(written) { e in
                        Button { day = e.day } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(Fmt.dayMonthWeekday.string(from: e.day)).font(.callout.weight(.semibold))
                                    Spacer()
                                    if e.mood > 0 { Text(moods[e.mood - 1].0) }
                                }
                                Text([e.freeText, e.goals, e.done].first { !$0.isEmpty } ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Calendar.current.isDate(e.day, inSameDayAs: day) ? Color.accentColor.opacity(0.13) : .clear))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
    }
}

let moods: [(String, String)] = [("😞", "Kötü"), ("😕", "Meh"), ("🙂", "İyi"), ("😄", "Harika"), ("🤩", "Muhteşem")]
func moodColor(_ m: Int) -> Color {
    switch m {
    case 1: Palette.secondary
    case 2: Palette.warning
    case 3: Palette.info
    case 4: Palette.success
    case 5: Palette.purple
    default: Palette.primary.opacity(0.5)
    }
}

struct JournalPage: View {
    @Bindable var entry: JournalEntry
    let day: Date
    @Query var tasks: [TaskItem]
    @Query(sort: \Habit.sortIndex) var habits: [Habit]
    @Query var allEntries: [JournalEntry]
    @Environment(\.modelContext) var context
    @State private var newHabit = ""

    var completed: [TaskItem] {
        tasks.filter { $0.isLive && $0.isDone && ($0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Alışkanlıklar
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Alışkanlıklar", icon: "flame.fill", color: Palette.warning)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(habits) { h in
                        let on = entry.habitsDone.contains(h.name)
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                if on { entry.habitsDone.removeAll { $0 == h.name } } else { entry.habitsDone.append(h.name) }
                                entry.updatedAt = Date()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: on ? "checkmark" : h.icon)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(on ? .white : Color(hex: h.colorHex))
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(on ? Color(hex: h.colorHex) : Color(hex: h.colorHex).opacity(0.14)))
                                    .contentTransition(.symbolEffect(.replace))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(h.name).font(.system(size: 13, weight: .medium))
                                    Text("🔥 \(streak(h.name)) gün").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color(hex: h.colorHex).opacity(0.12) : Color.primary.opacity(0.04)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Alışkanlığı sil", role: .destructive) { context.delete(h) } }
                    }
                    HStack {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                        TextField("Yeni alışkanlık", text: $newHabit).textFieldStyle(.plain).onSubmit {
                            guard !newHabit.isEmpty else { return }
                            context.insert(Habit(name: newHabit, icon: "star.fill", colorHex: Palette.projectColors[habits.count % Palette.projectColors.count], sortIndex: habits.count))
                            newHabit = ""
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
            }
            .card()

            HStack(alignment: .top, spacing: 18) {
                journalField("Bugünkü hedefler", "target", Palette.primary, $entry.goals, "- Bugün neyi başarmak istiyorsun?")
                journalField("Gün içinde yapılanlar", "list.bullet.clipboard", Palette.info, $entry.done, "- Neler yaptın?")
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Tamamlanan görevler · \(completed.count)", icon: "checkmark.circle.fill", color: Palette.success)
                if completed.isEmpty { Text("Bu gün tamamlanan görev yok.").font(.callout).foregroundStyle(.secondary) }
                ForEach(completed) { TaskRow(task: $0, compact: true) }
            }
            .card()

            journalField("Serbest yazı", "pencil.line", Palette.purple, $entry.freeText, "Aklından geçenleri yaz…", minHeight: 160)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Gün sonu değerlendirmesi", icon: "moon.stars.fill", color: Palette.warning)
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { m in
                        Button { withAnimation(.spring(duration: 0.3)) { entry.mood = entry.mood == m ? 0 : m } } label: {
                            VStack(spacing: 3) {
                                Text(moods[m - 1].0).font(.system(size: 26))
                                Text(moods[m - 1].1).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 70, height: 62)
                            .background(RoundedRectangle(cornerRadius: 12).fill(entry.mood == m ? moodColor(m).opacity(0.2) : Color.primary.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(entry.mood == m ? moodColor(m) : .clear, lineWidth: 1.5))
                            .scaleEffect(entry.mood == m ? 1.06 : 1)
                        }.buttonStyle(.plain)
                    }
                }
                editor($entry.review, "Gün nasıl geçti? Neyi daha iyi yapabilirdin?", 80)
            }
            .card()

            journalField("Yarın için notlar", "sunrise.fill", Palette.teal, $entry.tomorrow, "- Yarın ilk iş…")
        }
        .onChange(of: entry.freeText) { entry.updatedAt = Date() }
    }

    func streak(_ habit: String) -> Int {
        var count = 0
        var d = day
        while let e = allEntries.first(where: { Calendar.current.isDate($0.day, inSameDayAs: d) }), e.habitsDone.contains(habit) {
            count += 1
            d = d.adding(days: -1)
        }
        return count
    }

    func journalField(_ title: String, _ icon: String, _ color: Color, _ text: Binding<String>, _ placeholder: String, minHeight: CGFloat = 100) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, icon: icon, color: color)
            editor(text, placeholder, minHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }

    func editor(_ text: Binding<String>, _ placeholder: String, _ minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder).font(.system(size: 14)).foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false)
                }
            }
    }
}

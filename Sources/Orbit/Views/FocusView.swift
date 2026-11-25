import SwiftUI
import SwiftData
import Charts

struct FocusView: View {
    @EnvironmentObject var focus: FocusTimer
    @EnvironmentObject var app: AppState
    @Query var tasks: [TaskItem]
    @Query(sort: \FocusSession.start, order: .reverse) var sessions: [FocusSession]
    @AppStorage("pomo.focus") var focusMin = 25
    @AppStorage("pomo.short") var shortMin = 5
    @AppStorage("pomo.long") var longMin = 15
    @AppStorage("pomo.rounds") var rounds = 4
    @AppStorage("pomo.autostart") var autoStart = true

    var openTasks: [TaskItem] {
        tasks.filter { $0.isLive && !$0.isDone }.sorted(by: TaskSort.byPriorityThenTime)
    }
    var todaySessions: [FocusSession] { sessions.filter { Calendar.current.isDateInToday($0.start) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "timer").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.secondary.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Focus").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Pomodoro: \(focusMin) dk odak, \(shortMin) dk mola").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(alignment: .top, spacing: 20) {
                    timerCard.frame(maxWidth: .infinity)
                    VStack(spacing: 20) {
                        statsCard
                        settingsCard
                    }
                    .frame(width: 340)
                }
                weekCard
            }
            .padding(28)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Zamanlayıcı

    var timerCard: some View {
        let shown = focus.isActive ? focus.phase : focus.upcoming
        return VStack(spacing: 24) {
            HStack(spacing: 6) {
                ForEach([FocusPhase.focus, .shortBreak, .longBreak], id: \.self) { p in
                    Text(p.title)
                        .font(.system(size: 13, weight: shown == p ? .semibold : .regular))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundStyle(shown == p ? .white : .secondary)
                        .background(Capsule().fill(shown == p ? p.color : Color.primary.opacity(0.05)))
                }
            }
            ZStack {
                Circle().stroke(shown.color.opacity(0.12), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: max(0.001, focus.progress))
                    .stroke(AngularGradient(colors: [shown.color.opacity(0.5), shown.color], center: .center), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: focus.progress)
                VStack(spacing: 6) {
                    Image(systemName: shown.icon).font(.system(size: 22)).foregroundStyle(shown.color)
                        .symbolEffect(.pulse, isActive: focus.isRunning)
                    Text(focus.remainingText)
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: focus.remainingText)
                    Text(focus.isPaused ? "Duraklatıldı" : focus.isRunning ? shown.title : "Başlamaya hazır")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(width: 280, height: 280)

            // Tur noktaları
            HStack(spacing: 8) {
                ForEach(0..<rounds, id: \.self) { i in
                    Circle()
                        .fill(i < focus.round % rounds || (focus.round > 0 && focus.round % rounds == 0 && !focus.isActive) ? Palette.secondary : Color.primary.opacity(0.12))
                        .frame(width: 9, height: 9)
                }
            }

            // Görev seçici
            Menu {
                Button("Görevsiz odaklan") { focus.setTask(nil) }
                Divider()
                ForEach(openTasks.prefix(25)) { t in
                    Button(t.title) { focus.setTask(t) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: focus.taskTitle.isEmpty ? "scope" : "checkmark.circle")
                    Text(focus.taskTitle.isEmpty ? "Bir görev seç (isteğe bağlı)" : focus.taskTitle).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            HStack(spacing: 14) {
                if focus.isActive {
                    circleButton("arrow.counterclockwise", "Sıfırla") { focus.stop() }
                }
                Button {
                    if focus.isRunning { focus.pause() }
                    else if focus.isPaused { focus.resume() }
                    else { focus.startUpcoming() }
                } label: {
                    Label(focus.isRunning ? "Duraklat" : focus.isPaused ? "Devam et" : (focus.upcoming == .focus ? "Odaklanmaya başla" : "Molayı başlat"),
                          systemImage: focus.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(Capsule().fill(shown.color.gradient))
                        .shadow(color: shown.color.opacity(0.4), radius: 12, y: 5)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                circleButton("forward.end.fill", "Atla") { focus.skip() }
            }
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .card()
    }

    func circleButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: İstatistik

    var statsCard: some View {
        let total = todaySessions.reduce(0) { $0 + $1.minutes }
        let byTask = Dictionary(grouping: todaySessions.filter { !$0.taskTitle.isEmpty }, by: \.taskTitle)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Bugün", icon: "chart.bar.fill", color: Palette.secondary)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(todaySessions.count)").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Palette.secondary)
                    Text("pomodoro").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.duration(total)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Palette.success)
                    Text("odak süresi").font(.caption).foregroundStyle(.secondary)
                }
            }
            if byTask.isEmpty {
                Text("Henüz bugün odak oturumu yok.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(byTask.prefix(5), id: \.0) { name, mins in
                HStack {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text(name).lineLimit(1)
                    Spacer()
                    Text(Fmt.duration(mins)).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Süreler", icon: "slider.horizontal.3", color: Palette.purple)
            Stepper("Odak: \(focusMin) dk", value: $focusMin, in: 5...120, step: 5)
            Stepper("Kısa mola: \(shortMin) dk", value: $shortMin, in: 1...30)
            Stepper("Uzun mola: \(longMin) dk", value: $longMin, in: 5...60, step: 5)
            Stepper("Uzun moladan önce: \(rounds) tur", value: $rounds, in: 2...8)
            Toggle("Sonraki fazı otomatik başlat", isOn: $autoStart)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    var weekCard: some View {
        let start = Date().startOfDay.adding(days: -6)
        let days = (0..<7).map { start.adding(days: $0) }
        let data = days.map { d in (d, sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: d) }.reduce(0) { $0 + $1.minutes }) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Son 7 gün", icon: "calendar", color: Palette.info, trailing: AnyView(
                Text("Toplam \(Fmt.duration(data.reduce(0) { $0 + $1.1 }))").font(.callout).foregroundStyle(.secondary)
            ))
            Chart(data, id: \.0) { d, m in
                BarMark(x: .value("Gün", Fmt.weekdayShort.string(from: d)), y: .value("Dakika", m))
                    .foregroundStyle(Calendar.current.isDateInToday(d) ? Palette.secondary.gradient : Palette.secondary.opacity(0.45).gradient)
                    .cornerRadius(6)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 160)
        }
        .card()
    }
}

/// Zamanlayıcı çalışırken her ekranda sağ üstte görünen küçük kapsül
struct FocusPill: View {
    @EnvironmentObject var focus: FocusTimer
    @EnvironmentObject var app: AppState

    var body: some View {
        if focus.isActive && app.selection != .focus {
            HStack(spacing: 8) {
                Image(systemName: focus.phase.icon).foregroundStyle(focus.phase.color)
                Text(focus.remainingText).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                if !focus.taskTitle.isEmpty {
                    Text(focus.taskTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 140)
                }
                Button { focus.isRunning ? focus.pause() : focus.resume() } label: {
                    Image(systemName: focus.isRunning ? "pause.fill" : "play.fill").font(.caption)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(focus.phase.color.opacity(0.4)))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .onTapGesture { app.go(.focus) }
            .padding(.top, 14).padding(.trailing, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

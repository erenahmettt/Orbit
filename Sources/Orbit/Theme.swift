import SwiftUI

enum Palette {
    static let primary = Color(hex: "#6558F5")
    static let secondary = Color(hex: "#FF786B")
    static let success = Color(hex: "#35B88A")
    static let warning = Color(hex: "#F2B84B")
    static let info = Color(hex: "#55A7E8")
    static let purple = Color(hex: "#9B78E8")
    static let teal = Color(hex: "#4CC3C3")
    static let blue = Color(hex: "#4C8DF5")
    static let lightBG = Color(hex: "#F5F4F1")
    static let darkBG = Color(hex: "#202127")

    static let projectColors = ["#6558F5", "#FF786B", "#35B88A", "#F2B84B", "#55A7E8", "#9B78E8", "#E86BA8", "#4CC3C3", "#8A94A6"]
    static let accentChoices = ["#6558F5", "#FF786B", "#35B88A", "#55A7E8", "#9B78E8", "#E86BA8", "#F2B84B"]
    static let projectIcons = ["folder.fill", "person.fill", "chevron.left.forwardslash.chevron.right", "briefcase.fill", "book.fill", "lightbulb.fill", "paintbrush.fill", "graduationcap.fill", "heart.fill", "star.fill", "hammer.fill", "globe", "camera.fill", "music.note", "gamecontroller.fill", "airplane", "dumbbell.fill", "leaf.fill", "cart.fill", "flame.fill"]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "Sistem"; case .light: "Açık"; case .dark: "Koyu" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

struct AppBackground: View {
    @Environment(\.colorScheme) var scheme
    var body: some View {
        (scheme == .dark ? Palette.darkBG : Palette.lightBG).ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.055) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05))
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 14, y: 6)
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardStyle(padding: padding)) }
}

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var color: Color = .accentColor
    var trailing: AnyView? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(color.gradient))
            }
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            trailing
        }
    }
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}

struct ProjectBadge: View {
    let project: Project
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: project.icon)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(project.color.gradient))
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
            if !subtitle.isEmpty { Text(subtitle).font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var color: Color = Palette.success
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static let locale = Locale(identifier: "tr_TR")
    private static func f(_ format: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = locale
        d.setLocalizedDateFormatFromTemplate(format)
        return d
    }
    static let longDate = f("EEEEdMMMMyyyy")
    static let dayMonth = f("dMMM")
    static let dayMonthWeekday = f("EEEdMMM")
    static let monthYear = f("MMMMyyyy")
    static let time = f("HHmm")
    static let weekdayShort = f("EEE")
    static let weekdayLong = f("EEEE")

    static func weekdaySymbol(_ weekday: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        return cal.shortWeekdaySymbols[(weekday - 1) % 7]
    }

    static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInTomorrow(date) { return "Yarın" }
        if cal.isDateInYesterday(date) { return "Dün" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        if days > 1 && days < 7 { return weekdayLong.string(from: date).capitalized(with: locale) }
        return dayMonth.string(from: date)
    }

    static func ago(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 45 { return "şimdi" }
        let r = RelativeDateTimeFormatter()
        r.locale = locale
        r.unitsStyle = .short
        return r.localizedString(for: date, relativeTo: Date())
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) dk" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) sa" : "\(h) sa \(m) dk"
    }
}

extension Calendar {
    static var orbit: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        c.locale = Fmt.locale
        return c
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self)! }
    func adding(minutes: Int) -> Date { Calendar.current.date(byAdding: .minute, value: minutes, to: self)! }
    var minutesIntoDay: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    func at(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: self)!
    }
    var startOfWeek: Date {
        let cal = Calendar.orbit
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self))!
    }
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))!
    }
}

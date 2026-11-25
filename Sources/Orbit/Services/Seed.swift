import Foundation
import SwiftData

@MainActor
enum Seed {
    /// Açılışta yarım kalmış taslak görevleri temizler. Uygulama her zaman boş başlar.
    static func cleanup(_ ctx: ModelContext) {
        if let drafts = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDraft })) {
            drafts.forEach { ctx.delete($0) }
        }
    }

    /// Karşılama ekranında seçilen başlangıç projeleri ve alışkanlıklar (içerik yok, sadece iskelet)
    static func starter(_ ctx: ModelContext, projects: [StarterItem], habits: [StarterItem]) {
        for (i, p) in projects.enumerated() {
            let pr = Project(name: p.name, colorHex: p.color, icon: p.icon)
            pr.sortIndex = i
            pr.startDate = Date().startOfDay
            ctx.insert(pr)
        }
        for (i, h) in habits.enumerated() {
            ctx.insert(Habit(name: h.name, icon: h.icon, colorHex: h.color, sortIndex: i))
        }
        try? ctx.save()
    }

    static func wipe(_ ctx: ModelContext) {
        try? ctx.delete(model: TaskItem.self)
        try? ctx.delete(model: Project.self)
        try? ctx.delete(model: Note.self)
        try? ctx.delete(model: NoteFolder.self)
        try? ctx.delete(model: CalEvent.self)
        try? ctx.delete(model: JournalEntry.self)
        try? ctx.delete(model: Habit.self)
        try? ctx.delete(model: Activity.self)
        try? ctx.save()
    }
}

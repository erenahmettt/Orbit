import AppKit
import SwiftUI

/// Geliştirme aracı: ORBIT_SNAPSHOT_DIR ayarlıysa her ekranı sırayla PNG olarak kaydeder ve çıkar.
/// Ekran kaydı izni gerektirmez (pencere kendi içeriğini çizer).
@MainActor
enum Snapshot {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] else { return }
        let app = AppState.shared
        let d = UserDefaults.standard
        let steps: [(String, () -> Void)] = [
            ("onboarding", { d.set(false, forKey: "onboarded") }),
            ("home", { d.set(true, forKey: "onboarded"); app.go(.home) }),
            ("today", { app.go(.today) }),
            ("tasks-kanban", { UserDefaults.standard.set("kanban", forKey: "taskViewMode"); app.go(.tasks) }),
            ("tasks-list", { UserDefaults.standard.set("list", forKey: "taskViewMode"); app.go(.upcoming) }),
            ("calendar-week", { UserDefaults.standard.set("week", forKey: "calMode"); app.go(.calendar) }),
            ("calendar-month", { UserDefaults.standard.set("month", forKey: "calMode"); app.go(.inbox); app.go(.calendar) }),
            ("focus", { app.go(.focus) }),
            ("focus-running", { FocusTimer.shared.start(); app.go(.home) }),
            ("note-serif", {
                FocusTimer.shared.stop()
                d.set("serif", forKey: "editorFont"); d.set(17.0, forKey: "editorSize")
                if let ctx = FocusTimer.shared.container?.mainContext {
                    let n = Store.createNote(context: ctx, title: "Tipografi testi", body: "# Başlık bir\n\nNormal paragraf metni, **kalın** ve *italik* kelimelerle. Satır aralığı ve yazı tipi burada görünür.\n\n## Liste\n- Birinci madde\n- [ ] Yapılacak\n- [x] Bitti\n\n> Bir alıntı satırı\n\n```\nlet x = 42\n```")
                    app.selectedNoteID = n.id
                }
                app.go(.notes)
            }),
            ("projects", { app.go(.projects) }),
            ("notes", { app.go(.notes) }),
            ("journal", { app.go(.journal) }),
            ("palette", { app.go(.home); app.showPalette = true }),
            ("settings", { app.showPalette = false; app.go(.settings) }),
        ]
        var i = 0
        func next() {
            guard i < steps.count else { NSApp.terminate(nil); return }
            let (name, action) = steps[i]
            i += 1
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                capture(to: "\(dir)/\(name).png")
                next()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { next() }
    }

    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 800 }) else { return }
        // Uygulama kendi penceresini yakalarken izin gerekmez; API yeni SDK'da gizlendiği için dinamik çağrılır.
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return }
        let fn = unsafeBitCast(sym, to: Fn.self)
        // .null rect, optionIncludingWindow (1<<3), boundsIgnoreFraming (1<<0)
        guard let img = fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

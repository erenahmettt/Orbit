import EventKit
import SwiftUI

struct ExternalEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let calendarName: String
}

/// Mac'in takvimindeki (Apple Calendar) etkinlikleri salt-okunur olarak getirir.
@MainActor
final class AppleCalendar: ObservableObject {
    static let shared = AppleCalendar()
    private let store = EKEventStore()
    @Published var authorized = false
    @Published var revision = 0

    init() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.revision += 1 }
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { granted, _ in
            Task { @MainActor in
                self.authorized = granted
                self.revision += 1
            }
        }
    }

    func events(from start: Date, to end: Date) -> [ExternalEvent] {
        guard authorized, UserDefaults.standard.bool(forKey: "appleCalendarEnabled") else { return [] }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred).map {
            ExternalEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "(Başlıksız)", start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, color: Color(cgColor: $0.calendar.cgColor), calendarName: $0.calendar.title)
        }
    }
}

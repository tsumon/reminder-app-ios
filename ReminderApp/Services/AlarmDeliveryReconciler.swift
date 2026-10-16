import Foundation

/// Production AlarmKit bookkeeping with injectable system effects for deterministic adapter checks.
/// The desired identity includes the exact date: a same-token holiday adjustment replaces the old chain.
@MainActor final class AlarmDeliveryReconciler {
    struct Key: Hashable {
        let reminderID: String
        let token: String
        let date: Date
        init(_ delivery: ReminderPolicy.Delivery) {
            reminderID = delivery.reminderID.uuidString; token = delivery.token; date = delivery.date
        }
        init(reminderID: String, token: String, date: Date) {
            self.reminderID = reminderID; self.token = token; self.date = date
        }
    }
    struct Entry: Codable {
        let id: UUID
        let reminderID: String
        let token: String
        let date: Date
        var key: Key { Key(reminderID: reminderID, token: token, date: date) }
    }
    private(set) var entries: [Entry]
    private var desired = Set<Key>()
    private var pending: [UUID: Key] = [:]
    private let persist: ([Entry]) -> Void

    init(entries: [Entry] = [], persist: @escaping ([Entry]) -> Void = { _ in }) {
        self.entries = entries; self.persist = persist
    }
    func reconcile(desired deliveries: [ReminderPolicy.Delivery], cancel: (UUID) -> Void) {
        desired = Set(deliveries.filter { $0.important && $0.kind != .advance }.map(Key.init))
        var retained = Set<Key>()
        let obsolete = entries.filter { !desired.contains($0.key) || !retained.insert($0.key).inserted }
        let obsoleteIDs = Set(obsolete.map(\.id))
        for entry in obsolete { cancel(entry.id) }
        entries.removeAll { obsoleteIDs.contains($0.id) }
        for (id, key) in Array(pending) where !desired.contains(key) {
            pending.removeValue(forKey: id)
            // If the system schedule is still suspended, cancellation is repeated when it returns.
            cancel(id)
        }
        persist(entries)
    }
    func schedule(_ delivery: ReminderPolicy.Delivery, exists: (UUID) -> Bool,
                  install: (UUID, ReminderPolicy.Delivery) async throws -> Void,
                  cancel: (UUID) -> Void) async -> Bool {
        let key = Key(delivery)
        guard desired.contains(key) else { return false }
        if let entry = entries.first(where: { $0.key == key }), exists(entry.id) { return true }
        entries.removeAll { $0.key == key }
        let id = UUID()
        pending[id] = key
        do {
            try await install(id, delivery)
            guard pending.removeValue(forKey: id) == key, desired.contains(key) else {
                cancel(id); return false
            }
            entries.append(Entry(id: id, reminderID: key.reminderID, token: key.token, date: key.date))
            persist(entries)
            return true
        } catch {
            pending.removeValue(forKey: id); cancel(id); persist(entries)
            return false
        }
    }
    func cancel(reminderID: UUID, systemCancel: (UUID) -> Void) {
        let reminderID = reminderID.uuidString
        for entry in entries where entry.reminderID == reminderID { systemCancel(entry.id) }
        entries.removeAll { $0.reminderID == reminderID }
        desired = desired.filter { $0.reminderID != reminderID }
        for (id, key) in Array(pending) where key.reminderID == reminderID {
            pending.removeValue(forKey: id); systemCancel(id)
        }
        persist(entries)
    }
}

import Foundation

/// A log entry involving a particular cat, with the moon it happened in.
struct LifeEvent: Identifiable {
    let moon: Int
    let entry: LogEntry

    var id: LogEntry.ID { entry.id }
}

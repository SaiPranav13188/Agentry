import Foundation
import SwiftData

@Model
final class ActivityEntry {
    var date: Date
    var event: String
    var details: String
    var kindRaw: String

    init(date: Date = .now, event: String, details: String = "", kind: ActivityKind = .system) {
        self.date = date
        self.event = event
        self.details = details
        self.kindRaw = kind.rawValue
    }

    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .system }

    static func log(_ context: ModelContext, _ event: String, _ details: String = "", kind: ActivityKind = .system) {
        context.insert(ActivityEntry(event: event, details: details, kind: kind))
    }
}

enum AgentryModels {
    static let all: [any PersistentModel.Type] = [
        Email.self, Draft.self, Reminder.self, JobApplication.self, ActivityEntry.self,
    ]
}

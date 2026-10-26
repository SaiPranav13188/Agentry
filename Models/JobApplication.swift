import Foundation
import SwiftData

@Model
final class JobApplication {
    var company: String
    var role: String
    var stageRaw: String
    var lastUpdate: Date
    var createdAt: Date
    /// Subject of the email that last changed this application.
    var lastEmailSubject: String
    var notes: String

    init(company: String, role: String, stage: JobStage, lastUpdate: Date = .now, lastEmailSubject: String = "") {
        self.company = company
        self.role = role
        self.stageRaw = stage.rawValue
        self.lastUpdate = lastUpdate
        self.createdAt = lastUpdate
        self.lastEmailSubject = lastEmailSubject
        self.notes = ""
    }

    var stage: JobStage {
        get { JobStage(rawValue: stageRaw) ?? .applied }
        set { stageRaw = newValue.rawValue }
    }
}

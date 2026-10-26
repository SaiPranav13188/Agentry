import Foundation
import SwiftData

/// Keeps the job list in sync with job emails. Plain Swift, no AI.
final class JobTracker {
    enum Change: Equatable {
        case added(JobStage)
        case moved(from: JobStage, to: JobStage)
        case unchanged
    }

    /// Add or update the application for company + role. Never creates duplicates.
    @discardableResult
    func record(company: String, role: String, stage: JobStage, subject: String, at date: Date = .now, in context: ModelContext) -> (JobApplication, Change) {
        let all = (try? context.fetch(FetchDescriptor<JobApplication>())) ?? []
        let key = Self.normalize(company)
        let roleKey = Self.normalize(role)

        let existing = all.first { app in
            Self.normalize(app.company) == key &&
                (roleKey.isEmpty || Self.normalize(app.role).isEmpty || Self.normalize(app.role) == roleKey)
        }

        if let app = existing {
            if app.role.isEmpty, !role.isEmpty { app.role = role }
            let old = app.stage
            guard Self.shouldMove(from: old, to: stage) else { return (app, .unchanged) }
            app.stage = stage
            app.lastUpdate = date
            app.lastEmailSubject = subject
            return (app, .moved(from: old, to: stage))
        }

        let app = JobApplication(company: company.isEmpty ? "Unknown company" : company, role: role, stage: stage, lastUpdate: date, lastEmailSubject: subject)
        context.insert(app)
        return (app, .added(stage))
    }

    /// Stages only move forward, except rejected/offer which always apply.
    nonisolated static func shouldMove(from old: JobStage, to new: JobStage) -> Bool {
        if old == new { return false }
        if new == .rejected || new == .offer { return true }
        if old == .rejected || old == .offer { return false }
        return new.order > old.order
    }

    nonisolated static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        for suffix in [" pvt ltd", " private limited", " ltd", " inc", " llc", " technologies", " careers", " recruiting", " talent", " hr", " team"] {
            t = t.replacingOccurrences(of: suffix, with: "")
        }
        return t.filter { $0.isLetter || $0.isNumber }
    }
}

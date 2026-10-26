import SwiftData
import SwiftUI

/// Application pipeline grouped by stage. Updates itself from job emails.
struct JobsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \JobApplication.lastUpdate, order: .reverse) private var jobs: [JobApplication]
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(title: "Jobs", subtitle: "Job emails move cards automatically. Right-click a card to fix it.") {
                Button {
                    showAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(SubtleButtonStyle())
            }
            stats
            if jobs.isEmpty {
                EmptyStateView(pet: .dog, mood: .idle, title: "No applications yet",
                               message: "When you get emails like “we received your application” or “interview invitation”, they show up here.",
                               actionTitle: "Add one manually", action: { showAdd = true })
            } else {
                board
            }
        }
        .padding(28)
        .sheet(isPresented: $showAdd) { AddJobSheet() }
    }

    private var stats: some View {
        let active = jobs.filter { $0.stage != .rejected && $0.stage != .offer }.count
        let interviews = jobs.filter { $0.stage == .interview || $0.stage == .offer }.count
        let rate = jobs.isEmpty ? 0 : Int((Double(interviews) / Double(jobs.count) * 100).rounded())
        return HStack(spacing: 14) {
            MiniStat(title: "Applications", value: jobs.count, color: .blue)
            MiniStat(title: "Active", value: active, color: .purple)
            MiniStat(title: "Interviews", value: interviews, color: .orange)
            MiniStat(title: "Offers", value: jobs.filter { $0.stage == .offer }.count, color: .green)
            MiniStat(title: "Interview rate", value: rate, color: .teal, suffix: "%")
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(JobStage.allCases) { stage in
                    let items = jobs.filter { $0.stage == stage }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: stage.symbol).foregroundStyle(stage.color)
                            Text(stage.title).font(.system(size: 13, weight: .bold))
                            Text("\(items.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        Capsule().fill(stage.color.opacity(0.6)).frame(height: 3)

                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(items) { job in
                                    JobCard(job: job)
                                        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                                }
                            }
                            .padding(2)
                        }
                    }
                    .padding(12)
                    .frame(width: 240)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(stage.color.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                }
            }
            .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: jobs.map(\.stageRaw))
        }
    }
}

private struct MiniStat: View {
    let title: String
    let value: Int
    let color: Color
    var suffix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                CountUpText(value: value, font: .system(size: 22, weight: .bold, design: .rounded))
                if !suffix.isEmpty { Text(suffix).font(.system(size: 16, weight: .bold, design: .rounded)) }
            }
            .foregroundStyle(color)
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}

private struct JobCard: View {
    @Environment(AppState.self) private var app
    let job: JobApplication
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(Theme.initials(job.company))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.avatarColor(for: job.company)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(job.company).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(job.role.isEmpty ? "Role not mentioned" : job.role)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !job.lastEmailSubject.isEmpty {
                Text("“\(job.lastEmailSubject)”")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(i <= job.stage.order ? job.stage.color : Color.primary.opacity(0.1))
                        .frame(height: 4)
                }
            }
            Text("Updated \(job.lastUpdate.formatted(.relative(presentation: .named)))")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardBackground).shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 8 : 3, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        .scaleEffect(hovering ? 1.02 : 1)
        .onHover { h in withMotion(Motion.quick) { hovering = h } }
        .contextMenu {
            Menu("Move to") {
                ForEach(JobStage.allCases) { stage in
                    Button(stage.title) {
                        withMotion {
                            job.stage = stage
                            job.lastUpdate = .now
                        }
                        app.log("Moved \(job.company) to \(stage.title)", "Manual change", kind: .job)
                        app.save()
                        if stage == .offer { app.achievements.record(.jobOffer(company: job.company)) }
                        if stage == .interview { app.achievements.record(.jobInterview(company: job.company)) }
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                withMotion { app.context.delete(job) }
                app.save()
            }
        }
    }
}

private struct AddJobSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var company = ""
    @State private var role = ""
    @State private var stage: JobStage = .applied

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add application").font(.system(size: 18, weight: .bold, design: .rounded))
            Form {
                TextField("Company", text: $company)
                TextField("Role", text: $role)
                Picker("Stage", selection: $stage) {
                    ForEach(JobStage.allCases) { Text($0.title).tag($0) }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    app.jobs.record(company: company, role: role, stage: stage, subject: "", in: app.context)
                    app.log("Added job application: \(company)", role, kind: .job)
                    app.save()
                    dismiss()
                }
                .buttonStyle(BrandButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(company.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

import SwiftData
import SwiftUI

/// Log of everything Agentry did.
struct ActivityView: View {
    @Query(Self.descriptor) private var entries: [ActivityEntry]
    @State private var search = ""

    private static var descriptor: FetchDescriptor<ActivityEntry> {
        var d = FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 600
        return d
    }

    private var grouped: [(day: Date, items: [ActivityEntry])] {
        let q = search.lowercased()
        let filtered = q.isEmpty ? entries : entries.filter { $0.event.lowercased().contains(q) || $0.details.lowercased().contains(q) }
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Activity", subtitle: "Everything Agentry did, newest first.") {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filter", text: $search).textFieldStyle(.plain).frame(width: 160)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }

                if entries.isEmpty {
                    EmptyStateView(pet: .cat, mood: .sleep, title: "Quiet so far", message: "Fetches, labels, drafts and sends will be logged here.")
                        .frame(height: 340)
                }

                ForEach(grouped, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(dayTitle(group.day).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 10)
                        ForEach(Array(group.items.enumerated()), id: \.element.persistentModelID) { index, entry in
                            ActivityRow(entry: entry, isLast: index == group.items.count - 1)
                        }
                    }
                    .card()
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(entry.kind.color.opacity(0.15))
                    Image(systemName: entry.kind.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.kind.color)
                }
                .frame(width: 24, height: 24)
                if !isLast {
                    Rectangle().fill(Theme.hairline).frame(width: 1.5).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.event).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if !entry.details.isEmpty {
                    Text(entry.details)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }
}

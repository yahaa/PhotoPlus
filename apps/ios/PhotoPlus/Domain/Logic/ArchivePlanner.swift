import Foundation

/// Decides what the rolling archive may upload and what may leave the phone.
enum ArchivePlanner {
    static func cutoff(now: Date, retentionMonths: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -retentionMonths, to: now) ?? now
    }

    /// Photos older than the retention window with no NAS copy yet.
    /// Videos and bursts are not archived in the MVP, so they simply stay on the phone.
    static func uploadCandidates(in items: [PhotoItem], cutoff: Date) -> [PhotoItem] {
        items.filter { item in
            item.storage == .localOnly && item.takenAt < cutoff && isArchivable(item)
        }
    }

    /// Local copies safe to remove: older than the window and fully on the NAS.
    /// A Live Photo also needs its motion resource there, or removal would lose the motion.
    static func freeableItems(in items: [PhotoItem], cutoff: Date) -> [PhotoItem] {
        items.filter { item in
            guard item.storage == .both, item.takenAt < cutoff, isArchivable(item), let remote = item.remote else {
                return false
            }
            return item.kind != .livePhoto || remote.motionSize > 0
        }
    }

    /// Items older than the window that the MVP will leave on the phone.
    static func skippedCount(in items: [PhotoItem], cutoff: Date) -> Int {
        items.filter { $0.localAssetID != nil && $0.takenAt < cutoff && !isArchivable($0) }.count
    }

    private static func isArchivable(_ item: PhotoItem) -> Bool {
        item.kind != .video && !item.isBurst
    }
}

/// Groups the timeline into the Years and Months views.
struct TimelineGroup: Identifiable, Hashable {
    let id: String
    let date: Date
    let items: [PhotoItem]
}

enum TimelineGrouper {
    static func groups(_ items: [PhotoItem], by components: Set<Calendar.Component>, calendar: Calendar = .current) -> [TimelineGroup] {
        let grouped = Dictionary(grouping: items) { calendar.dateComponents(components, from: $0.takenAt) }
        return grouped.compactMap { key, members -> TimelineGroup? in
            guard let date = calendar.date(from: key) else { return nil }
            return TimelineGroup(id: "\(key.year ?? 0)-\(key.month ?? 0)", date: date, items: members)
        }
        .sorted { $0.date < $1.date }
    }
}

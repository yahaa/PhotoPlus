import Foundation

enum PhotoFormat {
    static func year(_ date: Date) -> String {
        date.formatted(.dateTime.year().locale(Locale(identifier: "zh_CN")))
    }

    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).day().locale(Locale(identifier: "zh_CN")))
    }

    /// "2025年7月8日 星期二 16:00", the first line of the info panel.
    static func full(_ date: Date) -> String {
        "\(day(date)) \(date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))) \(time(date))"
    }

    /// "5日", the label inside a Months card.
    static func dayOfMonth(_ date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))日"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "12 张照片、3 个视频", the line under the title when the grid rests on the newest photo.
    static func summary(_ items: [PhotoItem]) -> String {
        let videos = items.filter { $0.kind == .video }.count
        let photos = items.count - videos
        var parts: [String] = []
        if photos > 0 { parts.append("\(photos) 张照片") }
        if videos > 0 { parts.append("\(videos) 个视频") }
        return parts.isEmpty ? "没有项目" : parts.joined(separator: "、")
    }
}

import Foundation

/// Grid sizes, sparsest first. The single column shows photos at their own aspect ratio.
enum GridDensity: Int, CaseIterable {
    case single = 1
    case three = 3
    case five = 5
    case nine = 9

    var pixelSize: CGFloat {
        switch self {
        case .single: 1200
        case .three: 400
        case .five: 240
        case .nine: 140
        }
    }

    /// Pinching in shows more photos.
    var denser: GridDensity { Self.allCases.first { $0.rawValue > rawValue } ?? self }
    var sparser: GridDensity { Self.allCases.last { $0.rawValue < rawValue } ?? self }
}

/// The filters in the sort and filter menu.
enum LibraryFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case favorites
    case photos
    case videos
    case screenshots
    case nasOnly
    case phoneOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "所有项目"
        case .favorites: "个人收藏"
        case .photos: "照片"
        case .videos: "视频"
        case .screenshots: "截屏"
        case .nasOnly: "仅在 NAS"
        case .phoneOnly: "尚未归档"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.3x3"
        case .favorites: "heart"
        case .photos: "photo"
        case .videos: "video"
        case .screenshots: "camera.viewfinder"
        case .nasOnly: "externaldrive.connected.to.line.below"
        case .phoneOnly: "iphone"
        }
    }

    func matches(_ item: PhotoItem) -> Bool {
        switch self {
        case .all: true
        case .favorites: item.isFavorite
        case .photos: item.kind != .video
        case .videos: item.kind == .video
        case .screenshots: item.isScreenshot
        case .nasOnly: item.storage == .nasOnly
        case .phoneOnly: item.storage == .localOnly
        }
    }
}

/// Text search over what PhotoKit and the NAS expose publicly: dates, filenames and media types.
/// Photos' semantic search (people, objects, places) has no public API.
enum LibrarySearch {
    static func filter(_ items: [PhotoItem], query: String, calendar: Calendar = .current) -> [PhotoItem] {
        let tokens = tokens(of: query)
        guard !tokens.isEmpty else { return [] }
        return items.filter { item in tokens.allSatisfy { matches(item, token: $0, calendar: calendar) } }
    }

    static func tokens(of query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func matches(_ item: PhotoItem, token: String, calendar: Calendar) -> Bool {
        if dateWords(item.takenAt, calendar: calendar).contains(token) { return true }
        if typeWords(item).contains(where: { $0.contains(token) }) { return true }
        return item.remote?.filename.lowercased().contains(token) ?? false
    }

    private static func dateWords(_ date: Date, calendar: Calendar) -> Set<String> {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let (year, month, day) = (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return [
            "\(year)", "\(year)年", "\(month)月", "\(day)日",
            "\(year)年\(month)月", "\(month)月\(day)日", "\(year)年\(month)月\(day)日",
            String(format: "%d-%02d", year, month), String(format: "%d-%02d-%02d", year, month, day)
        ]
    }

    private static func typeWords(_ item: PhotoItem) -> [String] {
        var words = [item.kind == .video ? "视频" : "照片"]
        if item.kind == .livePhoto { words.append("实况") }
        if item.isFavorite { words.append("个人收藏") }
        if item.isScreenshot { words.append("截屏") }
        if item.storage == .nasOnly { words.append("nas") }
        return words
    }
}

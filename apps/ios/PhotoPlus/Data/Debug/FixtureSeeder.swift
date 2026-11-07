#if DEBUG
import Photos
import UIKit

/// Test-only: creates generated images in a dedicated album, so UI tests exercise real
/// PhotoKit paths without reading or changing anyone's photos. Driven by environment:
///   PHOTOPLUS_FIXTURE_ALBUM    album title; confines PhotoKitStore to that album
///   PHOTOPLUS_FIXTURE_COUNT    how many images to create if the album doesn't exist
///   PHOTOPLUS_FIXTURE_CLEANUP  "1" deletes the album and its remaining assets instead
enum FixtureSeeder {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static func seedIfRequested(photoKit: PhotoKitStore) async {
        guard let title = photoKit.fixtureAlbumTitle else { return }
        // Fixtures render the same bytes every run, so their hashes repeat. A cached original would let
        // a test pass without the NAS ever being asked for it.
        ImageCache.shared.trimOriginals(limit: 0)
        if environment["PHOTOPLUS_FIXTURE_CLEANUP"] == "1" {
            await cleanup(title: title, photoKit: photoKit)
            return
        }
        guard photoKit.fixtureAlbum(titled: title) == nil,
              let count = environment["PHOTOPLUS_FIXTURE_COUNT"].flatMap(Int.init), count > 0 else {
            return
        }
        let photos = (0..<count).map { index in (date: date(index: index, count: count), data: render(index: index, count: count)) }
        try? await PHPhotoLibrary.shared().performChanges {
            let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            var placeholders: [PHObjectPlaceholder] = []
            for photo in photos {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: photo.data, options: nil)
                request.creationDate = photo.date
                if let placeholder = request.placeholderForCreatedAsset { placeholders.append(placeholder) }
            }
            album.addAssets(placeholders as NSArray)
        }
    }

    private static func cleanup(title: String, photoKit: PhotoKitStore) async {
        guard let album = photoKit.fixtureAlbum(titled: title) else { return }
        let assets = PHAsset.fetchAssets(in: album, options: nil)
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }
    }

    /// The newest quarter falls inside any retention window; the rest spreads over three years.
    private static func date(index: Int, count: Int) -> Date {
        let oldCount = max(count - max(count / 4, 1), 1)
        let calendar = Calendar.current
        if index >= oldCount {
            return calendar.date(byAdding: .day, value: -(count - index), to: Date()) ?? Date()
        }
        let monthsAgo = 36 - (index * 30 / oldCount)
        let base = calendar.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return calendar.date(byAdding: .hour, value: index, to: base) ?? base
    }

    private static func render(index: Int, count: Int) -> Data {
        let size = CGSize(width: 1200, height: index % 5 == 0 ? 1600 : 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let hue = CGFloat(index) / CGFloat(max(count, 1))
            let colors = [
                UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor,
                UIColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.55, alpha: 1).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let label = "FIXTURE \(index + 1)" as NSString
            label.draw(at: CGPoint(x: 60, y: size.height - 150), withAttributes: [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ])
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }
}
#endif

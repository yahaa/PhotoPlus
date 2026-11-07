import ImageIO
import MapKit
import SwiftUI

/// The panel a swipe up reveals under the photo: date, file and camera, plus where PhotoPlus keeps it.
struct PhotoInfoPanel: View {
    @EnvironmentObject private var store: LibraryStore
    let item: PhotoItem
    let onPullDown: () -> Void

    @State private var details = PhotoDetails()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(PhotoFormat.full(item.takenAt)).font(.subheadline.weight(.medium))
                    if let filename = details.filename {
                        Text(filename).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("info-filename")
                    }
                }
                cameraCard
                if let coordinate {
                    let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000)
                    Map(initialPosition: .region(region), interactionModes: []) {
                        Marker("", coordinate: coordinate)
                    }
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                storageCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 90)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < -50 } action: { _, pulled in
            if pulled { onPullDown() }
        }
        .task(id: item.id) { await load() }
        .accessibilityIdentifier("info-panel")
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = details.metadata.latitude, let longitude = details.metadata.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(details.metadata.cameraModel ?? "未知相机").font(.footnote.weight(.semibold))
                Spacer()
                if let format = details.filename.flatMap(PhotoMetadata.formatLabel) {
                    Text(format)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray3), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(10)
            .background(Color(.systemGray5))
            VStack(alignment: .leading, spacing: 3) {
                Text(details.metadata.lensModel ?? "无镜头信息")
                Text(sizeLine)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(10)
            Divider()
            HStack(spacing: 0) {
                ForEach(Array(details.metadata.exposureColumns.enumerated()), id: \.offset) { index, value in
                    if index > 0 { Divider().frame(height: 14) }
                    Text(value).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("info-camera")
    }

    private var sizeLine: String {
        let megapixels = Double(item.width * item.height) / 1_000_000
        var parts = ["\(max(Int(megapixels.rounded()), 1)) MP", "\(item.width) × \(item.height)"]
        if let size = details.sizeBytes ?? item.remote?.sizeBytes { parts.append(PhotoFormat.bytes(size)) }
        return parts.joined(separator: " · ")
    }

    private var storageCard: some View {
        VStack(spacing: 8) {
            LabeledContent("存储位置", value: storageText)
            if let remote = item.remote {
                Divider()
                LabeledContent("安全等级", value: remote.tier.title)
            }
        }
        .font(.footnote)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("info-storage")
    }

    private var storageText: String {
        switch item.storage {
        case .localOnly: "仅手机"
        case .both: "手机和 NAS"
        case .nasOnly: "仅 NAS"
        }
    }

    private func load() async {
        details = PhotoDetails(filename: item.remote?.filename, sizeBytes: item.remote?.sizeBytes)
        do {
            if let assetID = item.localAssetID {
                details.filename = store.photoKit.originalFilename(assetID: assetID) ?? details.filename
                guard item.kind != .video else { return }
                let data = try await store.photoKit.imageData(assetID: assetID)
                details.sizeBytes = Int64(data.count)
                details.metadata = await Task.detached { Self.metadata(of: CGImageSourceCreateWithData(data as CFData, nil)) }.value
            } else if let id = item.remote?.id {
                let file = try await ImageCache.shared.originalFile(id: id, api: store.settings.apiClient)
                details.metadata = await Task.detached { Self.metadata(of: CGImageSourceCreateWithURL(file as CFURL, nil)) }.value
            }
        } catch {
            // The panel still shows what the timeline already knows.
        }
    }

    nonisolated private static func metadata(of source: CGImageSource?) -> PhotoMetadata {
        guard let source, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return PhotoMetadata()
        }
        return PhotoMetadata(properties: properties)
    }
}

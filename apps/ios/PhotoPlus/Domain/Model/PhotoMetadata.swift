import Foundation
import ImageIO

/// What the info panel shows from a photo's EXIF, TIFF and GPS dictionaries.
struct PhotoMetadata: Equatable {
    var cameraModel: String?
    var lensModel: String?
    var iso: Int?
    var focalLength: Double?
    var exposureBias: Double?
    var aperture: Double?
    var exposureTime: Double?
    var latitude: Double?
    var longitude: Double?

    init() {}

    init(properties: [CFString: Any]) {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        lensModel = exif[kCGImagePropertyExifLensModel] as? String
        iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        exposureBias = exif[kCGImagePropertyExifExposureBiasValue] as? Double
        aperture = exif[kCGImagePropertyExifFNumber] as? Double
        exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        if let value = gps[kCGImagePropertyGPSLatitude] as? Double {
            latitude = gps[kCGImagePropertyGPSLatitudeRef] as? String == "S" ? -value : value
        }
        if let value = gps[kCGImagePropertyGPSLongitude] as? Double {
            longitude = gps[kCGImagePropertyGPSLongitudeRef] as? String == "W" ? -value : value
        }
    }

    /// The five columns under the camera card; "-" where the photo doesn't say.
    var exposureColumns: [String] {
        [
            iso.map { "ISO \($0)" } ?? "-",
            focalLength.map { "\(Self.compact($0)) mm" } ?? "-",
            exposureBias.map { "\(Self.compact($0)) ev" } ?? "-",
            aperture.map { "ƒ\(Self.compact($0))" } ?? "-",
            exposureTime.map(Self.shutter) ?? "-"
        ]
    }

    /// "HEIF" for IMG_1.HEIC, the label Photos puts on the camera card.
    static func formatLabel(filename: String) -> String? {
        let suffix = (filename as NSString).pathExtension.uppercased()
        switch suffix {
        case "": return nil
        case "HEIC": return "HEIF"
        case "JPG": return "JPEG"
        default: return suffix
        }
    }

    static func shutter(_ seconds: Double) -> String {
        guard seconds > 0 else { return "-" }
        return seconds >= 1 ? "\(compact(seconds)) s" : "1/\(Int((1 / seconds).rounded())) s"
    }

    private static func compact(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// The header of the info panel, read on demand because it needs the image data.
struct PhotoDetails: Equatable {
    var filename: String?
    var sizeBytes: Int64?
    var metadata = PhotoMetadata()
}

import ImageIO
import XCTest
@testable import PhotoPlus

final class PhotoMetadataTests: XCTestCase {
    func testReadsCameraExposureAndSignedGPS() {
        let metadata = PhotoMetadata(properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone 13"],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "Main",
                kCGImagePropertyExifISOSpeedRatings: [64],
                kCGImagePropertyExifFocalLength: 5.1,
                kCGImagePropertyExifExposureBiasValue: 0.0,
                kCGImagePropertyExifFNumber: 1.6,
                kCGImagePropertyExifExposureTime: 1.0 / 120
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.5,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 122.25,
                kCGImagePropertyGPSLongitudeRef: "W"
            ]
        ])
        XCTAssertEqual(metadata.cameraModel, "iPhone 13")
        XCTAssertEqual(metadata.lensModel, "Main")
        XCTAssertEqual(metadata.exposureColumns, ["ISO 64", "5.1 mm", "0 ev", "ƒ1.6", "1/120 s"])
        XCTAssertEqual(metadata.latitude, -37.5)
        XCTAssertEqual(metadata.longitude, -122.25)
    }

    func testMissingValuesShowDashes() {
        let metadata = PhotoMetadata(properties: [:])
        XCTAssertEqual(metadata.exposureColumns, ["-", "-", "-", "-", "-"])
        XCTAssertNil(metadata.latitude)
    }

    func testFormatLabelsAndShutter() {
        XCTAssertEqual(PhotoMetadata.formatLabel(filename: "IMG_1.HEIC"), "HEIF")
        XCTAssertEqual(PhotoMetadata.formatLabel(filename: "a.jpg"), "JPEG")
        XCTAssertEqual(PhotoMetadata.formatLabel(filename: "a.png"), "PNG")
        XCTAssertNil(PhotoMetadata.formatLabel(filename: "noextension"))
        XCTAssertEqual(PhotoMetadata.shutter(2), "2 s")
        XCTAssertEqual(PhotoMetadata.shutter(0.5), "1/2 s")
    }
}

# apps/ios

Swift + SwiftUI client for PhotoPlus (`com.yahaa.photoplus`).

## Layout

- `PhotoPlus/UI/` — Timeline, Settings, Devices, upload-queue placeholders
- `PhotoPlus/Data/` — `ApiClient` (NAS Go API) and `PhotoKitStore` stubs
- `PhotoPlus/Domain/` — models + repository stubs
- `PhotoPlus.xcodeproj` — hand-written Xcode project (open this)
- `project.yml` — optional [XcodeGen](https://github.com/yonaskolb/XcodeGen) recipe if you need to regenerate the project

## Open / build

1. On a Mac with Xcode 16+ (iOS 17 SDK).
2. Open `PhotoPlus.xcodeproj` (File → Open).
3. Select an iPhone simulator or device; set your Development Team for signing.
4. Product → Run.

CLI (Mac only):

```bash
xcodebuild -project PhotoPlus.xcodeproj -scheme PhotoPlus -destination 'platform=iOS Simulator,name=iPhone 16' build
```

This Linux box cannot build iOS; the project is meant to open and build under Xcode.

## Notes

- `NSPhotoLibraryUsageDescription` is set for PhotoKit / rolling archive.
- Pair with `apps/android` (Kotlin Compose) — dual native codebases for Photos/MediaStore depth.

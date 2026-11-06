# apps/android

Kotlin + Jetpack Compose client for PhotoPlus (`com.yahaa.photoplus`).

## Layout

- `ui/` — Timeline, Settings, Devices, upload-queue placeholders; albums stub
- `data/` — `ApiClient` (NAS Go API) and `LocalMediaStore` stubs
- `domain/` — models + repository stubs

## Open / build

1. Install Android Studio Ladybug+ (or compatible) with Android SDK 35 and JDK 17.
2. **File → Open** this `apps/android` directory (not the monorepo root).
3. Let Gradle sync; first sync downloads the wrapper distribution if needed.
4. Run the `app` configuration on an emulator or device.

Debug APK (after SDK + wrapper are ready):

```bash
./gradlew :app:assembleDebug
# output: app/build/outputs/apk/debug/app-debug.apk
```

This Linux CI/box may lack an Android SDK; the project is structured to open and build on a machine that has one. If `gradle-wrapper.jar` is missing, Android Studio creates it on first open, or run `gradle wrapper` with a local Gradle 8.9+.

## Notes

- MediaStore / rolling-archive permissions are declared; runtime requests come later.
- Pair with `apps/ios` (SwiftUI) — dual native codebases for Photos/MediaStore depth.

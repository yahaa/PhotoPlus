# apps/ios

Swift + SwiftUI client for PhotoPlus (`com.yahaa.photoplus`). Library, Collections and the viewer follow Apple's Photos; Settings is PhotoPlus's own addition.

## Layout

- `PhotoPlus/UI/` — Library (Years / Months / All), Viewer, Collections, Settings
- `PhotoPlus/Domain/` — models, timeline merging, archive rules
- `PhotoPlus/Data/` — NAS `ApiClient`, PhotoKit access, caches, settings
- `PhotoPlus/Archive/` — the foreground rolling archive
- `PhotoPlus/Data/Debug/` — Debug-only generated fixtures for tests
- `project.yml` — source of truth for the Xcode project (`xcodegen generate` after adding or removing files)

## Build and run

On a Mac with Xcode 26: open `PhotoPlus.xcodeproj`, select a simulator or device, set your Development Team, and run. Then enter the NAS address and token under Settings. See the root `CLAUDE.md` for command-line builds and tests.

## Current limits

- Uploads run only while the app is in the foreground.
- Videos, bursts and edited photos are not archived and stay on the phone.
- Live Photos are archived with their motion, but play back only while on the phone.
- There is no search tab yet.

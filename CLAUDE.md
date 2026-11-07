# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repository is public. Machine-specific details (hosts, device IDs, signing team) belong in the untracked `CLAUDE.local.md`.

## Project state

PhotoPlus is a private cloud photo album for home NAS hardware. `docs/ARCHITECTURE.md` describes the target system; only part of it exists:

- **Built (single-user MVP):** the Go API (upload, list, download, delete, stats, one bearer token) and the iOS client (Library, Collections, Search, viewer, Settings, foreground rolling archive).
- **Scaffold only:** the Android client (placeholder screens, empty repository and `ApiClient`), `deploy/scripts/*` and `storage/scripts/init-volumes.sh` (they only echo a placeholder).
- **Not started:** accounts, family roles, QR pairing, Headscale, storage health, disk orchestration, background upload.

Check the code before treating an architecture statement as implemented. No CI or Makefiles exist.

## Commands

Each component is built from its own directory; there is no root build.

### Server (`server/`, Go 1.22, chi, SQLite)

```bash
go build ./...
go vet ./...
gofmt -l .                                # no linter is configured
go test ./...
go test ./internal/api -run TestName      # single test
PHOTOPLUS_TOKEN=... PHOTOPLUS_HTTP_ADDR=127.0.0.1:18800 go run ./cmd/server
```

`PHOTOPLUS_TOKEN` is required. Also read: `PHOTOPLUS_HTTP_ADDR` (default `:8080`), `PHOTOPLUS_DB_PATH`, `PHOTOPLUS_FILER_URL` (default `http://127.0.0.1:8888`). API tests use an in-memory store, so check filer behaviour against real SeaweedFS too.

### Storage (`storage/`)

```bash
docker compose up -d      # SeaweedFS master 127.0.0.1:9333, filer 127.0.0.1:8888, volume on the compose network only
```

The filer has no auth, so never publish it beyond loopback; only the Go API talks to it.

### iOS (`apps/ios/`, Xcode 26, iOS 18 deployment target)

Lint runs anywhere SwiftLint is installed; building and testing need a Mac.

```bash
swiftlint lint --strict --quiet     # zero warnings; only macOS builds of SwiftLint run the SourceKit rules
xcodegen generate                   # after adding or removing files; commit PhotoPlus.xcodeproj
xcodebuild -project PhotoPlus.xcodeproj -scheme PhotoPlus -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
xcodebuild ... -only-testing:PhotoPlusTests/ArchivePlannerTests/testFreesOldPhotoWithNASCopy test   # single test
```

`project.yml` is the source of truth for the Xcode project. `ScreenshotTourUITests` walks every screen against the behaviour measured in Apple's Photos and only runs with `TEST_RUNNER_PHOTOPLUS_SCREENSHOT_DIR` set. UI tests need `TEST_RUNNER_PHOTOPLUS_SERVER_URL` and `TEST_RUNNER_PHOTOPLUS_TOKEN`, and expect an empty NAS: leftover NAS photos change the cell counts they assert.

**Never touch real photos in device tests.** `PHOTOPLUS_FIXTURE_ALBUM` (Debug only) confines `PhotoKitStore` to a generated album; `ArchiveFlowUITests` always sets it. `TEST_RUNNER_PHOTOPLUS_TOUR_UNCONFINED` is for simulators only.

### Android (`apps/android/`, Gradle 8.9, AGP 8.7, Kotlin 2.0, JDK 17, SDK 35, minSdk 26)

```bash
./gradlew :app:assembleDebug
./gradlew lint
./gradlew :app:testDebugUnitTest
./gradlew :app:testDebugUnitTest --tests 'com.yahaa.photoplus.SomeTest'   # single test
```

`gradle-wrapper.jar` is not committed (`gradlew` is a custom script that exits 1 without it). Generate it with `gradle wrapper` (Gradle 8.9+) or by opening `apps/android` (not the monorepo root) in Android Studio. No `testImplementation` dependencies are declared yet, so unit tests need those added first.

## Architecture

```
Phone (iOS / Android) ──Headscale network──> Go API on the NAS ──> SeaweedFS (master + volume + filer)
```

The phone keeps recent originals and is only a cache beyond that. Older originals upload to the NAS and can then leave the phone, leaving a cached thumbnail; opening one fetches the original from the NAS. The NAS is therefore the source of truth: a new phone rebuilds its timeline from it, and anything still queued on the old phone is lost if it hasn't finished uploading.

Decisions that shape the code across components:

- **Two native clients on purpose.** Android and iOS are separate codebases for deep MediaStore and PhotoKit integration (the repo moved off Flutter), so don't propose a shared UI layer. Both use the same `ui` / `data` / `domain` layering and the bundle ID `com.yahaa.photoplus`.
- **A photo's id is the SHA-256 of its original.** The server recomputes it while streaming to the filer, so a corrupted upload can't commit.
- **A database row means the whole photo is durable.** Clients send thumbnail and motion first; the original's PUT goes last, and the server checks every object is stored before inserting the row. A committed photo is never overwritten. This ordering is what makes it safe for a client to remove its local copy, so preserve it.
- **The client generates thumbnails.** Go has no pure-Go HEIC decoder, and the phone can already render them. PhotoKit keeps nothing after a delete, so NAS-only items show thumbnails cached from the NAS.
- **No client-side upload queue.** `TimelineMerger` pairs NAS rows with local assets through `sourceLocalId`, so PhotoKit plus the NAS listing already say what is left, and a rescan resumes.
- **Removing local copies is guarded.** It is only ever user-initiated, re-fetches the NAS list first (`fetchRemoteStrict`, never the cached index), and goes through iOS's own confirmation. `ArchivePlanner` holds the eligibility rules. Videos, bursts and edited photos stay on the phone for now, because the server can't yet hold all their resources; a Live Photo needs its motion resource on the NAS first.
- **Safety tier maps to a SeaweedFS collection**, not a per-object setting. Replication is set per volume, so changing a policy means a migration such as `volume.fix.replication`, not an instant rewrite. Today's single volume has no redundancy whichever tier is chosen, and the Settings text says so.
- **Plain HTTP is allowed for now.** `NSAllowsArbitraryLoads` is on because users enter arbitrary LAN or tailnet IPs and ATS exceptions can't cover IP ranges. Tailnet traffic is encrypted by WireGuard, but on a plain LAN the bearer token is not. Replace this with TLS before any release.
- **Erasure coding is fixed at RS(10+4)** in open-source SeaweedFS; custom ratios are Enterprise-only. On a 1–8 bay box, shard placement must be disk-aware. See `docs/OBJECT_STORAGE_COMPARISON.md` for the storage comparison.
- **Filer metadata needs its own backup**, since volume disks alone cannot restore the object index.
- **Multi-tenancy lives in the network layer:** one Headscale user per customer isolates namespaces. Within a box, the first device to scan-bind becomes admin and invites family as read-only or read-write.
- **The iOS bottom bar is custom, not `TabView`'s.** Photos' bar changes shape on rules `TabView` can't express: it collapses only away from the newest photo and stays collapsed in Years and Months, and there's no API to minimize it programmatically. `BottomBarModel` holds those rules.
- **Admin UI is out of scope for the clients.** Phone settings cover the NAS connection, retention, storage status and safety tier; admin comes later as a web app.

`docs/ARCHITECTURE.md` also lists the open risks to validate, such as background upload limits and EC behaviour on few disks.

# PhotoPlus Architecture

Private cloud album: phone keeps recent originals locally; older photos archive to home NAS. Clients talk to a Go API on the box; objects live in SeaweedFS; devices reach each other via Headscale (Tailscale control plane).

## 1. Client (`apps/ios` + `apps/android`)

- Dual native clients: **Swift + SwiftUI** on iOS (`apps/ios`) and **Kotlin + Jetpack Compose** on Android (`apps/android`). Intentional dual codebase for deep Photos (PhotoKit) / MediaStore integration rather than a shared Flutter UI.
- UI mirrors the iOS Photos app: timeline, albums, search.
- Rolling archive: user sets a retention window (e.g. 6 months); older originals upload to NAS, then leave the phone.
- Local placeholders: PhotoKit / MediaStore thumbnail + metadata stay; open a photo → fetch original from NAS.
- Upload queue with iCloud-like progress affordance.
- EXIF preserved on upload.
- Multi-device login under one account.

### Device switch

New phone: reinstall app, sign in to the same account → timeline loads from the NAS (local storage is only a cache). Photos still queued on the old phone must finish uploading before the switch, or they are lost.

### Settings

Phone settings only (no admin UI; admin comes later as Web):

- Rolling-archive retention: user picks e.g. 3 / 6 / 12 months; older originals upload to NAS then leave the phone.
- Storage status: local free space, NAS used, upload queue.
- Safety tier: casual / important → different SeaweedFS collections (replica count).
- Account & devices: list signed-in devices; remove a device.

## 2. API (`server`, Go)

NAS-side control plane.

- Schedule object I/O against SeaweedFS.
- Generate ~200px / tens-of-KB thumbnails.
- Index by EXIF time for timeline + search.
- Users: first device to scan-bind becomes admin; admin invites family with read-only or read-write.
- AuthZ on all album/object ops.
- Storage health: disk status, erasure-coding health.
- New-disk orchestration: udev detect → mount → refresh SeaweedFS volume config → apply without downtime.
- Route objects by safety tier into SeaweedFS collections (e.g. important RF=3, casual RF=2; user-selectable).

## 3. Storage (`storage`, SeaweedFS)

- Single-node distributed mode: master + volume + filer.
- One volume server per disk; add bays as needed (no hard disk-count cap).
- Hot data uses volume-level replication (placement codes like `001`/`002`); collections separate tiers (e.g. important vs casual), not per-object instant RF.
- Open-source EC for warm/sealed volumes is fixed RS(10+4); custom EC ratios are Enterprise-only. Shard placement must be disk-aware on a 1–8 bay box.
- **Back up filer metadata separately** — volume disks alone do not restore the object index.
- Disk lifecycle inspired by `yahaa/storage-plus`: plug → upsert mount; unplug → umount; `blkid` UUID as stable id.

## 4. Network (Headscale)

- Self-hosted Headscale on our cloud as the default control plane; all customer devices join it.
- One Headscale user per customer → isolated namespace; tenants cannot see each other.
- Managed mode: our Headscale. Self-managed mode: advanced users point the app at their own Headscale URL.
- For non-technical users, Headscale/Tailscale is factory-preinstalled and bound via QR; no config UI exposed.

## 5. Hardware (`deploy`)

- Custom Linux mini-PC + 1–8 drive bays; Thunderbolt / USB for expansion where needed.
- Factory image: Headscale client, SeaweedFS, Go API.
- Unbox flow: power on → scan QR in app → paired and usable.

## Risks to validate

- iOS / Android background upload and media-library permission limits (PhotoKit background, MediaStore scoped storage, OEM killers).
- Changing SeaweedFS RF / collection policy needs `volume.fix.replication` (or equivalent) migration, not an instant rewrite.
- Open-source 10+4 EC on ≤8 disks: verify shard-per-disk caps so two-disk loss stays within 4 parity shards.
- Filer metadata backup and restore drill.
- Headscale multi-tenant scale (users, nodes, coordination latency) under real customer load.

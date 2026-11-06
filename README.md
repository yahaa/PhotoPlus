# PhotoPlus

Private cloud photo album for home NAS hardware.

Monorepo layout:

| Path | Role |
|------|------|
| `apps/android` | Kotlin + Jetpack Compose client (Android) |
| `apps/ios` | Swift + SwiftUI client (iOS) |
| `server` | Go API on the NAS |
| `storage` | SeaweedFS deploy configs & scripts |
| `deploy` | Factory provisioning & install |
| `docs` | Design docs |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

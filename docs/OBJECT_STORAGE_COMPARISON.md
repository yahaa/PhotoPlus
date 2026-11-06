# Object storage comparison (PhotoPlus)

Scope: single-node NAS, 1–8 disks, photo/video blobs, commercial closed-source product. Not legal advice.

## 1. Primary: SeaweedFS

- License Apache-2.0; ~36k GitHub stars; active releases.
- Fits single-node multi-disk: one volume server per disk, or `weed mini`.
- Strong small-file write path (~431 ops/s sequential small uploads in a public r/selfhosted benchmark vs ~113 MinIO / ~376 Garage).
- Production mentions: ~100TB image load on 2× HDD; >100TB backup migration off MinIO.
- Default durability path includes erasure coding (we target 3 data + 2 parity).
- Drawbacks: docs are hard; maintainer concentration on chrislusf (low bus factor); **filer metadata must be backed up** or the index is gone.

## 2. Runner-up: RustFS

- License Apache-2.0; ~36k stars; MinIO-like S3 / pool model with erasure sets.
- Single-node multi-drive pools supported; docs suggest ~4GB RAM as a starting point.
- GA only in 2026 — fewer independent production write-ups; treat as parallel bake-off, not a drop-in yet.

## 3. Not recommended here

- **MinIO community**: repo archived ~2026-04; AGPL-3.0.
- **Garage**: AGPL-3.0; replication only (no EC); official single-node path is non-production.
- **Ceph RGW**: durable at scale, ops too heavy for a 1–8 bay appliance.
- **Apache Ozone**: multi-node / big-data oriented.
- **OpenIO**: open-source line effectively dormant after OVHcloud acquisition.

## 4. Decision for PhotoPlus

Ship on **SeaweedFS**. Keep **RustFS** as a backup candidate and re-evaluate after soak tests.

Ops checklist: back up filer metadata separately; rehearse power loss and disk failure; treat EC/RF policy changes as migrations; run a dependency license pass before closed-source release.

## Sources

- [seaweedfs/seaweedfs](https://github.com/seaweedfs/seaweedfs)
- [HN: SeaweedFS ~100TB / 56M images](https://news.ycombinator.com/item?id=46333399)
- [r/selfhosted: MinIO vs SeaweedFS vs Garage](https://www.reddit.com/r/selfhosted/comments/1ryfzw4/minio_vs_seaweedfs_vs_garage/)
- [rustfs/rustfs](https://github.com/rustfs/rustfs)
- [minio/minio](https://github.com/minio/minio) (archived, AGPL-3.0)

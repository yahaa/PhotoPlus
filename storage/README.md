# storage

SeaweedFS single-node (master + volume + filer). Run: `docker compose up -d` from this directory.

Host ports stay on loopback because the filer has no auth: master `127.0.0.1:9333`, filer `127.0.0.1:8888`. The volume server is reachable only on the compose network.

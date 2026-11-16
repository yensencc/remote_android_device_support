# Third-party components

All vendored code is **unchanged** from the commit listed (exported with `git archive`).
Each directory keeps its original `LICENSE` / `NOTICE`. All are Apache License 2.0.

| Directory | Component | Source | Commit | Notes |
| --- | --- | --- | --- | --- |
| `vendor/hmdm-docker` | Headwind MDM Docker image | https://github.com/h-mdm/hmdm-docker (official) | `25119d7` (2026-10-25, "Bump tomcat, certbot, Headwind MDM") | The deployment uses the published image `headwindmdm/hmdm:0.1.9`, built from this source; kept for reference and local builds |
| `vendor/headwind-remote-server` | Headwind Remote server (formerly aPuppet): web console, Janus image build, config templates | Originally `github.com/h-mdm/remote-control` (no longer public); preserved in Apache-2.0 forks, e.g. https://github.com/ZhiYiDai/remote-control | `212335a` (2022-01-02, "Product renaming", by Headwind's developer) | The last upstream commit. Later third-party changes (2024 forks) are deliberately **not** included |
| `vendor/headwind-remote-agent` | Headwind Remote Android agent v2.02 (`com.hmdm.control`) | Originally `github.com/h-mdm/remote-control-android` (no longer public); preserved in Apache-2.0 forks, e.g. https://github.com/huajiworld/remote-control-android | `73730d1` (2023-08-01, "Some string adjustments", by Headwind's developer) | The last upstream commit. The fork's later CI-only commits are excluded. `gradle/wrapper/gradle-wrapper.jar` matches Gradle's official 4.6 wrapper checksum |

## Modified copy

`agent/` is a copy of `vendor/headwind-remote-agent` with an MDM integration and fixes.
The changes are listed in [agent/README-LTS.md](agent/README-LTS.md), and every
modified file carries a notice, as Apache-2.0 section 4 requires. It depends on
`io.github.webrtc-sdk:android` 125.6422.07 (BSD-3-Clause, Maven Central), because
the original `org.webrtc:google-webrtc` artifact is no longer published.

## Container images

| Image | Version | Publisher |
| --- | --- | --- |
| `headwindmdm/hmdm` | `0.1.9` (Headwind MDM 5.41.1, client 6.40) | Headwind MDM, Docker Hub |
| `headwindmdm/janus-gateway` | `0.10.7` | Headwind MDM, Docker Hub; built from `vendor/headwind-remote-server/deploy/images/janus-gateway` |
| `postgres` | `15-alpine` | Docker official image (upstream hmdm-docker uses 12, which is end-of-life) |

## Derived files in this repo

- `remote/janus/*.tmpl` and `remote/janus/janus.plugin.textroom.jcfg`: Headwind
  Remote's Janus templates (`vendor/headwind-remote-server/deploy/templates/janus`),
  with the Ansible placeholders replaced. Janus's HTTP and WebSocket APIs bind to
  127.0.0.1, because nginx terminates TLS. Every change is listed in each file's header.
- `remote/web-admin/settings.js.tmpl`: based on the upstream `settings.js.j2`; points
  the console at `/janus-ws` and `/janus` through nginx.
- `scripts/build-web-admin.sh`: the same concatenation as the upstream `gulpfile.js`,
  without the Node toolchain.

Headwind MDM, Headwind Remote and aPuppet are products of Headwind Solutions LLC. This
repository is not affiliated with them.

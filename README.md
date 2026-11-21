# Remote Android device support

Self-hosted **device management** and **remote control** for Android devices:
registers, payment phones, tablets and TVs running the
[POS app](https://github.com/yensencc/react-native-pos-with-tab). It installs on one
small Linux server:

| Part | What it does | URL |
| --- | --- | --- |
| **[Headwind MDM](https://h-mdm.com)** (Community, open source) | Device list, push APK installs and updates, kiosk mode, per-app settings (configures the POS app remotely) | `https://mdm.<your-domain>` |
| **Headwind Remote** (formerly **aPuppet**, open source) | Live screen view and control of a device in the browser (WebRTC through Janus) | `https://remote.<your-domain>` |

## Contents

1. [How it fits together](#how-it-fits-together)
2. [Requirements](#requirements)
3. [Install](#install)
4. [After installing](#after-installing)
5. [Access and credentials](#access-and-credentials)
6. [Client devices: prerequisites and steps](#client-devices-prerequisites-and-steps)
7. [Enrolling devices](#enrolling-devices)
8. [Configuring the POS app from the MDM](#configuring-the-pos-app-from-the-mdm)
9. [Remote control sessions](#remote-control-sessions)
10. [Operations](#operations)
11. [Security](#security)
12. [Limits to know](#limits-to-know)
13. [Repository layout](#repository-layout)
14. [Troubleshooting](#troubleshooting)

## How it fits together

```
                 ┌──────────────────────────── server ───────────────────────────────┐
 Browser ─HTTPS─►│ nginx (host, Let's Encrypt)                                         │
                 │   mdm.<domain>    ──► hmdm (Tomcat, 127.0.0.1:8080) ──► PostgreSQL │
                 │   remote.<domain> ──► web console (basic auth)                      │
                 │                    ──► /janus, /janus-ws ──► Janus (127.0.0.1)      │
 Devices ─HTTPS─►│                                                                     │
         ─TCP───►│ 31000  MDM push (MQTT, authenticated)                               │
         ─UDP───►│ 20000-20039  screen video (RTP / WebRTC) ◄──► Janus                 │
                 └─────────────────────────────────────────────────────────────────────┘
```

- **Outbound only for devices.** Devices only make outbound connections to the server,
  so shops need no router changes.
- **Containers bind to loopback.** Every container port is on 127.0.0.1 except MDM push
  (31000/tcp) and the RTP range (UDP). nginx terminates all TLS.
- **Janus** is the WebRTC relay. It forwards the device's encoded video to the browser
  without re-encoding it, and carries taps back. It only works during remote sessions.

## Requirements

- **Server:** Ubuntu 22.04, 24.04 or 26.04, **x86-64** (the Headwind images are
  amd64-only).
- **Memory:** **1 GB RAM minimum** for a pilot (the installer adds 2 GB swap); **2 GB+**
  for real use.
- **Disk:** about 5 GB.
- **DNS:** two **A records** pointing at the server, for example `mdm.example.com` and
  `remote.example.com`.
- **Ports:** 22, 80, 443 and 31000 TCP, plus 20000–20039 UDP. The installer configures
  `ufw`; also allow these in your provider's firewall, if one is enabled.
- **SSH:** key access as root (or sudo).

## Install

```bash
# on the server
git clone https://github.com/yensencc/remote_android_device_support.git /opt/remote-support
cd /opt/remote-support
cp .env.example .env
nano .env            # set MDM_DOMAIN, REMOTE_DOMAIN, ADMIN_EMAIL
sudo ./install.sh
```

**What `install.sh` does** (safe to re-run; it keeps existing secrets and data):
1. Checks that both domains resolve to this server.
2. Generates every secret into `.env` (mode 600).
3. Installs Docker, nginx, certbot and ufw; adds swap if there is none; enables
   unattended security updates.
4. Opens only the ports listed above.
5. Gets Let's Encrypt certificates (webroot, auto-renewing).
6. Renders the Janus and nginx configs.
7. Builds the web console.
8. Starts PostgreSQL, Headwind MDM and Janus with memory limits.

**The first start downloads about 1 GB** and takes a few minutes. At the end it prints
the URLs.

## After installing

1. **MDM panel:** open `https://mdm.<domain>` and log in with **admin / admin**. Change
   the password **immediately**, and set your email in the profile.
2. **Remote console:** open `https://remote.<domain>`. Log in with `REMOTE_ADMIN_USER`
   and the `REMOTE_ADMIN_PASS` from `.env`.
3. **Back up `.env`** somewhere safe and encrypted. It holds every secret, and
   `scripts/backup.sh` includes it.
4. **Schedule backups:**
   `echo '15 3 * * * root /opt/remote-support/scripts/backup.sh' > /etc/cron.d/remote-support-backup`

## Access and credentials

**No secret values belong in this repo.** Keep the operator's copy in a password
manager or in `~/.config/remote-support/CREDENTIALS.md` (mode 600, outside Git). This
table says what exists and where it lives:

| Access | Login | Where the secret lives |
| --- | --- | --- |
| Server SSH | `root`, key only | Your SSH private key (password login disabled) |
| Server rescue console (provider web console) | `root` | Root password, set on first login; only works on the provider's console |
| MDM panel `https://mdm.<domain>` | `admin` (plus users you add) | Set in the panel; the first login is `admin/admin`, change it at once |
| Remote console `https://remote.<domain>` | `REMOTE_ADMIN_USER` (`support`) | `REMOTE_ADMIN_PASS` in `.env` |
| Agent *Server URL* / *Secret* | — | `https://remote.<domain>` / `JANUS_API_SECRET` in `.env` (enter it in the MDM's Application settings) |
| Database | `hmdm` | `SQL_PASS` in `.env` (loopback only) |
| MDM signing / push | — | `SHARED_SECRET` in `.env`: the stock agent's public value `changeme-C3z9vi54` (it must match the agent APK) |
| Janus admin API | — | `JANUS_ADMIN_SECRET` in `.env` (API disabled) |
| Agent release signing key | — | Off-repo keystore (see the [agent repo](https://github.com/yensencc/lts-remote-support-android#signing-release-builds)) |
| Let's Encrypt | `ADMIN_EMAIL` | Expiry notices only |

## Client devices: prerequisites and steps

**What each device needs:**

| Requirement | Detail |
| --- | --- |
| Android version | **7.0+**. On Android 14+, every remote session needs one on-screen tap ("Start now") |
| Network (outbound only) | HTTPS **443** to `mdm.<domain>` and `remote.<domain>`; TCP **31000** (MDM push); UDP **20000–20039** (screen video). No inbound ports or router changes |
| **Headwind MDM agent** | `https://mdm.<domain>/files/hmdm-<version>-os.apk`, or installed by QR enrollment |
| **Remote Support agent** | Pushed by the MDM (`com.lasttechsol.remotesupport`); source in [lts-remote-support-android](https://github.com/yensencc/lts-remote-support-android) |
| **POS app** | Pushed by the MDM (optional) |
| Permissions, once per device | Remote Support: **Accessibility** on (for remote taps; on Android 13+ you may first need App info → ⋮ → *Allow restricted settings*). Without device-owner enrollment, also allow **Install unknown apps** for Headwind MDM, and turn off battery optimization for it so push stays connected |
| Fire TV / Android TV | Can't be device owner: installs need a tap, and kiosk mode is limited |

**What the support person needs:** a desktop **Chrome, Edge or Firefox**, the MDM
login and the remote-console login. Nothing to install.

**Bringing a new device under support:**
1. **Pick a configuration.** In the MDM, choose the device's configuration (register,
   display and so on) and make sure it contains the Remote Support agent with its
   `server_url` / `secret` Application settings.
2. **Enroll.** Either factory-reset the device, tap the welcome screen 6×, and scan the
   configuration's QR code (**recommended**: silent installs, full control). Or install
   the MDM agent APK and enter the server and a device ID.
3. **Install.** Wait for the apps to install (tap **Install** if asked).
4. **Set up the agent once.** Open **Remote Support**, agree to the terms, and enable
   its Accessibility service.
5. **Test.** Send a `runApp` push (see
   [Remote control sessions](#remote-control-sessions)), connect from the console,
   and tap **Start now** on the device.

## Enrolling devices

1. **MDM → Applications:** upload the POS app APK (`app-release.apk`) and the
   **Remote Support** agent APK (built from its own repo, see below).
2. **MDM → Configurations:** create one configuration per role, for example *Register*,
   *Payment phone*, *Display* and *Display manager*. Add both apps to each.
   - **Kiosk mode** with the POS app as the main app locks a device to it.
   - Add the remote agent to the kiosk's allowed apps so staff can start sessions.
3. **Enroll each device:**
   - **Full control (device owner):** factory-reset the device, tap the welcome screen
     6 times, and scan the configuration's QR code (MDM → Devices → QR code).
   - **Without a reset:** install the Headwind MDM launcher APK and enter the server and
     device ID. You get less control: installs and remote control ask for confirmation.
   - **Fire TV:** can't be device owner; use the second method.

**The remote agent** is our MDM-integrated build of the open-source agent, in
[lts-remote-support-android](https://github.com/yensencc/lts-remote-support-android) (package `com.lasttechsol.remotesupport`, shown as **Remote
Support**). It takes its server URL, secret and name from the MDM's Application
settings, the MDM can start it, and it reports its session code to the MDM panel.
Build it there with `scripts/build.sh` (signed with a key kept outside Git).
MDM setup is in [its README](https://github.com/yensencc/lts-remote-support-android#5-headwind-mdm-integration).
In short, these are the Application settings for `com.lasttechsol.remotesupport`:

| Attribute | Value |
| --- | --- |
| `server_url` | `https://remote.<domain>` |
| `secret` | `JANUS_API_SECRET` from `.env` |
| `device_name` | optional; default is the MDM device number |

## Configuring the POS app from the MDM

The POS app reads **Application settings** for `com.yensencc.react_native_pos` (MDM →
Configurations → Application settings, or per device). It applies them at startup and
whenever the MDM pushes a change:

| Attribute | Values | Used by |
| --- | --- | --- |
| `pos_role` | `register`, `display`, `terminal`, `manager` | all (**required**) |
| `pos_register_host` | the register's LAN IP/hostname | display, terminal, manager |
| `pos_pair_code` | the register's 4-digit code | display, terminal |
| `pos_manager_code` | the register's 6-digit manager code | manager |
| `pos_display_name` | e.g. `Menu board` | display |
| `pos_display_mode` | `order`, `queue`, `media` | display |
| `pos_rotation` | `0`, `90`, `180`, `270` | display |
| `pos_business_name`, `pos_currency` | e.g. `Samantha Coffee`, `usd` | register without Stripe keys |

Stripe keys are **never** set through the MDM. Full details are in the POS repo:
`docs/REMOTE_SUPPORT.md`.

## Remote control sessions

**From the MDM panel (Remote Support agent):**
1. **Push messages:** choose the device, type `runApp`, payload
   `{"pkg":"com.lasttechsol.remotesupport","extra":{"connect":true}}`.
2. **Read the code:** the agent opens, connects, and reports `Session … PIN … <link>`.
   It shows up in the device's log right away (with a Device Log rule) and in the
   device's custom field 1 within about 15 minutes.
3. **Connect:** open the link and press **Connect** in the console.
4. **On the device:** someone taps **Start now** on Android's casting prompt.

**From the device:** open **Remote Support** and read out the session ID and PIN it
shows.

**First time on each device:** agree to the terms and enable the app's Accessibility
service (needed for remote taps). You then see the screen and control it with mouse and
keyboard.

**Premium** (from Headwind) adds a Remote Control button in the MDM device list. See
[Limits](#limits-to-know).

## Operations

| Task | Command (in `/opt/remote-support`) |
| --- | --- |
| Status: containers, memory, ports, certificate expiry | `./scripts/status.sh` |
| Logs | `docker compose logs -f hmdm` (or `janus`, `postgresql`) |
| Backup now | `./scripts/backup.sh` (to `/var/backups/remote-support`, kept 14 days) |
| Apply `.env` changes / reload certificates | `./scripts/update.sh` |
| Restart | `docker compose restart` |
| Upgrade the MDM | Change `HMDM_IMAGE` / `HMDM_URL` / `CLIENT_VERSION` in `.env`, back up, then `./scripts/update.sh` |
| Remove (keeps data) | `./scripts/uninstall.sh` (`--purge` deletes all MDM data) |

**Certificates** renew automatically, and nginx reloads after each renewal. Run
`./scripts/update.sh` after a renewal so the MDM's internal keystore picks up the new
certificate. It isn't used for any public port, so this is housekeeping.

## Security

**This server can see and control payment devices. Treat it as production payment
infrastructure.**
- **SSH:** keys only, no passwords. Keep the OS updated; the installer enables
  unattended upgrades.
- **MDM panel:** change `admin/admin` on first login; use a long unique password.
  Restrict the panel by IP if you can.
- **Remote console:** it's behind basic auth because it contains the Janus API secret.
  Anyone with that secret plus a device's session ID and password could view that
  device. Rotate it by clearing `JANUS_API_SECRET` in `.env`, running
  `./scripts/update.sh`, and updating the agents.
- **Database:** PostgreSQL isn't published outside the Docker network (upstream
  hmdm-docker publishes 5432; this setup doesn't).
- **Merchant consent:** tell merchants in writing that devices are managed and can be
  viewed remotely. Don't control a device while it's taking a payment.
- **Agent provenance:** the official remote-control repos are no longer public. The
  vendored code is pinned to the **last commits by Headwind's own developer** (see
  [THIRD_PARTY.md](THIRD_PARTY.md)). Headwind Remote has been falsely flagged by Google
  Play Protect before, so install the agent through the MDM, from your own signed build.
- **Tap to Pay:** check it on each device model with the agent installed, because the
  agent's Accessibility service may trip payment security checks.

## Limits to know

- **Unattended sessions:** on Android 14+ every screen-sharing session shows a
  **consent prompt** on the device. The open-source agent (ours included) always needs
  someone on site to tap it; the MDM can start the agent and show its code, but not
  accept that prompt.
  Headwind's Premium agent starts sessions from the MDM; how far it avoids the prompt
  depends on device-owner enrollment and the device/Android version, so confirm with
  Headwind per model before buying.
- **Janus 0.10.7:** the vendored agent uses the pre-1.0 Janus streaming API, so Janus is
  pinned to 0.10.7 (2020).
- **1 GB servers:** fine for a pilot. Expect a slow first start (Java) and some swapping
  while APKs are uploaded or pushed. Resize at your provider when you add merchants, then
  set `TOMCAT_MAX_HEAP=512m`, `HMDM_MEM_LIMIT=900m` and run `./scripts/update.sh`.

## Repository layout

```
install.sh                    one-shot installer (Ubuntu, root)
docker-compose.yml            postgresql + hmdm + janus (pinned images, memory limits)
.env.example                  settings; install.sh fills in secrets -> .env (git-ignored)
nginx/                        host nginx sites (mdm, remote) + TLS snippet
remote/janus/*.tmpl           Janus config, from Headwind Remote's templates (loopback-only)
remote/web-admin/             console settings template (Janus URLs + API secret)
scripts/                      build-web-admin, backup, update, status, uninstall
vendor/hmdm-docker/           Headwind MDM Docker source (image build reference)
vendor/headwind-remote-server/  Headwind Remote server: web console + Janus image build
vendor/headwind-remote-agent/   Headwind Remote Android agent (aPuppet) source, unchanged
THIRD_PARTY.md                where each vendored component comes from, and its license
```

**Generated on the server (not in Git):** `.env`, `data/` (database, MDM files),
`generated/` (rendered Janus configs, built console).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Saved changes and `runApp` pushes reach devices only on their periodic sync; the hmdm log shows `User name [hmdm] or password is invalid` | `SHARED_SECRET` doesn't match the MDM agent APK. Set `SHARED_SECRET=changeme-C3z9vi54` (the stock agent's value) in `.env`, put the same value in `hash.secret` in `data/hmdm-config/ROOT.xml`, then `docker compose up -d hmdm` |
| `install.sh`: "resolves to …, expected …" | DNS isn't pointing here yet; wait for propagation (`dig +short mdm.<domain>`) |
| certbot fails | Port 80 blocked by the provider firewall, or DNS not propagated |
| MDM shows 502 for a few minutes after start | Java is still starting (slow on 1 vCPU); `docker compose logs -f hmdm` |
| MDM container restarts, "Killed" in logs | Out of memory: check swap (`swapon --show`); raise `HMDM_MEM_LIMIT` or resize the server |
| Console loads, but a session never shows video | UDP range blocked: check `ufw status` and the provider firewall; check `PUBLIC_IP` in `.env` |
| Agent: "Unauthorized request" | Wrong secret: it must equal `JANUS_API_SECRET` |
| Devices don't get pushes | Port 31000/tcp blocked |
| MDM log: `Failed to initialize component [Connector["https-openssl-nio-8443"]]` | Harmless: Tomcat's own HTTPS port isn't used (nginx terminates TLS) and can't load the ECDSA Let's Encrypt key. The panel and devices use port 8080 behind nginx |

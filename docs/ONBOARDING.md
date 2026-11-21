# Onboarding a device: fully managed and remote-supported

This runbook takes a device from out of the box (or factory reset) to:
- **fully managed:** Headwind MDM is the **device owner**, so app installs and updates
  are silent and permissions are granted automatically;
- **remote-supported:** the **Remote Support** agent is installed and configured, and a
  support person can view and control the screen from a browser.

| Phase | Where | Once per… | Time |
| --- | --- | --- | --- |
| [Apps: prerequisites](#apps-prerequisites) | MDM panel | app version | 5 min per app |
| [A. Server preparation](#a-server-preparation-once) | MDM panel | server | 15 min |
| [B. Configuration per role](#b-a-configuration-per-device-role-once-per-role) | MDM panel | role (register, display…) | 10 min |
| [C. Register the device](#c-register-the-device-in-the-mdm) | MDM panel | device | 1 min |
| [D. Enroll](#d-enroll-the-device-qr-code-device-owner) | the device | device | 10 min |
| [E. One-time setup on the device](#e-one-time-setup-on-the-device) | the device | device | 2 min |
| [F. Verify](#f-verify) | server + browser | device | 3 min |

Which path fits which device:

| Device | Path | Result |
| --- | --- | --- |
| Android phone or tablet, 9+ (any brand, including onn) | **QR enrollment** (D1) after a factory reset | Fully managed |
| Android 7–8 | QR enrollment; it first downloads a QR reader over Wi-Fi | Fully managed |
| Already set up, can't be reset / Fire TV / Android TV | **Manual install** (D2) | Managed, but each install or update needs a tap; limited kiosk |

> Moving an existing device (such as the onn tablet) to **fully managed** requires a
> factory reset. Do it together with the POS app's switch to its private signing key,
> since that needs a reinstall anyway.

---

## Apps: prerequisites

**Nothing has to be installed on the device beforehand.** For QR enrollment you only
need a factory-reset device with internet. Every app comes from the MDM, so each one
must be **uploaded to the MDM before you onboard a device**.

| # | App (as shown on the device) | Package | Current version | What it does | How it reaches the device | Ready in the MDM? |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | **Headwind MDM** | `com.hmdm.launcher` | 6.40 | The MDM agent: device owner, installs and updates the other apps, kiosk mode | **QR:** Android downloads it during setup from `https://mdm.lasttechsol.com/files/hmdm-6.40-os.apk`. **Manual:** you install that APK (D2) | ✅ comes with the server install |
| 2 | Headwind MDM update helper | `com.hmdm.emuilauncherrestarter` | 1.04 | Lets the agent update itself | Installed by the MDM | ✅ in "Common - Minimal" |
| 3 | Headwind MDM Pager Plugin | `com.hmdm.pager` | 1.02 | Shows text messages sent from the panel (Messaging plugin) | Installed by the MDM | ✅ in "Common - Minimal" |
| 4 | **Remote Support** | `com.lasttechsol.remotesupport` | 2.02-lts2 | Remote screen view and control | Installed by the MDM | ✅ uploaded. **Turn "Show icon" on** in each configuration (it's off today) |
| 5 | **POS app** | `com.yensencc.react_native_pos` | (first private-key build) | The business app | Installed by the MDM | ❌ **not in the MDM yet.** Add it after the private-key switch |

**Not wanted:** *Headwind Remote / aPuppet* (`com.hmdm.control`), the old remote agent.
Both configurations are already set to **Remove** it.

### Adding an app (or a new version) to the MDM

1. **Build the release APK:**
   - Remote Support: `scripts/build.sh` in lts-remote-support-android →
     `dist/remote-support-agent-<version>.apk`.
   - POS app: its signed release build.
2. **First time: Applications → Add.**
   - **Type:** Application.
   - **File:** upload the APK. **Package ID**, **name** and **version** fill in by
     themselves; check them.
   - **Native code:** None (universal APK).
   - **Show icon:** On.
   - **Preinstalled**, **Run after installation** and **Run at boot:** Off.
   - Save.
3. **New version: Applications → the app → Versions → Add.**
   - Upload the APK; it needs a higher `versionCode` than the current one.
   - When asked, apply it to the configurations.
4. **In each configuration that should have it:** Applications → set the app to
   **Install** and **Show icon** on → Save. Enrolled devices get it within seconds:
   silently when fully managed, with an **Install** prompt otherwise.

## A. Server preparation (once)

1. **MDM login:** use https://mdm.lasttechsol.com with your own admin password (not
   `admin/admin`).
2. **Applications:** apps 1–5 from [Apps: prerequisites](#apps-prerequisites) exist at
   their current versions. Remote Support is built in
   [lts-remote-support-android](https://github.com/yensencc/lts-remote-support-android).
   The POS app must be signed with its **private release key**.
3. **Old agent:** the old *Headwind Remote* (`com.hmdm.control`) is set to **Remove** in
   every configuration.
4. **Settings: custom property 1.**
   - Name it `Remote session`, so the session code shows in the device list.
   - Leave **Send to device** off.
5. **Plugins → Device Log → Settings: add a rule.**
   - **Application:** `com.lasttechsol.remotesupport`. **Level:** Info.
   - Session codes then reach the panel within seconds.
6. **Push check:** push is what delivers instant installs and remote session starts. If
   `docker compose logs hmdm` shows `User name [hmdm] or password is invalid`, see the
   README troubleshooting (`SHARED_SECRET`).

## B. A configuration per device role (once per role)

Use one configuration per role: **POS Register**, **POS Payment phone**, **POS Display**,
**POS Manager**. Create each by **copying "Common - Minimal"**. Don't use the vendor
templates such as "MIUI (Xiaomi Redmi)"; they add vendor-specific helper apps.

In each configuration:

| Tab / field | Set to | Why |
| --- | --- | --- |
| **Applications** → Headwind MDM | Install (already there; it's the main app) | The MDM agent itself |
| **Applications** → Remote Support | **Install**, show icon | Remote support |
| **Applications** → POS app | **Install**, show icon | The business app |
| **Application settings** → app `com.lasttechsol.remotesupport` | `server_url` = `https://remote.lasttechsol.com`<br>`secret` = `JANUS_API_SECRET` from the server `.env` (stored in the operator's credentials sheet) | Zero-typing remote support. **Without these, new devices come up unconfigured** |
| **Application settings** → app `com.yensencc.react_native_pos` | `pos_role` (+ `pos_register_host`, `pos_pair_code`, …; see README "Configuring the POS app") | The device starts in the right role. **Never** put Stripe keys here |
| **Push notifications** | **MQTT + alarm** (`mqttAlarm`, a persistent connection) | Instant updates and session starts |
| **Run-time permissions** | **Grant all** (the default) | No permission prompts |
| **Mobile enrollment / Wi-Fi** (optional) | the shop's Wi-Fi SSID and password | The QR code then joins Wi-Fi by itself |
| **Kiosk mode** (registers, displays) | On, main app = POS app. **Enable it after** the device is verified (F) | Locks the device to the POS app |
| **Kiosk mode** (phones you also use otherwise) | Off | |

**Device-specific values** (a register's host IP, a display's name and rotation) can be
set per device later: **Devices → device → Application settings**.

## C. Register the device in the MDM

1. **Devices → Add.**
   - **Number** (the device ID): use a fixed naming scheme with no spaces, for example
     `samantha-register-1`, `samantha-display-2`. It becomes the name shown in Remote
     Support and in the console.
   - **Description:** shop and location ("Samantha Coffee, front counter").
   - **Configuration:** the device's role (B).
2. **Save, then click the device's QR code icon.** That QR code carries the configuration
   **and** this device ID, so nothing is typed on the device.

## D. Enroll the device (QR code, device owner)

### D1. QR enrollment (fully managed)

1. **Before the reset:**
   - **Remove any Google account** from the device (Settings → Accounts). Otherwise
     factory-reset protection asks for it after the reset.
   - **Charge the device** above 30%.
2. **Factory reset:** Settings → System → Reset options → **Erase all data**.
3. **On the first welcome screen,** tap the **same spot 6 times** quickly. A QR scanner
   opens.
   - **Android 7–8:** connect Wi-Fi when asked; it downloads a QR reader first.
   - **No scanner after 6 taps:** you've moved past the first screen. Go back to it, or
     reset again.
4. **Scan the QR code** from step C.
5. **Wi-Fi:** connect if the QR code doesn't include it.
6. **"This device belongs to your organization":** accept. The device downloads the
   Headwind MDM agent from `https://mdm.lasttechsol.com/files/hmdm-6.40-os.apk` and makes
   it the **device owner**.
7. **Headwind MDM opens and walks through its own permission screens** (overlay, usage
   access and so on). Allow each one.
8. **Wait 1–3 minutes.** The MDM installs apps 2–5 (update helper, Pager plugin, Remote
   Support, POS app) by itself, with no prompts.

### D2. Manual install (devices that can't be reset / Fire TV)

1. **On the device:** download `https://mdm.lasttechsol.com/files/hmdm-6.40-os.apk` with
   the browser. On Fire TV, use the *Downloader* app.
2. **Allow "Install unknown apps"** for that browser or Downloader, then install.
3. **Open Headwind MDM** and allow its permission screens.
4. **Server URL:** when asked, enter `https://mdm.lasttechsol.com`.
5. **Device ID:** enter the device ID from step C.
6. **Install the apps:** when Headwind MDM offers Remote Support and the POS app, tap
   **Install** for each. Updates will ask again each time.
7. **Keep push working:** Settings → Apps → Headwind MDM → Battery → **Unrestricted**.

## E. One-time setup on the device

Android doesn't let an MDM do these steps, so someone on site does them once.

1. **Open Remote Support:**
   - Tap **Agree**.
   - **Enable its Accessibility service** when asked: Settings → Accessibility → Remote
     Support → On. This is what lets you tap and type remotely.
   - **Switch greyed out ("restricted setting"):** Settings → Apps → Remote Support → ⋮
     → **Allow restricted settings**, then try again.
   - **Check:** the app shows "Connected" with a Session ID and PIN.
2. **Open the POS app:**
   - It starts in its role from the MDM settings.
   - Enter anything that must stay local, such as the Stripe restricted key, on the
     device.
3. **Kiosk:** if the configuration will use kiosk mode, turn it on now in the MDM (B).

## F. Verify

1. **Run the checklist on the server:**

   ```bash
   ssh remote-support
   cd /opt/remote-support && ./scripts/device-status.sh "samantha-register-1"
   ```

   Every line should be `[x]`. It checks:
   - the device is syncing;
   - it's fully managed (device owner);
   - each configured app is installed at the expected version;
   - Remote Support's settings are in the MDM;
   - Remote Support has reported a session.

   `./scripts/device-status.sh` with no argument lists every device with its score.
2. **Start a session from the panel:**
   1. **Push messages → Send:** pick the device, type `runApp`, payload
      `{"pkg":"com.lasttechsol.remotesupport","extra":{"connect":true}}`.
   2. **Read the code:** the device's **log** (or its *Remote session* field) shows
      `Session … PIN … <link>`.
   3. **Connect:** open the link (console login `support`), then press **Connect**.
   4. **On the device:** someone taps **Start now** (Android asks at every session).
   5. **Check control:** you see the screen and can tap. Disconnect.
3. **Record the device:** device ID, shop, model, serial, role and enrollment date go in
   the shop's records.

### Done: what a successfully onboarded device has

**Apps** (Settings → Apps; app icons on the home screen, or in the kiosk launcher):

| App | Package | Version | Icon | Status |
| --- | --- | --- | --- | --- |
| Headwind MDM | `com.hmdm.launcher` | 6.40 | — (runs the device; it's the home screen in kiosk mode) | Device owner |
| Headwind MDM update helper | `com.hmdm.emuilauncherrestarter` | 1.04 | no | Background |
| Headwind MDM Pager Plugin | `com.hmdm.pager` | 1.02 | yes | Shows panel messages |
| **Remote Support** | `com.lasttechsol.remotesupport` | 2.02-lts2 (or newer) | yes | Accessibility **On**; shows "Connected" with a Session ID and PIN when opened |
| **POS app** | `com.yensencc.react_native_pos` | current release | yes | Opens in its role (register, display…) |

**Not present:** *Headwind Remote* / *aPuppet* (`com.hmdm.control`).

**Other signs it worked:**
- **Ownership notice:** the quick settings or lock screen says *"This device is managed
  by your organization"* (fully managed only).
- **Device admin:** Settings → Security → Device admin apps shows **Headwind MDM**
  enabled.
- **Accessibility:** Settings → Accessibility → **Remote Support** is On.
- **MDM panel:**
  - **Devices:** the device shows a recent *last update*, and its *Remote session*
    column has `Session … PIN … <link>`.
  - **Device Log:** has the "Remote support ready" line.
- **Checklist:** `./scripts/device-status.sh "<device-id>"` shows every line `[x]`. It
  checks each configured app at the expected version, so it catches a missing or
  outdated app.

If an app is missing: open **Headwind MDM** on the device (a non-owner device may be
waiting for an **Install** tap), then rerun the checklist.

## Afterwards

| Task | How |
| --- | --- |
| Update an app on all devices of a role | Applications → app → add version → apply to the configurations (devices update within seconds; silently when fully managed) |
| Change a device's role | Devices → device → configuration |
| Remote session | F2 |
| Device lost or stolen | Remote wipe/lock isn't in the Community edition. Delete the device in **Devices** (it stops getting configurations), and rotate the Remote Support secret (README → Security), because it was on the device |
| Retire a device | Factory reset it, then delete it in Devices |

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| QR scan: "Couldn't set up device" / "contact your IT admin" | The device can't download `hmdm-6.40-os.apk` (no Wi-Fi or internet), or the device still has an account. Reset and retry with Wi-Fi in the QR code |
| Enrolled, but apps don't install | `device-status.sh` shows what's missing. Check the configuration's Applications tab (action **Install**) and that push works (A6) |
| Remote Support shows the settings screen | `server_url` / `secret` missing in the configuration's Application settings (B) |
| Session code never shows in the panel | No Device Log rule (A5); the custom field updates only every ~15 min |
| "Connecting" forever in Remote Support | Agent older than 2.02-lts2; update it |
| Taps don't work in a session | Accessibility is off for Remote Support (E1) |

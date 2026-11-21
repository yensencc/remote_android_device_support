# Onboarding a device: fully managed and remote-supported

This runbook takes a device from out of the box (or factory reset) to:
- **fully managed:** Headwind MDM is the **device owner**, so app installs and updates
  are silent and permissions are granted automatically;
- **remote-supported:** the **Remote Support** agent is installed and configured, and a
  support person can view and control the screen from a browser.

| Phase | Where | Once per… | Time |
| --- | --- | --- | --- |
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

## A. Server preparation (once)

1. **MDM login:** use https://mdm.lasttechsol.com with your own admin password (not
   `admin/admin`).
2. **Application: Remote Support.**
   - **Applications:** the app (`com.lasttechsol.remotesupport`) must exist with its latest
     APK. It's built in
     [lts-remote-support-android](https://github.com/yensencc/lts-remote-support-android).
   - **Show icon:** On. **Run after install / at boot:** Off.
3. **Application: POS app** (`com.yensencc.react_native_pos`).
   - Add it the same way, signed with its **private release key** (once that switch is
     done).
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
8. **Wait 1–3 minutes.** Remote Support and the POS app install by themselves, with no
   prompts.

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

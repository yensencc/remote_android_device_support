# Remote Support agent (MDM-integrated build)

This is the Headwind Remote (aPuppet) Android agent from
`vendor/headwind-remote-agent` (v2.02, unchanged copy kept there for reference),
with a small integration with **Headwind MDM**. Apache License 2.0, as upstream; every
modified file says so at the top.

Package id **`com.lasttechsol.remotesupport`**, app name **Remote Support**. It's
separate from the official `com.hmdm.control`, so both can be installed side by side
and the official app never "updates" over this build.

## What it adds

| Feature | How |
| --- | --- |
| **Zero-typing setup** | On every start the agent reads `server_url`, `secret` and `device_name` from the MDM's *Application settings* for its package (`MdmBridge.java`, through the launcher's `com.hmdm.IMdmApi`). Without `device_name`, the MDM device number is used, so the name matches the MDM device list |
| **Start from the MDM panel** | A Push message of type `runApp` with payload `{"pkg":"com.lasttechsol.remotesupport","extra":{"connect":true}}` opens the agent, which connects at once (even after an earlier error) and gets a new session ID and PIN |
| **Session codes in the MDM panel** | When connected, the agent sends `Session <id> PIN <pin> https://<server>/web-admin/?session=<id>&pin=<pin>`:<br>• as a **device log** line, uploaded right away (needs a Device Log rule, see below);<br>• into **custom field 1** (or the one in `session_field`), shown in the device list within about 15 minutes.<br>Exiting clears it |
| **Idle timeout from the MDM** | `idle_timeout` (seconds; `0` = never). Default 120 s: the agent exits if nobody connects |

## Fixes

- **Device names can't break the session.** A device name ending in a typed Enter made the agent "connect" forever, because the textroom join was built by string concatenation. The join now uses `JSONObject`, and names are stripped of control characters.
- **"Never" idle timeout sticks.** Upstream reset it to 120 s on the next start.
- **The share-link message** had its two arguments swapped, and its URL pointed at `/` instead of `/web-admin/`.
- **Data channel start (2.02-lts2).** The first data-channel message is now sent once the channel is open. The newer WebRTC library drops messages sent earlier, so the agent stayed on "connecting" forever with the server never seeing a room request.
- **The build works again.** `org.webrtc:google-webrtc:1.0.32006` and jcenter no longer exist. It now uses `io.github.webrtc-sdk:android:125.6422.07` from Maven Central, the same `org.webrtc` API (the agent only uses its DataChannel), and is ARM-only.

## What it does NOT do

**Android still asks "Start recording / casting?" for every session**, and someone on site taps **Start now**. The agent doesn't, and won't, tap through that system prompt. That is Android's protection against silent screen capture.

## Building

```bash
./scripts/build-agent.sh        # → dist/remote-support-agent-<version>.apk
```

You need JDK 17 and the Android SDK with platform 33. Set `ANDROID_HOME` if the SDK isn't in `~/Library/Android/sdk`.

### Signing

- **Key location.** The release key lives **outside the repo**, at `~/.config/remote-support/agent-release.jks`. Its passwords are in `~/.config/remote-support/agent-signing.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; mode 600). Set `AGENT_SIGNING_PROPERTIES` to use another file.
- **Back up both files somewhere safe.** Updates must be signed with the same key. If you lose it, every device has to uninstall the app before it can take a new build.
- **Certificate SHA-256:** `27:79:22:82:04:08:7B:C4:19:79:CD:95:7C:CC:0F:CF:DE:9A:3F:4D:F8:26:2E:88:D7:F3:E7:F7:B4:AF:D0:D2`
- **To release a new version,** bump `versionCode` / `versionName` in `app/build.gradle`.

## Setting it up in Headwind MDM

1. **Applications → Add application → upload** `dist/remote-support-agent-<version>.apk`.

2. **Configurations → (your configuration) → Applications:** set the app to **Install**.

3. **Same configuration → Application settings:** add these, for application `com.lasttechsol.remotesupport`:

   | Name | Value |
   | --- | --- |
   | `server_url` | `https://remote.lasttechsol.com` |
   | `secret` | the `JANUS_API_SECRET` from the server's `.env` |
   | `device_name` | *(optional; default: the MDM device number)* |
   | `idle_timeout` | *(optional)* e.g. `600` |
   | `session_field` | *(optional)* `1`–`3`, or `0` to not use a custom field |

4. **Settings:** give *custom property 1* a name, e.g. "Remote session", so it shows in the device list. Leave its "send to device" option **off**.

5. **Plugins → Device Log → Settings:** add a rule for application `com.lasttechsol.remotesupport`, level **Info**. Session lines then appear under the device's logs right away.

6. **On each device, once:**
   - Open **Remote Support** and agree to the terms.
   - Enable its **Accessibility** service. This is for remote taps and typing; without it you can watch but not control.
   - On Android 13+, if the Accessibility switch is greyed out ("restricted setting"): App info → ⋮ → **Allow restricted settings**.

   **Device-owner enrollment** (QR code) also grants the other permissions silently.

### Starting a session from the panel

1. **Push messages:** choose the device, type **`runApp`**, payload `{"pkg":"com.lasttechsol.remotesupport","extra":{"connect":true}}`.
2. **Read the code.** The device's log, or its "Remote session" field, shows `Session … PIN … <link>`. The agent also shows it on screen.
3. **Connect.** Open the link, log in to the console, and press **Connect**.
4. **On the device,** someone taps **Start now** on Android's casting prompt.

## Security notes

- **The secret** (the Janus API secret) is an MDM Application setting, so it isn't in the code or the APK.
- **Other apps on the device can read it.** The launcher's API doesn't authenticate callers, so any app on an enrolled device could read the Application settings, the secret included. That's acceptable on dedicated POS devices; don't use it on devices with untrusted apps.
- **Session PINs reach the MDM panel** (admins only) and the device log. A session ends when the agent exits or goes idle, and the next one gets new codes.

# iOS test builds (free Apple ID, no Mac)

How Axon is built for iPhone without a Mac or a paid Apple Developer account:

1. **Codemagic** (cloud macOS) builds an **unsigned** release build (workflow `ios-unsigned` in `codemagic.yaml`).
2. The result is packaged as `axon-<version>-<build>-unsigned.ipa`.
3. On Windows, **Sideloadly** signs it with a **free Apple ID** and installs it on the iPhone over USB.

Bundle ID in the project: `com.appaxon.axon` (same as the Android applicationId). Nothing in the app depends on the bundle ID at runtime, so it is fine if Sideloadly changes it while signing.

---

## 1. What works and what doesn't with free signing

| Area | Status |
|---|---|
| Login, logout, sessions, attacks, calendar, statistics, chat, voice messages | Works |
| Push notifications (FCM) | **Not available.** A free Apple ID cannot get the APNs entitlement. The app skips FCM on iOS entirely: no notification permission prompt, and no token is sent to the backend. New chat messages still appear in-app through normal polling. |
| In-app update dialog | **Disabled on iOS.** It only exists for Android (APK link). A new iOS build has to be installed manually (see section 4). |
| App lifetime | The signature **expires after 7 days**, after which the app no longer opens. Re-install weekly (see section 5). |
| Number of apps | A free Apple ID can have at most **3 sideloaded apps** active per device, and 10 App IDs per 7 days. |
| Data across re-installs | Re-installing **on top of** the existing app (without deleting it first) keeps the login and local data. Deleting the app clears local data. The keychain login may survive a delete, but don't count on it. |
| Dark mode | The app has a light theme only. It stays light when iOS is in dark mode, which is expected. |

---

## 2. Codemagic setup (one time)

1. Sign in at <https://codemagic.io> with the Git provider that hosts this repo, then add the repository as an application. Codemagic detects `codemagic.yaml` automatically.
2. Go to the app's **Environment variables** and create a group named **`axon_ios`** with these variables:

   | Variable | Value | Secure |
   |---|---|---|
   | `GOOGLE_SERVICE_INFO_PLIST` | base64 of `GoogleService-Info.plist` (see below) | Yes |
   | `API_BASE_URL` | `https://axon.tera-software1.com` (no `/api`, no trailing slash) | No |

   Both are optional. Without `GOOGLE_SERVICE_INFO_PLIST` the app builds and runs with Firebase disabled. Without `API_BASE_URL` it uses the production URL built into the app.

3. **Get `GoogleService-Info.plist`:** Firebase console → project → *Add app* → iOS → bundle ID `com.appaxon.axon` → download the file. **Do not commit it**, because it is in `.gitignore`. Then base64-encode it on Windows (PowerShell, in the folder that holds the file):

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("GoogleService-Info.plist")) | Set-Clipboard
   ```

   Paste the clipboard into `GOOGLE_SERVICE_INFO_PLIST` and tick *Secure*.

   With free signing this file only makes Firebase initialize. Push still doesn't work (see section 1). It is needed later for real push.

## 3. Build and download the .ipa

1. In Codemagic, open the app and click **Start new build**.
2. Choose branch `main` and workflow **iOS unsigned (Sideloadly)**, then click **Start**. It takes about 15–25 minutes.
3. When it finishes, open the build and go to **Artifacts**. Download `axon-<version>-<build>-unsigned.ipa`. Also available: `flutter_build_ios.log`, plus Xcode logs if any.
4. If the build fails, open the failed step and read its log. The full Flutter output is also in the `flutter_build_ios.log` artifact.

The version and build number in the file name come from `version:` in `pubspec.yaml`. Bump it before each build you hand out.

## 4. Install with Sideloadly (Windows)

One-time setup on the PC:

1. Install **iTunes** and **iCloud** from apple.com, using the *web installers* and **not** the Microsoft Store versions. Sideloadly needs their drivers.
2. Install **Sideloadly** from <https://sideloadly.io>.
3. Use a dedicated free Apple ID if possible, not your personal one. Two-factor authentication is fine.

One-time setup on each iPhone:

1. Connect the iPhone by USB, unlock it, and tap **Trust This Computer**.
2. iOS 16 or newer: enable **Developer Mode** in *Settings → Privacy & Security → Developer Mode → On*, then restart and confirm. The option only appears after the first sideload attempt. If it is missing, run the install once and then come back.

Install:

1. Open Sideloadly and select the iPhone.
2. Drag the `.ipa` in and enter the Apple ID.
3. Leave *Advanced options* at their defaults, then click **Start**. Enter the Apple ID password or app-specific password and the 2FA code if asked.
4. On the iPhone, trust the developer profile: *Settings → General → VPN & Device Management → [your Apple ID] → Trust*.
5. Open **Axon**.

## 5. Weekly re-install (7-day expiry)

- Before the 7 days run out, plug the phone in and install the **same or a newer** `.ipa` with Sideloadly using the **same Apple ID**. **Do not delete the app first**, so data and login are kept.
- Sideloadly can also auto-refresh over Wi-Fi if the PC is on, but the manual method is more reliable.
- If the app expires anyway, it just won't open. Re-install it the same way and nothing is lost.

---

## 6. Manual test checklist (iPhone)

Run this on both phones after every new build. Note the iOS version and model in the report.

**General**
- [ ] The app launches to the splash screen and login with no crash and no update dialog.
- [ ] **No** notification permission prompt appears, which is expected with free signing.
- [ ] Arabic RTL renders correctly on every screen: alignment, back-arrow direction, numbers and dates, and charts (LTR where intended).
- [ ] The keyboard never hides the field being typed into: login, chat input, dialogs, add case/device forms. Dragging or tapping outside dismisses it.
- [ ] Safe areas: nothing is under the notch, Dynamic Island, or home indicator, in both portrait and landscape.
- [ ] Dark mode on the phone: the app stays readable in its light theme.
- [ ] Kill and reopen the app: the session is restored without logging in again.

**Patient**
- [ ] Login and logout.
- [ ] Start a session and end a session.
- [ ] Log an attack, and check the attack confirmation prompt.
- [ ] Calendar shows the sessions and attacks.
- [ ] Chat: send text, **record and send a voice message** (the first time asks for microphone permission with the Arabic text), play your own voice message and one received from the doctor. Check playback volume (speaker, not earpiece) and that the phone's silent switch is handled.
- [ ] Account settings, info pages, and the **delete account** screen opens (cancel unless testing deletion on purpose).

**Doctor**
- [ ] Cases list loads and search/filter works.
- [ ] Case details: summary, sessions vs attacks chart, edit case.
- [ ] Attack statistics screen.
- [ ] Chat with patient and engineer, including voice messages both ways.

**Engineer**
- [ ] Devices tab: list, device details, add device.
- [ ] Clinics tab and device types tab, including add dialogs.
- [ ] Messages inbox: open a conversation, send text and voice.
- [ ] Overview tab numbers and charts.

**If the app crashes on launch**
1. Check that the profile is trusted (section 4, step 4) and that Developer Mode is on.
2. If it opened before but not now, the 7-day signature has probably expired. Re-install.
3. Get the crash log: *Settings → Privacy & Security → Analytics & Improvements → Analytics Data → `Runner-…`* (share it). Or connect to the PC and use Sideloadly's log or 3uTools.
4. Install the previous `.ipa` to check whether it's a regression. Report the build number, iOS version, and the crash log.

---

## 7. Switching to the paid Apple Developer account later

1. **Bundle ID:** register `com.appaxon.axon` in the Apple Developer portal (Identifiers) and create the app in App Store Connect.
2. **Signing:** create an App Store Connect API key and add it to Codemagic (*Teams → Integrations → Developer Portal*). Then uncomment and adjust the `ios-appstore` workflow in `codemagic.yaml`. It uses automatic signing and uploads to TestFlight. Also set `APP_STORE_APPLE_ID` (the numeric app ID) in the `axon_ios` group.
3. **Enable push:**
   - In the Apple Developer portal, create an **APNs Auth Key (.p8)** and upload it in *Firebase console → Project settings → Cloud Messaging → Apple app configuration*.
   - In Xcode (or by editing the project), add the **Push Notifications** capability. This creates `Runner.entitlements` with `aps-environment`.
   - Add **Background Modes → Remote notifications**: `UIBackgroundModes` = `remote-notification` in `Info.plist`.
   - Build with `--dart-define=IOS_PUSH_ENABLED=true`, which turns FCM on for iOS in `lib/core/notifications/fcm_service.dart`. This is already in the skeleton workflow.
4. **Updates:** the in-app update dialog is Android-only (`lib/core/update/app_update_provider.dart`). For App Store builds, either keep it off or extend it to open the App Store link.
5. Consider adding `ITSAppUsesNonExemptEncryption` = `false` to `Info.plist` (the app uses only HTTPS) to skip the export-compliance question on every upload.

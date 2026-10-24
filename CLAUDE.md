# CLAUDE.md

## Release & operations

Never push, deploy, or run commands against the production server or database unless the user asks. The user pushes and deploys.

### Releasing an update
- **iPhone (web app, https://axon.tera-software1.com/app/):** on the PC run `bash tool/build_web.sh` (needs `web_firebase.json`, otherwise the build has no push), then `scp build/axon-web.tar.gz` to the server. Next do step **B5** (new release folder, swap the `web` symlink) and the **first block of part C** in `DEPLOY_AND_TEST_CHECKLIST.md`; see **E4**. No nginx change or restart is needed. An open app checks `version.json` on start, on return to the foreground and every 30 min, and shows an "Update" banner when the server has a newer build. `build_web.sh` stamps every build with a new number, so this works without bumping `pubspec.yaml`.
- **Android (native APK):** there's no runbook in the repo, so this is the procedure:
  1. Bump `version:` in `pubspec.yaml`. The number after `+` is the versionCode and must be higher than the last published one.
  2. Run `flutter build apk --release`. It needs `android/key.properties`; the build stops without it. The output is `build/app/outputs/flutter-apk/app-release.apk`.
  3. In the Django admin, go to **App versions** (`app_updates`) and add a new version: platform `android`, `version_code` matching the `+` number, the APK in `apk_file`, release notes, then tick `is_published`.
  4. Users are prompted when they next open the app, and they install it themselves. `is_mandatory` blocks the app until they update.
  5. Before publishing, run the checks in `DEPLOY_AND_TEST_CHECKLIST.md` E6 / D7 step 31.
- **If a change touches both the backend and the app UI,** release both: deploy the backend, then a new web build and a new APK.

### Backend deploy and rollback
- `DEPLOY_AND_TEST_CHECKLIST.md` **B0–B10** covers backups, migrate, nginx, restart and rollback (B10). Verify with part **C**.
- `SERVER_SETUP.md` covers the first install, and §12 covers routine code updates.
- `deploy/RUNBOOK_voice_release.md` is an earlier step-by-step release with rollback. Use it as the pattern for new runbooks in `deploy/`.
- `deploy/` holds the systemd units, nginx snippets and the backup and restore scripts. The server copies live in `/etc/systemd/system/` and `/etc/nginx/`.

### Server notes
- The systemd drop-in `/etc/systemd/system/axon.service.d/firebase-group.conf` (`[Service]` `SupplementaryGroups=axon`) is **required**. `axon.service` runs with `Group=www-data`, and the Firebase credentials file is `root:axon 640`, so without the drop-in push fails silently with a `PermissionError`. `deploy/axon.service` now has the same line.
- `axon-attack-reminders.service` also sends push and also runs with `Group=www-data`. It doesn't have this line yet.

### Secret and local files (none are in Git)
| File | Where |
|---|---|
| `web_firebase.json` (Firebase web config for `build_web.sh`) | PC, project root (git-ignored); keep a backup |
| `/etc/axon/axon.env` (SECRET_KEY, DB password, settings) | server, `root:axon 640` |
| `/etc/axon/firebase-service-account.json` (FCM admin key) | server, `root:axon 640` (the PC copy `axon-f7a96-firebase-adminsdk-*.json` is git-ignored) |
| `android/key.properties` | PC (git-ignored); template: `android/key.properties.example` |
| Release keystore `care_path-upload.jks` | PC, **outside the project** (path in `key.properties`, e.g. `C:/keys/`); losing it means future APKs can't update installed ones |

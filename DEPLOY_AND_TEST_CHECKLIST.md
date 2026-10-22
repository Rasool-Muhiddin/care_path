# Axon PWA (iPhone web app): deploy and test checklist

Covers commits `b852018` … `754970b` (phases 1–7 of the PWA work) and this file.
Do the parts in order: **A** (your PC) → **B** (server) → **C** (verify on the server) → **D** (real iPhone) → **E** (after testing).

What this release changes for people already using Axon:

- **Android app (existing APK):** keeps working. The server changes are backward compatible
  (no header = old behavior), and you do **not** need to ship a new APK.
- **New:** the web app at `https://axon.tera-software1.com/app/` for iPhone users.
- **Server:** one migration (`notifications.0002`, choices only, runs no SQL), ffmpeg for voice
  conversion, two new nginx snippets, and a `Cache-Control: no-store` header on `/api/`. No new Python packages.

---

## Part A: on your PC

### A1. Firebase web app (for push notifications)

Without this the web app works fully, just without notifications. You can deploy first and add it
later, but then you rebuild and re-upload the web app (A3–A4, B6).

1. Open <https://console.firebase.google.com> and select the project **axon-f7a96**.
2. Click the **gear icon** next to "Project Overview" → **Project settings** → tab **General**.
3. Scroll to **Your apps** → **Add app** → choose the **Web** icon (`</>`).
4. App nickname: `Axon Web`. Leave **"Also set up Firebase Hosting" unticked**. Click **Register app**.
5. The page shows a code block with `const firebaseConfig = { apiKey: ..., authDomain: ..., projectId: ...,
   storageBucket: ..., messagingSenderId: ..., appId: ... }`. Copy these four values:
   `apiKey`, `appId`, `messagingSenderId`, `projectId`. Ignore the "npm install firebase" instructions and
   click **Continue to console**.
6. Still in Project settings, open the tab **Cloud Messaging**.
   - Check that **Firebase Cloud Messaging API (V1)** shows **Enabled** (it already is if Android push works).
   - Scroll to **Web configuration** → **Web Push certificates** → **Generate key pair**.
   - Copy the **Key pair** value: one long string starting with `B`, about 88 characters. That is the VAPID public key.
     (Never copy or share the private key; Firebase keeps it.)
7. In the project root on your PC (Git Bash):
   ```bash
   cd /e/TEST/care_path
   cp web_firebase.example.json web_firebase.json
   ```
   Open `web_firebase.json` and fill it in:
   ```json
   {
     "FIREBASE_WEB_API_KEY": "<apiKey>",
     "FIREBASE_WEB_APP_ID": "<appId, looks like 1:1234567890:web:abc123...>",
     "FIREBASE_MESSAGING_SENDER_ID": "<messagingSenderId>",
     "FIREBASE_PROJECT_ID": "axon-f7a96",
     "FIREBASE_WEB_VAPID_KEY": "<the Key pair from step 6>"
   }
   ```
   These are public identifiers (they end up in the web app), but the file is git-ignored on purpose. Keep a copy.
8. Only if your Google Cloud project restricts browser API keys by website:
   Google Cloud Console → APIs & Services → Credentials → the "Browser key" for axon-f7a96 →
   add `https://axon.tera-software1.com/*` under Website restrictions.

### A2. Push the code

```bash
cd /e/TEST/care_path
git status            # only PWA_FEASIBILITY_REPORT.md and axon_ios_prompt_for_claude_code.md untracked
git log --oneline -10 # 754970b ... b852018, plus the checklist commit on top
git push origin main
```

### A3. Build the web app

In **Git Bash** (not PowerShell):

```bash
cd /e/TEST/care_path
bash tool/build_web.sh
```

**OK:** ends with `Built build/web and build/axon-web.tar.gz`, and there is **no**
`WARNING: web_firebase.json not found` line (unless you chose to deploy without push for now).

Check that the Firebase config made it into the build (prints `1` or more):
```bash
grep -c "$(head -c 20 <<< "$(grep VAPID web_firebase.json | cut -d'"' -f4)")" build/web/main.dart.js
```

### A4. Upload the build to the server

```bash
scp build/axon-web.tar.gz ubuntu@SERVER_IP:/tmp/axon-web.tar.gz
```
(Use the same SSH user and host you normally use for the server.)

---

## Part B: deploy on the server (axon.tera-software1.com)

Run as `ubuntu` in one terminal session. If the session drops, run **B0** again before continuing.
Nothing here touches the pharmacy app. API downtime is only the few seconds of `systemctl restart axon` in B8.

### B0. Session setup (re-run in every new shell)

```bash
PY() { sudo bash -c 'set -a; . /etc/axon/axon.env; set +a; cd /var/www/axon/app; exec runuser -u axon -- /var/www/axon/venv/bin/python manage.py "$@"' _ "$@"; }
APP=/var/www/axon/app
REL=/var/backups/axon-release-web
DOMAIN=axon.tera-software1.com
sudo install -d -m 700 -o root -g root "$REL"
```

### B1. Pre-flight checks (read-only)

```bash
df -h / /var
systemctl is-active axon nginx postgresql
sudo -u axon git -C "$APP" status --porcelain
sudo -u axon git -C "$APP" fetch origin
sudo -u axon git -C "$APP" log --oneline HEAD..origin/main
sudo -u axon git -C "$APP" diff --stat HEAD origin/main -- requirements.txt '*/migrations/*'
sudo test -e "$REL/PREV_COMMIT" || sudo -u axon git -C "$APP" rev-parse HEAD | sudo tee "$REL/PREV_COMMIT"
```

**OK:**
- `is-active`: three lines of `active`.
- `status --porcelain` prints nothing.
- `HEAD..origin/main` lists the PWA commits (`Web (phase 1)` … `Web (phase 7)`, the checklist commit),
  possibly with older iOS/Codemagic commits that were never deployed. Those only touch `ios/` and `codemagic.yaml`.
- The `diff --stat` shows only `notifications/migrations/0002_device_token_web_platform.py`. `requirements.txt` is unchanged.
- `PREV_COMMIT` holds the current full hash. That is your rollback target.

**If not:** stop on local changes, unknown migrations or a non-active service. Don't deploy on top of a broken state.

### B2. Backups

```bash
sudo test -s "$REL/axon_db.dump" || sudo -u postgres pg_dump -Fc -d axon_db | sudo tee "$REL/axon_db.dump" >/dev/null
sudo pg_restore -l "$REL/axon_db.dump" | grep -c "TABLE DATA"
sudo cp -n -a /etc/nginx/sites-available/axon "$REL/nginx-axon.bak"
sudo ls -la "$REL"
```

**OK:** the `grep -c` prints a number above 10, and `nginx-axon.bak` exists.

### B3. Install ffmpeg (voice conversion)

```bash
sudo apt update
sudo apt install -y ffmpeg
ffmpeg -hide_banner -version | head -1
ffmpeg -hide_banner -encoders 2>/dev/null | grep -E ' aac '
sudo -u axon ffmpeg -hide_banner -version | head -1
```

**OK:** a version line (any ffmpeg 4.x–7.x), an ` A..... aac` encoder line, and the `axon` user can run it.
ffmpeg is installed to `/usr/bin`, which is on the service's default PATH, so no env change is needed.
(Only if you installed it somewhere else: add `FFMPEG_BINARY=/full/path/to/ffmpeg` to `/etc/axon/axon.env`.)

### B4. Pull the code and migrate

```bash
sudo -u axon git -C "$APP" pull --ff-only origin main
sudo -u axon git -C "$APP" log --oneline -1
sudo -u axon /var/www/axon/venv/bin/pip install -r "$APP/requirements.txt"
PY migrate --plan
PY sqlmigrate notifications 0002
PY migrate
PY makemigrations --check --dry-run
PY collectstatic --noinput
PY check --deploy
```

**OK:**
- `pull` says `Fast-forward`. `pip`: every line `Requirement already satisfied`.
- `migrate --plan` lists **only** `notifications.0002_device_token_web_platform`.
- `sqlmigrate` shows `-- (no-op)`: the migration only adds the `web` choice and changes nothing in the database.
- `migrate`: `Applying notifications.0002_device_token_web_platform... OK`.
- `makemigrations`: `No changes detected`.
- `check --deploy`: no errors, and **no `chat.W001`** (that warning means ffmpeg is not found).
  Warnings you already had before are fine.

**If not:** the database is unchanged until `migrate` (and this migration is SQL-free anyway).
Roll back the code with B11 part 3, then `sudo systemctl restart axon`.

### B5. Web files (release folder + `web` symlink)

```bash
TS=$(date +%Y%m%d-%H%M%S)
sudo install -d -o axon -g www-data -m 755 /var/www/axon/web-releases /var/www/axon/web-releases/$TS
sudo tar -xzf /tmp/axon-web.tar.gz -C /var/www/axon/web-releases/$TS --strip-components=1
sudo chown -R axon:www-data /var/www/axon/web-releases/$TS
sudo chmod -R u=rwX,g=rX,o=rX /var/www/axon/web-releases/$TS
ls /var/www/axon/web-releases/$TS
test -L /var/www/axon/web && readlink /var/www/axon/web | sudo tee "$REL/PREV_WEB"   # empty on the first deploy
sudo ln -sfn /var/www/axon/web-releases/$TS /var/www/axon/web
readlink /var/www/axon/web
```

**OK:** the listing shows `index.html  firebase-messaging-sw.js  main.dart.js  flutter_bootstrap.js  canvaskit  fonts  icons  assets  manifest.json ...`,
and the symlink points to the new folder.

### B6. nginx: add the web app

```bash
sudo cp "$APP/deploy/nginx-axon-web.conf"         /etc/nginx/snippets/axon-web.conf
sudo cp "$APP/deploy/nginx-axon-web-headers.conf" /etc/nginx/snippets/axon-web-headers.conf
```

Insert `include /etc/nginx/snippets/axon-web.conf;` into axon's site **before** `location / {`, and extend
`gzip_types`. This script does nothing if the include is already there, and refuses to edit unless it
finds exactly one `location / {`:

```bash
sudo python3 - <<'EOF'
import re, sys
p = '/etc/nginx/sites-available/axon'
s = open(p).read()
if 'snippets/axon-web.conf' in s:
    sys.exit('already present, nothing changed')
matches = list(re.finditer(r'^([ \t]*)location / \{', s, re.M))
if len(matches) != 1:
    sys.exit(f'STOP: found {len(matches)} "location / {{" lines; add the include by hand')
indent = matches[0].group(1)
pos = matches[0].start()
s = s[:pos] + f'{indent}# Axon PWA: /app/ and /firebase-messaging-sw.js\n{indent}include /etc/nginx/snippets/axon-web.conf;\n\n' + s[pos:]
old = 'gzip_types application/json text/css application/javascript text/plain;'
if old in s:
    s = s.replace(old, 'gzip_types application/json text/css application/javascript text/plain application/wasm font/ttf application/x-font-ttf application/manifest+json;')
    print('gzip_types extended')
open(p, 'w').write(s)
print('include inserted')
EOF
sudo grep -n "listen\|axon-web\|location\|gzip_types" /etc/nginx/sites-available/axon
sudo nginx -t && sudo systemctl reload nginx && echo "nginx reloaded"
```

**OK:** `include inserted` (and usually `gzip_types extended`). The grep shows the include line inside the server
block that has `listen 443 ssl`, just above `location /`. `nginx -t` says `syntax is ok` / `test is successful`, then `nginx reloaded`.

**If not:** if `nginx -t` fails, nothing was reloaded and the old config is still live. Restore the file and check again:
`sudo cp -a "$REL/nginx-axon.bak" /etc/nginx/sites-available/axon && sudo nginx -t`.

### B7. Cloudflare (dashboard, once)

- **Speed → Optimization → Rocket Loader: Off**, or at least add a rule that disables it for `/app/*`.
  Rocket Loader rewrites `<script>` tags and can break Flutter's loader.
- If you have a **Cache Rule "Cache Everything"** for this host, exclude `/app/*` and `/firebase-messaging-sw.js`.
  nginx sends `no-cache` for them. The default Cloudflare settings already respect that.
- DNS for `axon` must stay **Proxied** (orange cloud), as before.

### B8. Restart Django

```bash
sudo systemctl restart axon
systemctl status axon --no-pager | head -5
sudo journalctl -u axon -n 30 --no-pager
```

**OK:** `active (running)`, and no tracebacks in the log.

### B9. Remove the upload

```bash
rm -f /tmp/axon-web.tar.gz
```

### B10. Rollback (only if needed)

Pick the smallest part that fixes the problem.

1. **Web app only** (new web build is broken; API is fine):
   ```bash
   PREV_WEB=$(sudo cat "$REL/PREV_WEB" 2>/dev/null)
   if [ -n "$PREV_WEB" ]; then sudo ln -sfn "$PREV_WEB" /var/www/axon/web; else echo "first deploy: use part 2 to take /app/ offline"; fi
   ```
2. **nginx** (take `/app/` offline completely):
   ```bash
   sudo cp -a "$REL/nginx-axon.bak" /etc/nginx/sites-available/axon
   sudo nginx -t && sudo systemctl reload nginx && echo "nginx restored"
   ```
3. **Backend code:**
   ```bash
   PREV=$(sudo cat "$REL/PREV_COMMIT"); echo "rolling back to $PREV"
   sudo -u axon git -C "$APP" reset --hard "$PREV"
   sudo -u axon /var/www/axon/venv/bin/pip install -r "$APP/requirements.txt"
   PY collectstatic --noinput
   sudo systemctl restart axon
   curl -s -o /dev/null -w 'me (expect 401): %{http_code}\n' https://$DOMAIN/api/auth/me/
   ```
   The `notifications.0002` migration does **not** need to be reversed. It made no database change, and the old
   code ignores `web` device tokens' platform value. Web voice notes already stored are normal AAC m4a files that
   old clients play.
4. **Database restore:** only for real data damage (not expected from this release). See step 17 of
   `deploy/RUNBOOK_voice_release.md` and use `$REL/axon_db.dump`. Data written after B2 is lost.

---

## Part C: verify on the server (and from any PC)

```bash
# web app and service worker
curl -sI https://$DOMAIN/app | grep -iE "^HTTP|^location"                                  # 301 -> /app/
curl -sI https://$DOMAIN/app/ | grep -iE "^HTTP|content-type|cache-control|content-security"
curl -s  https://$DOMAIN/app/ | grep -c '<base href="/app/">'                              # 1
curl -sI https://$DOMAIN/app/canvaskit/canvaskit.wasm | grep -iE "^HTTP|content-type"       # 200, application/wasm
curl -sI https://$DOMAIN/app/fonts/IBMPlexSansArabic-Regular.ttf | grep -iE "^HTTP|content-type|cache-control"  # font/ttf, max-age=604800
curl -sI https://$DOMAIN/firebase-messaging-sw.js | grep -iE "^HTTP|content-type"           # 200, application/javascript
curl -sI https://$DOMAIN/app/manifest.json | grep -iE "^HTTP"                               # 200

# Django still answers everything else
curl -s -o /dev/null -w 'me: %{http_code}\n' https://$DOMAIN/api/auth/me/                   # 401
curl -sI https://$DOMAIN/api/auth/me/ | grep -i cache-control                               # no-store
curl -s -o /dev/null -w 'privacy: %{http_code}\n' https://$DOMAIN/privacy/                  # 200
curl -s -o /dev/null -w 'admin: %{http_code}\n' https://$DOMAIN/admin/                      # 401 (basic auth), as before
```

**Web login with the cookie** (use a **test** account; the login endpoint is limited to 10 tries per minute):
```bash
read -rp "test username: " U; read -rsp "password: " P; echo
J=$(mktemp)
curl -s -c "$J" -H "X-Axon-Client: web" -H "Origin: https://$DOMAIN" -H "Content-Type: application/json" \
     -d "{\"username\":\"$U\",\"password\":\"$P\"}" https://$DOMAIN/api/auth/login/ | head -c 120; echo
grep -c "axon_refresh" "$J"; grep "axon_refresh" "$J" | cut -c1-12           # 1, then "#HttpOnly_ax"
curl -s -b "$J" -c "$J" -X POST -H "X-Axon-Client: web" -H "Origin: https://$DOMAIN" https://$DOMAIN/api/auth/refresh/ | head -c 60; echo
curl -s -o /dev/null -w 'foreign origin (expect 403): %{http_code}\n' -b "$J" -X POST -H "X-Axon-Client: web" -H "Origin: https://evil.example" https://$DOMAIN/api/auth/refresh/
curl -s -b "$J" -c "$J" -X POST -H "X-Axon-Client: web" -H "Origin: https://$DOMAIN" https://$DOMAIN/api/auth/logout/; echo
# native app flow is unchanged: no header -> "refresh" still in the body, no cookie
curl -s -H "Content-Type: application/json" -d "{\"username\":\"$U\",\"password\":\"$P\"}" https://$DOMAIN/api/auth/login/ | grep -o '"refresh"'
rm -f "$J"; unset P
```
**OK:** login prints `{"access":"...` with **no** `"refresh"`, the cookie line starts with `#HttpOnly_`,
refresh prints `{"access":"...`, the foreign origin gets 403, logout prints `{}`, and the last
(native) login prints `"refresh"`.

**ffmpeg conversion of a Safari-style recording** (fragmented MP4; no database access):
```bash
ffmpeg -v error -y -f lavfi -i sine=frequency=440:duration=3 -c:a aac -movflags frag_keyframe+empty_moov+default_base_moof -f mp4 /tmp/axon-frag.m4a
PY shell -c "from chat.voice import transcode_to_m4a, aac_duration_seconds, ffmpeg_path; d=open('/tmp/axon-frag.m4a','rb').read(); print('seconds:', round(aac_duration_seconds(transcode_to_m4a(d, 'mov', ffmpeg_path())), 1))"
rm -f /tmp/axon-frag.m4a
```
**OK:** `seconds: 3.0`.

**Push from the server works** (after A1; read-only DB query, then one test notification to one user):
```bash
PY shell -c "from notifications.models import DeviceToken as T; print({p: T.objects.filter(platform=p).count() for p in ('android','ios','web')})"
```
(The `web` count becomes 1 or more after D6.)

---

## Part D: manual test on a real iPhone (iOS 16.4 or newer)

You need: one iPhone with iOS ≥ 16.4, a **patient** test account with an open case, the **doctor** of that case
(on Android or another device), and an Android phone with the current Axon APK. Note iOS version and model for each finding.

### D1. Safari, not installed
1. Open **Safari** → `https://axon.tera-software1.com/app/`.
   **Expect:** dark loading screen with the Axon logo and a moving teal bar, then the Arabic screen
   **"ثبّت Axon على iPhone"** with 3 numbered steps (right to left) and the warning that notifications only work after installing.
2. Arabic text appears immediately in the app font, with no boxes and no font "jump".
3. Tap **"المتابعة في المتصفح بدون إشعارات"** → login screen. Log in as the patient.
   **Expect:** home screen, and an orange banner at the top: "ثبّت التطبيق على الشاشة الرئيسية لتصلك الإشعارات." with **"كيف؟"**.
   Only if A1 is done. Without the Firebase web config, no banner is expected.
4. Tap **"كيف؟"** → the install screen again → continue in the browser.
5. Pull down to reload the page. **Expect:** still logged in (no login screen). This is the HttpOnly cookie restoring the session.

### D2. Add to Home Screen
6. Safari → **Share** button → scroll → **Add to Home Screen**. **Expect:** name "Axon" and the gold brain logo on black. Tap **Add**.
7. Open **Axon from the Home Screen**. **Expect:** full screen with no Safari bars, no install screen, and the **login screen**
   (the installed app has its own storage, so you sign in once more; this is expected).

### D3. Login and staying logged in
8. Log in as the patient. **Expect:** patient home.
9. Swipe Axon away in the app switcher, then reopen it. **Expect:** still logged in.
10. Leave the app for more than **30 minutes** (the access token expires), then open it and open a case.
    **Expect:** it works without a login screen (silent refresh via the cookie).
11. Settings → **Log out** → login screen. Close and reopen the app. **Expect:** still logged out.
    Log in again for the next steps.

### D4. Notifications (needs A1)
12. Right after login in the installed app: popup **"فعّل الإشعارات"**. Tap **"تفعيل الإشعارات"**.
    **Expect:** the iOS permission dialog → **Allow**. The popup and the orange banner disappear.
    Settings in the app shows **"الإشعارات مفعّلة"**.
13. On the server, run the `DeviceToken` count from Part C. **Expect:** `web` is 1 or more.
14. **Test notification from the server** (replace the username):
    ```bash
    PY shell -c "from accounts.models import User; from notifications.services import send_push_to_users; send_push_to_users([User.objects.get(username='PATIENT_TEST_USERNAME')], title='اختبار', body='إشعار تجريبي من الخادم', data={'type': 'test'})"
    ```
    The command prints a log line like `إشعار FCM: نجح 1 من 1 توكن` in the terminal (N of M devices reached).
    With the app **closed** (swiped away) and the phone locked: **Expect:** a notification "اختبار / إشعار تجريبي من الخادم" with the Axon icon.
15. **Real message, app closed:** lock the iPhone. From the doctor account, send a text message in the patient's case chat.
    **Expect:** within seconds, the notification "رسالة جديدة / لديك رسالة جديدة".
16. **Tap that notification.** **Expect:** Axon opens directly on that case's chat, and the message is there.
17. **App open in another screen:** send another message from the doctor. **Expect:** the unread badge or chat updates
    immediately. A notification banner may also show; that's by design, because iOS requires every push to be displayed.
18. **"Not now" and "denied" paths** (optional, needs resetting permission): iPhone Settings → Notifications → Axon → off,
    then reopen Axon. **Expect:** the orange banner "الإشعارات محظورة. فعّلها من إعدادات iPhone ← الإشعارات ← Axon."
    Turn it back on in Settings, return to Axon, and **expect** the banner to disappear.

### D5. Voice notes from Safari (confirms the fragmented-MP4 fix)
19. In the installed app, open the patient's chat → tap the **microphone**.
    **Expect:** the iOS microphone permission dialog (first time) → Allow → recording timer runs.
20. Record about **5 seconds** → **Send**. **Expect:** the voice bubble appears with a duration of about **0:05**,
    **not** the error "الرسالة الصوتية فارغة" and not "صيغة الرسالة الصوتية غير مدعومة".
21. On the server, confirm it was converted and stored as AAC m4a:
    ```bash
    sudo journalctl -u axon --since "10 min ago" --no-pager | grep -c "تعذّر تحويل"        # 0
    F=$(sudo ls -t /var/www/axon/private/voice/$(date +%Y/%m)/ | head -1); echo "$F"
    sudo ffmpeg -hide_banner -i "/var/www/axon/private/voice/$(date +%Y/%m)/$F" 2>&1 | grep -E "Duration|Audio"
    ```
    **Expect:** a `.m4a` file, `Duration: 00:00:05...`, and `Audio: aac (LC) ... mono`.
22. **Play it on the iPhone:** tap ▶ on your own note. Note whether it **plays on the first tap**
    (expected), or shows a spinner and then needs a **second tap** (acceptable fallback; please report which).
    The sound should come from the **loudspeaker**, not the earpiece.
23. Record one of **2 minutes**. **Expect:** it stops automatically at 2:00 and sends.
24. Microphone prompt: close and reopen the app, then record again. Note whether iOS asks for the microphone again.
    That's known iOS behavior for Home Screen apps; just report it.

### D6. Cross-device playback
25. **iPhone → Android:** on the Android phone (current APK), log in as the doctor → the patient's chat → play the
    iPhone note from D5. **Expect:** it plays with the right duration.
26. **Android → iPhone:** the doctor records a voice note on Android. On the iPhone, play it.
    **Expect:** it plays (first tap, or second tap as in step 22).
27. Optional: the doctor uses the web app in **Chrome on a PC** (`/app/`) and sends a voice note.
    **Expect:** iPhone and Android both play it. Chrome may record WebM/Opus, and the server converts it.

### D7. Other checks
28. **Closed case:** for a closed case, open its chat. **Expect:** messages are readable and there's no input field.
29. **Offline:** turn on airplane mode → open Axon. **Expect:** the "couldn't reach the server" screen with a retry button,
    not a login screen. Turn airplane mode off → tap retry → home.
30. **Staff in English:** log in as a doctor on the iPhone web app. **Expect:** English left-to-right screens
    (as in the Android app), and the notification popup and banner in English.
31. **Android regression (existing APK):** log in, open a case, send text and voice, receive a push. **Expect:** exactly as before.

### D8. Content-Security-Policy check (needs a Mac; optional but recommended)
32. iPhone: Settings → Safari → Advanced → **Web Inspector: on**. Connect the iPhone to a Mac with a cable.
    Mac Safari → Settings → Advanced → "Show features for web developers". Then **Develop** menu → your iPhone →
    the Axon page. Open the **Console** and repeat steps 8, 12, 15–16 and 19–22.
    **Expect:** no messages containing `Content-Security-Policy`. If there are some, send them to me
    before doing E1.

---

## Part E: after testing (things that depend on you)

E1. **Enforce the CSP** once D8 shows no violations: in `/etc/nginx/snippets/axon-web-headers.conf`, change
`Content-Security-Policy-Report-Only` to `Content-Security-Policy`. Also change it in `deploy/nginx-axon-web-headers.conf`
in the repo and commit. Then `sudo nginx -t && sudo systemctl reload nginx` and repeat D3 and D5 quickly.

E2. **Raise HSTS** when everything is stable (unchanged from before this release): `SECURE_HSTS_SECONDS=31536000` in
`/etc/axon/axon.env`, then `sudo systemctl restart axon`.

E3. **Tell iPhone users** the address `https://axon.tera-software1.com/app/` and that they need iOS 16.4+ and must
"Add to Home Screen" for notifications. Clinic staff should help the first time.

E4. **Each future web release:** `git push` → on the PC `bash tool/build_web.sh` → `scp` the tarball → B5 (new
timestamp folder, swap the symlink) → C (first block). No nginx change and no restart needed, unless the backend changed too.
Users get the new version the next time they open the app.

E5. **Cleanup a few days after a good deploy:** `sudo rm -rf /var/backups/axon-release-web`, and remove old folders
in `/var/www/axon/web-releases/` except the current one and the previous one.

E6. **If you later build a new Android APK from this code:** the native voice and token-storage code was refactored
(same behavior, covered by tests, and the debug APK builds). Before publishing it, run the D7 step 31 checks with the new APK.

E7. **Push and migration status reminders:** without `web_firebase.json` the web app has no notifications. After
adding it later, repeat A3, A4, B5 and D4.

E8. **Not part of this release** (documented in `PWA_FEASIBILITY_REPORT.md`): offline caching of the app shell,
splitting the app into smaller downloads (deferred loading), and the iOS limits that can't be fixed on the web
(no notifications before installing, the microphone prompt may repeat, separate login for Safari and the Home Screen app).

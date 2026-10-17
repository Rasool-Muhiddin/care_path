# Runbook: voice messages + closed-case chat release

Deploys everything on `main` after the server's current commit:

- `c3c2317` Add voice messages to chat (all channels and roles)
- the follow-up commit "Chat: hide the input on closed cases" (it contains this file)

Only one migration: `chat.0006_voice_messages`. No new Python packages.
The voice features only appear for users once they install the new app build.
Old app builds keep working for text.

Run as `ubuntu` in one terminal session. If the session drops, run **step 0 again** before continuing.
Do not touch `pharmacy-backend.service` or `pharmacy_backend_db`. Nothing below does.

> **Downtime note.** From `git pull` until the restart (steps 4–13), the code on disk, the DB
> schema and the running gunicorn disagree. gunicorn recycles workers (`max_requests`), and
> the new `audio` column is NOT NULL, so chat requests can fail with 500 in that window.
> The runbook therefore **stops `axon` in step 4** and starts it again in step 13.
> Expect about 10–15 minutes of API downtime, so pick a quiet hour. The pharmacy app is not affected.

---

## Step 0: session setup (re-run in every new shell)

```bash
PY() { sudo bash -c 'set -a; . /etc/axon/axon.env; set +a; cd /var/www/axon/app; exec runuser -u axon -- /var/www/axon/venv/bin/python manage.py "$@"' _ "$@"; }
APP=/var/www/axon/app
REL=/var/backups/axon-release-voice
DOMAIN=axon.tera-software1.com
sudo install -d -m 700 -o root -g root "$REL"
sudo ls -ld "$REL"
```

**OK:** `drwx------ ... root root ... /var/backups/axon-release-voice`. `sudo` asks for your password once.
**If not:** no other step depends on anything except this directory. Fix the `install` error (usually a typo) before going on.

---

## Step 1: pre-flight checks (read-only)

```bash
df -h / /var
sudo -u postgres psql -tAc "SELECT pg_size_pretty(pg_database_size('axon_db'));"
systemctl is-active axon nginx postgresql pharmacy-backend
sudo -u axon git -C "$APP" log --oneline -1
sudo -u axon git -C "$APP" status --porcelain
sudo -u axon git -C "$APP" fetch origin
sudo -u axon git -C "$APP" log --oneline HEAD..origin/main
sudo -u axon git -C "$APP" diff --stat HEAD origin/main -- requirements.txt '*/migrations/*'
sudo test -e "$REL/PREV_COMMIT" || sudo -u axon git -C "$APP" rev-parse HEAD | sudo tee "$REL/PREV_COMMIT"
sudo cat "$REL/PREV_COMMIT"
```

**OK:**
- `df`: several GB free on `/var`, and at least 3× the DB size printed by the `pg_size_pretty` line.
- `is-active` prints four lines of `active`. Note the pharmacy line for step 16.
- `log -1` shows the commit the server runs now, e.g. `71074d1 Use "Supervising Engineer" label; ...`.
- `status --porcelain` prints **nothing**.
- `HEAD..origin/main` lists exactly the two commits above (newest first).
- The `diff --stat` shows only `chat/migrations/0006_voice_messages.py` (requirements.txt unchanged).
- `PREV_COMMIT` holds the full hash of the current commit. This is your rollback target.

**If not:**
- Low disk: free space first. Stop here.
- A service is not `active`: investigate it before deploying. Do not deploy on top of a broken state.
- `status --porcelain` lists files: someone changed files on the server. **Stop.** Run
  `sudo -u axon git -C "$APP" diff` and decide. Do not pull over unknown edits.
- `HEAD..origin/main` shows other commits too: the server is further behind than expected.
  Stop and review what those commits need before continuing.

---

## Step 2: backups (DB, nginx site, axon.env, backup script)

`cp -n` and the `sudo test -s` guard never overwrite a backup that already exists, so re-running is safe.

```bash
sudo test -s "$REL/axon_db.dump" || sudo -u postgres pg_dump -Fc -d axon_db | sudo tee "$REL/axon_db.dump" >/dev/null
sudo pg_restore -l "$REL/axon_db.dump" | grep -c "TABLE DATA"
sudo cp -n -a /etc/nginx/sites-available/axon "$REL/nginx-axon.bak"
sudo cp -n -a /etc/axon/axon.env "$REL/axon.env.bak"
sudo cp -n -a /usr/local/bin/axon-backup.sh "$REL/axon-backup.sh.bak"
sudo ls -l "$REL"
```

**OK:**
- The `grep -c` prints a number greater than 20 (one line per table with data).
- `ls -l` shows `PREV_COMMIT`, `axon_db.dump` (non-zero size, roughly the DB size or smaller), `nginx-axon.bak`, `axon.env.bak` and `axon-backup.sh.bak`.

**If not:**
- `pg_dump` errors, or the dump is 0 bytes: delete it with `sudo rm "$REL/axon_db.dump"`, fix the cause (disk, typo), and re-run. **Never continue without a valid dump.**

---

## Step 3: check that the server-side files match the repo (read-only)

```bash
sudo diff /usr/local/bin/axon-backup.sh "$APP/deploy/backup_db.sh" && echo "backup script == repo"
sudo grep -nE '^(BACKUP_DIR|KEEP_DAYS|STAMP)=' /usr/local/bin/axon-backup.sh
sudo grep -nE 'server \{|listen |location ' /etc/nginx/sites-available/axon
```

**OK:**
- `backup script == repo`.
- Three variable lines:
  - `BACKUP_DIR=/var/backups/axon`
  - `KEEP_DAYS=14`
  - `STAMP=$(date -u +%Y%m%d-%H%M%S)`
- The nginx listing shows a `server {` block containing `listen 443 ssl` (added by certbot) with `location /static/`, `location /media/`, `location = /api/auth/login/`, `location /admin/` and `location /`. The certbot redirect block for port 80 usually follows at the end. `location /media/` appears **exactly once**.

**If not:**
- The backup script differs, or a variable name is different: step 15 uses `$BACKUP_DIR`, `$STAMP` and `$KEEP_DAYS`. Adapt those three names to what your script uses (or send me the `diff`).
- `location /media/` appears twice (one per server block): in step 12, insert the new block by hand into the block with `listen 443 ssl`.

---

## Step 4: stop axon (start of the downtime window)

```bash
sudo systemctl stop axon
systemctl is-active axon; systemctl is-active pharmacy-backend
```

**OK:** `inactive` for axon, then `active` for pharmacy.
**If not:** if axon won't stop, check `sudo journalctl -u axon -n 50 --no-pager`.
Do not continue while it is half-running. To abort now, run `sudo systemctl start axon`; nothing has changed yet.

---

## Step 5: git pull

```bash
sudo -u axon git -C "$APP" status --porcelain
sudo -u axon git -C "$APP" pull --ff-only origin main
sudo -u axon git -C "$APP" log --oneline -3
```

**OK:**
- `status` prints nothing.
- `pull` says `Fast-forward` and lists files, including `chat/voice.py` and `chat/migrations/0006_voice_messages.py`.
- `log` shows the closed-case commit on top, then `c3c2317`, then your previous commit.

**If not:**
- `Not possible to fast-forward`, or there are local changes: **stop**. Run `sudo systemctl start axon`.
  The tree is unchanged, so investigate with `git status` / `git log HEAD..origin/main`.
- Authentication errors: the deploy key or credentials for `axon` are the problem (see SERVER_SETUP.md step 4). Start axon again while you fix it.

---

## Step 6: pip install

```bash
sudo -u axon /var/www/axon/venv/bin/pip install -r "$APP/requirements.txt"
```

**OK:** every line says `Requirement already satisfied` (no new packages in this release).
**If not:** a network error means retry. An install error means **roll back** (step 17, code part only:
`git reset --hard` to PREV_COMMIT, then `sudo systemctl start axon`). The DB is untouched so far.

---

## Step 7: private voice directory

```bash
sudo mkdir -p /var/www/axon/private/voice
sudo chown -R axon:www-data /var/www/axon/private
sudo chmod 2750 /var/www/axon/private /var/www/axon/private/voice
stat -c '%a %U:%G %n' /var/www/axon /var/www/axon/private /var/www/axon/private/voice
sudo -u axon touch /var/www/axon/private/voice/.write_test && sudo -u axon rm /var/www/axon/private/voice/.write_test && echo "axon can write"
sudo -u www-data ls -la /var/www/axon/private/voice >/dev/null && echo "nginx (www-data) can read"
sudo -u nobody ls /var/www/axon/private 2>&1 | head -1
```

**OK:**

```
755 axon:www-data /var/www/axon
2750 axon:www-data /var/www/axon/private
2750 axon:www-data /var/www/axon/private/voice
axon can write
nginx (www-data) can read
ls: cannot open directory '/var/www/axon/private': Permission denied
```

The last line is expected: other users cannot read voice notes.

**If not:**
- `/var/www/axon` not 755: nginx can't traverse it (but `/static/` would already be broken, so check first).
- A failed write/read test: re-run the `chown`/`chmod` lines. No restart is needed for this step.

---

## Step 8: env variables (idempotent)

```bash
sudo sed -i -e '$a\' /etc/axon/axon.env
for kv in VOICE_NOTES_ROOT=/var/www/axon/private/voice VOICE_NOTES_X_ACCEL_PREFIX=/_protected/voice/; do
  k=${kv%%=*}
  if sudo grep -q "^${k}=" /etc/axon/axon.env; then
    echo "already set: $(sudo grep "^${k}=" /etc/axon/axon.env)   (expected: $kv)"
  else
    echo "$kv" | sudo tee -a /etc/axon/axon.env >/dev/null && echo "added: $kv"
  fi
done
sudo grep -n '^VOICE_' /etc/axon/axon.env
sudo stat -c '%a %U:%G %n' /etc/axon/axon.env
PY shell -c "from django.conf import settings as s; print(s.VOICE_NOTES_ROOT, s.VOICE_NOTES_X_ACCEL_PREFIX)"
```

**OK:**
- The first run prints `added: ...` twice. A second run prints `already set: ...` twice.
- `grep` shows **exactly two** `VOICE_` lines.
- `stat` shows `640 root:axon` (unchanged).
- The last line prints `/var/www/axon/private/voice /_protected/voice/`.

**If not:**
- More than two `VOICE_` lines, or an `already set` value that differs from expected: edit with
  `sudo nano /etc/axon/axon.env` so each key appears once with the expected value.
- `PY` prints something else: the env file isn't loaded. Check the `PY` definition (step 0).

---

## Step 9: pre-migration data check

The new constraint requires every existing message to have non-empty text.

```bash
sudo -u postgres psql -d axon_db -tAc "SELECT count(*) FROM chat_chatmessage WHERE text = '';"
```

**OK:** `0`.
**If not:** **stop before migrating.** List the rows with
`sudo -u postgres psql -d axon_db -c "SELECT id, case_id, sender_id, created_at FROM chat_chatmessage WHERE text = '';"`
and decide: delete them, or give them placeholder text. Then re-run this check.
Nothing has changed in the DB yet. To abort: run the code rollback (step 17: env/code parts), then `sudo systemctl start axon`.

---

## Step 10: showmigrations, then migrate

```bash
PY showmigrations chat
PY migrate --plan
PY migrate
PY showmigrations chat | tail -2
```

**OK:**
- Before: `[X] 0001_initial` … `[X] 0005_sender_set_null` and `[ ] 0006_voice_messages`.
- `--plan` lists **only** `chat.0006_voice_messages` (add fields audio/duration_seconds, alter text, add constraint).
- `migrate` prints `Applying chat.0006_voice_messages... OK`.
- After: `[X] 0006_voice_messages`.

**If not:**
- `--plan` lists other apps: stop. Something else is pending that this runbook doesn't cover.
- `migrate` fails: PostgreSQL runs the migration in one transaction, so the schema is unchanged.
  Read the error (an IntegrityError on `chat_message_text_xor_voice` means step 9 was skipped or the data changed).
  Fix it and re-run, or roll back the code (step 17) and start axon.

---

## Step 11: makemigrations check, collectstatic, check --deploy

```bash
PY makemigrations --check --dry-run
PY collectstatic --noinput
PY check --deploy
```

**OK:**
- `No changes detected`.
- `0 static files copied to '/var/www/axon/static', N unmodified.` (a few copied files is also fine).
- `System check identified no issues (0 silenced).` Warnings that you already had before this release are acceptable.

**If not:**
- `makemigrations` reports changes: don't create migrations on the server. Stop and tell me; it means the code and migrations disagree.
- `check --deploy` shows **errors** (`E…`): stop and fix the env, or roll back. New warnings: note them and decide.

---

## Step 12: nginx (add the internal voice location)

In the repo's `deploy/nginx-axon.conf`, the server block holds these locations, in order:
`location /static/`, `location /media/`, `location = /api/auth/login/`, `location /admin/`, `location /`.
On the server, certbot turned that block into the `listen 443 ssl` block.
The new block goes **inside that same server block, right after the closing `}` of `location /media/ { … }`**
and before `location = /api/auth/login/`:

```nginx
    # Chat voice notes (private medical files). "internal": never reachable from outside.
    # Django checks access in /api/chat/messages/<id>/audio/ and answers with
    # X-Accel-Redirect: /_protected/voice/<file>, then nginx serves the file.
    location /_protected/voice/ {
        internal;
        alias /var/www/axon/private/voice/;
        add_header X-Content-Type-Options "nosniff" always;
    }
```

Insert it with this script. It does nothing if the block is already there, and refuses to edit unless there is exactly one `location /media/`:

```bash
sudo python3 - <<'PYEOF'
import re, sys
p = '/etc/nginx/sites-available/axon'
s = open(p, encoding='utf-8').read()
if '/_protected/voice/' in s:
    sys.exit('Already present - nothing changed.')
lines = s.split('\n')
starts = [i for i, l in enumerate(lines) if re.match(r'\s*location\s+/media/\s*\{', l)]
if len(starts) != 1:
    sys.exit(f'Found {len(starts)} "location /media/" blocks - insert by hand into the "listen 443 ssl" block.')
end = next(i for i in range(starts[0] + 1, len(lines)) if lines[i].strip() == '}')
block = '''
    # Chat voice notes (private medical files). "internal": never reachable from outside.
    # Django checks access in /api/chat/messages/<id>/audio/ and answers with
    # X-Accel-Redirect: /_protected/voice/<file>, then nginx serves the file.
    location /_protected/voice/ {
        internal;
        alias /var/www/axon/private/voice/;
        add_header X-Content-Type-Options "nosniff" always;
    }'''
lines[end + 1:end + 1] = block.split('\n')
open(p, 'w', encoding='utf-8').write('\n'.join(lines))
print(f'Inserted after line {end + 1}.')
PYEOF
sudo diff -u "$REL/nginx-axon.bak" /etc/nginx/sites-available/axon
sudo grep -nE 'server \{|listen |location ' /etc/nginx/sites-available/axon
sudo nginx -t && sudo systemctl reload nginx && echo "nginx reloaded"
```

**OK:**
- `Inserted after line N.`
- The `diff` shows only the 9 added lines, right after the `/media/` block.
- The listing shows `location /_protected/voice/` between `location /media/` and `location = /api/auth/login/`, in the block that has `listen 443 ssl`.
- `nginx -t` says `syntax is ok` and `test is successful`, then `nginx reloaded` prints.

**If not:**
- `nginx -t` fails: the `&&` chain means **nothing was reloaded** and all sites, pharmacy included, keep running the old config.
  Restore with `sudo cp -a "$REL/nginx-axon.bak" /etc/nginx/sites-available/axon && sudo nginx -t`, then fix and retry.
- The script refused (two `/media/` blocks): open `sudo nano /etc/nginx/sites-available/axon`, paste the block after
  `location /media/ { … }` inside the `listen 443 ssl` block only, then run the last three commands.

---

## Step 13: start axon (end of the downtime window)

```bash
sudo systemctl restart axon
sleep 3
systemctl status axon --no-pager | head -12
sudo journalctl -u axon --since "-3 min" --no-pager | tail -30
```

**OK:**
- `Active: active (running)`.
- The journal shows gunicorn `Listening at: unix:/run/axon/gunicorn.sock` and `Booting worker` lines, with **no** `Traceback`.

**If not:** read the traceback. Env or permission errors: fix them and restart. Anything unclear: **roll back (step 17)**.

---

## Step 14: post-deploy checks

```bash
curl -s -o /dev/null -w 'me (expect 401): %{http_code}\n'          https://$DOMAIN/api/auth/me/
curl -s -o /dev/null -w 'privacy (expect 200): %{http_code}\n'     https://$DOMAIN/privacy/
curl -s -o /dev/null -w 'deletion (expect 200): %{http_code}\n'    https://$DOMAIN/account-deletion/
curl -s -o /dev/null -w 'protected (expect 404): %{http_code}\n'   https://$DOMAIN/_protected/voice/test.m4a
curl -s -o /dev/null -w 'audio anon (expect 401): %{http_code}\n'  https://$DOMAIN/api/chat/messages/1/audio/
```

**OK:** exactly the codes in parentheses.

**If not:**
- 502 everywhere: gunicorn isn't up. Go back to step 13.
- `protected` returns 200 or 403: the `internal;` line is missing or in the wrong block. Fix step 12.
- `audio anon` returns 404: the server isn't running the new code (check `git log -1` and restart).

### Voice note end-to-end test (needs the new app build)

1. On a phone with the new build, log in as a test patient. Open the chat (medical), tap 🎤, speak ~5 s, then tap send.
2. Log in as that case's doctor (second phone, or log out and in). Open the chat and press play on the voice bubble.
3. On the server:

```bash
sudo find /var/www/axon/private/voice -type f -mmin -30 -printf '%m %u:%g %s %p\n'
sudo find /var/www/axon/private/voice -mindepth 1 -type d -printf '%m %u:%g %p\n'
sudo -u postgres psql -d axon_db -c "SELECT id, case_id, inquiry_type, duration_seconds, audio FROM chat_chatmessage WHERE audio <> '' ORDER BY id DESC LIMIT 3;"
sudo tail -5 /var/log/nginx/error.log
```

**OK:**
- The file line looks like `640 axon:www-data 41234 /var/www/axon/private/voice/2026/10/<random>.m4a`.
- Directories show `2750` (or `750`) with group `www-data`.
- The DB row has `duration_seconds` ≈ 5 and `audio` = `2026/10/<random>.m4a`.
- The doctor hears the note.
- No new `permission denied` lines in the nginx error log.

**If not:**
- Sending fails with "صيغة ... غير مدعومة": the app build is old or the recorder produced another format. Send me the message.
- Playback fails and the nginx error log says `Permission denied`: re-run step 7.
- Playback fails with 404 while the file exists: compare `VOICE_NOTES_X_ACCEL_PREFIX` (step 8) with the nginx `location` (step 12). They must both be `/_protected/voice/`.
- Closed-case check (optional): close a test case in the doctor app. The chat input is replaced by the closed-case notice within ~8 s.

---

## Step 15: backup script: include voice files

The variables come from `deploy/backup_db.sh` and were checked in step 3. The added lines are idempotent (they are not appended twice).

```bash
if sudo grep -q 'voice-\$STAMP' /usr/local/bin/axon-backup.sh; then
  echo "voice backup already in script"
else
sudo tee -a /usr/local/bin/axon-backup.sh >/dev/null <<'EOF'

# Chat voice notes (not in pg_dump). Same retention as the DB dumps, so
# audio of deleted patients also leaves the backups after KEEP_DAYS.
VOICE_PARENT=/var/www/axon/private
if [ -d "$VOICE_PARENT/voice" ]; then
  tar -C "$VOICE_PARENT" -cf "$BACKUP_DIR/voice-$STAMP.tar" voice
  tar -tf "$BACKUP_DIR/voice-$STAMP.tar" >/dev/null
  echo "voice backup ok: $BACKUP_DIR/voice-$STAMP.tar"
fi
find "$BACKUP_DIR" -name 'voice-*.tar' -mtime +"$KEEP_DAYS" -delete
EOF
fi
sudo bash -n /usr/local/bin/axon-backup.sh && echo "syntax ok"
sudo diff "$REL/axon-backup.sh.bak" /usr/local/bin/axon-backup.sh
sudo systemctl start axon-backup.service
systemctl status axon-backup.service --no-pager | head -8
sudo journalctl -u axon-backup.service --since "-5 min" --no-pager | tail -5
sudo ls -lt /var/backups/axon | head -5
sudo tar -tvf "$(sudo ls -t /var/backups/axon/voice-*.tar | head -1)" | head
```

**OK:**
- `syntax ok`.
- The `diff` shows only the added lines.
- The status shows `status=0/SUCCESS` (the unit is oneshot, so `inactive (dead)` afterwards is normal).
- The journal shows `backup ok: …sql.gz` and `voice backup ok: …/voice-YYYYMMDD-HHMMSS.tar`.
- `ls` lists the new `voice-*.tar` (mode `-rw-------`, owner `axon`).
- `tar -tvf` lists `voice/`, `voice/2026/10/…m4a`.

**If not:**
- `tar: Cannot open: Permission denied`: the backup runs as `axon`, which owns the voice dir. Re-run step 7.
- Anything else: restore with `sudo cp -a "$REL/axon-backup.sh.bak" /usr/local/bin/axon-backup.sh`. The DB backup keeps working as before.
- The tar files sit on the same disk as the data. Copying `/var/backups/axon` off the server occasionally protects against disk loss.

---

## Step 16: confirm the pharmacy app is untouched

```bash
systemctl is-active pharmacy-backend
systemctl status pharmacy-backend --no-pager | head -5
sudo journalctl -u pharmacy-backend --since "-60 min" -p err --no-pager | tail -5
sudo nginx -t
```

**OK:**
- `active`, with the same `Active: … since <time>` as before the deploy (it was never restarted).
- No error lines (or only errors you already had before).
- `nginx -t` is OK.

**If not:** this release did not touch pharmacy files, its service or its DB. The only shared action was `systemctl reload nginx`.
If pharmacy's site misbehaves, restore the nginx file from step 2 and reload; that is enough to rule this release out.

---

## Step 17: full rollback (only if needed)

Restores everything to the pre-deploy state.
**Data written after step 2 is lost:** messages, sessions and anything else created in the meantime.
Decide quickly if you need it.

```bash
# (run step 0 first if this is a new shell)
PREV=$(sudo cat "$REL/PREV_COMMIT"); echo "rolling back to $PREV"
sudo systemctl stop axon

# 1. Database: restore the pre-deploy dump (as postgres; owners stay axon_user)
sudo cat "$REL/axon_db.dump" | sudo -u postgres pg_restore --clean --if-exists --single-transaction -d axon_db
sudo -u postgres psql -d axon_db -tAc "SELECT count(*) FROM django_migrations WHERE app='chat' AND name='0006_voice_messages';"

# 2. nginx site file
sudo cp -a "$REL/nginx-axon.bak" /etc/nginx/sites-available/axon
sudo nginx -t && sudo systemctl reload nginx && echo "nginx restored"

# 3. env file and backup script
sudo cp -a "$REL/axon.env.bak" /etc/axon/axon.env
sudo stat -c '%a %U:%G' /etc/axon/axon.env
sudo cp -a "$REL/axon-backup.sh.bak" /usr/local/bin/axon-backup.sh

# 4. code
sudo -u axon git -C "$APP" reset --hard "$PREV"
sudo -u axon git -C "$APP" log --oneline -1
sudo -u axon /var/www/axon/venv/bin/pip install -r "$APP/requirements.txt"
PY collectstatic --noinput

# 5. start and check
sudo systemctl start axon
systemctl status axon --no-pager | head -5
curl -s -o /dev/null -w 'me (expect 401): %{http_code}\n' https://$DOMAIN/api/auth/me/
```

**OK:**
- `pg_restore` prints nothing.
- The migration count query prints `0`.
- `nginx restored`.
- `640 root:axon`.
- `log -1` shows the PREV commit.
- axon is `active (running)` and `/api/auth/me/` returns 401.

**If not:**
- `pg_restore` errors: `--single-transaction` means nothing changed. Make sure axon is stopped (open connections) and retry.
  The daily `*.sql.gz` in `/var/backups/axon` plus `/usr/local/bin/axon-restore.sh` are a second fallback.

**After a rollback:**
- Voice files in `/var/www/axon/private/voice` are now orphaned private data.
  Once the rollback is final, delete them: `sudo rm -rf /var/www/axon/private`.
- Users with the new app build can still send text. Voice sends will show an error until the release is re-deployed.

---

## Cleanup (a few days after a successful deploy)

```bash
sudo rm -rf /var/backups/axon-release-voice
```

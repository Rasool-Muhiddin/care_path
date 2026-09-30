#!/usr/bin/env bash
# /usr/local/bin/axon-backup.sh  — نسخة احتياطية يومية لقاعدة PostgreSQL
# يقرأ بيانات الاتصال من /etc/axon/axon.env . يحتفظ بآخر 14 نسخة.
set -euo pipefail

ENV_FILE=/etc/axon/axon.env
BACKUP_DIR=/var/backups/axon
KEEP_DAYS=14

set -a; source "$ENV_FILE"; set +a
mkdir -p "$BACKUP_DIR"
umask 077

STAMP=$(date -u +%Y%m%d-%H%M%S)
OUT="$BACKUP_DIR/axon-$STAMP.sql.gz"

PGPASSWORD="$DB_PASSWORD" pg_dump \
  -h "${DB_HOST:-127.0.0.1}" -p "${DB_PORT:-5432}" -U "$DB_USER" \
  --no-owner --clean --if-exists "$DB_NAME" | gzip -9 > "$OUT"

# تأكد أن الملف سليم وغير فارغ
gzip -t "$OUT"
[ "$(stat -c%s "$OUT")" -gt 1024 ] || { echo "backup too small: $OUT" >&2; exit 1; }

# حذف ما هو أقدم من KEEP_DAYS
find "$BACKUP_DIR" -name 'axon-*.sql.gz' -mtime +"$KEEP_DAYS" -delete
echo "backup ok: $OUT"

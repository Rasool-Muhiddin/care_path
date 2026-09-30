#!/usr/bin/env bash
# استرجاع نسخة:  sudo /usr/local/bin/axon-restore.sh /var/backups/axon/axon-YYYYMMDD-HHMMSS.sql.gz
# تحذير: يستبدل محتوى القاعدة الحالية بالكامل.
set -euo pipefail
FILE="${1:?usage: axon-restore.sh <backup.sql.gz>}"
[ -f "$FILE" ] || { echo "file not found: $FILE" >&2; exit 1; }

set -a; source /etc/axon/axon.env; set +a
read -r -p "سيتم استبدال قاعدة $DB_NAME بالكامل من $FILE . اكتب YES للمتابعة: " ANS
[ "$ANS" = "YES" ] || { echo "cancelled"; exit 1; }

systemctl stop axon
gunzip -c "$FILE" | PGPASSWORD="$DB_PASSWORD" psql -v ON_ERROR_STOP=1 \
  -h "${DB_HOST:-127.0.0.1}" -p "${DB_PORT:-5432}" -U "$DB_USER" "$DB_NAME"
systemctl start axon
echo "restore ok"

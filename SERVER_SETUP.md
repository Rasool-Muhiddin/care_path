# نشر axon (care_path) على السيرفر المشترك — بالترتيب

الدومين: `axon.tera-software1.com`
مبدأ العزل: كل شيء يخص هذا المشروع باسم `axon` (مستخدم، مجلد، خدمة، socket، قاعدة، ملف nginx).
لا يوجد أي أمر هنا يعدّل مشاريع `gunicorn.service` أو `pharmacy-backend.service` أو قواعد `clinic_db` و`pharmacy_backend_db`،
ولا يحذف موقع nginx الافتراضي، ولا يفعّل جداراً نارياً، ولا يعمل `apt upgrade`.

المشاريع الموجودة (للتذكير): /var/www/pharmacy (gunicorn.sock)، /var/www/pharmacy-backend (/run/pharmacy-backend/pharmacy-backend.sock).
مشروعنا: /var/www/axon  و  /run/axon/gunicorn.sock  و  axon.service  و  axon_db / axon_user.

## 0) فحص قبل أي تغيير (قراءة فقط) — يجب أن تكون كل النتائج "غير موجود"
    id axon 2>&1 | head -1
    ls -d /var/www/axon /etc/axon /run/axon 2>&1
    systemctl list-unit-files | grep -i axon
    sudo -u postgres psql -Atc "select datname from pg_database where datname='axon_db'" -c "select rolname from pg_roles where rolname='axon_user'"
    sudo grep -rn "axon" /etc/nginx/ 2>/dev/null
    python3 --version            # Django 6.1 يحتاج Python 3.12 أو أحدث
    free -h                      # ذاكرة كافية لعمّالين إضافيين؟
    sudo ufw status verbose
لو ظهر أي شيء يحمل اسم axon قبل أن تبدأ، أوقف وأخبرني.

## 1) الحزم اللازمة فقط (بدون upgrade)
    sudo apt update
    sudo apt -y install python3-venv python3-dev git certbot python3-certbot-nginx
(nginx وPostgreSQL موجودان أصلاً ولا نعيد تثبيتهما. أضف `libpq-dev` فقط إن فشل تثبيت الحزم لاحقاً.)
الجدار الناري: لا تنفذ شيئاً إن كان `ufw` غير مفعّل. وإن كان مفعّلاً فتأكد أن 80 و443 مسموحان (`sudo ufw status`).

## 2) مستخدم ومجلدات المشروع (جديدة كلياً)
    sudo adduser --system --group --home /var/www/axon axon
    sudo usermod -aG www-data axon
    sudo mkdir -p /var/www/axon/{app,static,media} /etc/axon /var/backups/axon
    sudo chown -R axon:www-data /var/www/axon
    sudo chmod 755 /var/www/axon /var/www/axon/static
    sudo chmod 2775 /var/www/axon/media
    sudo chown axon:axon /var/backups/axon
(مستخدم مخصص بدل `ubuntu` يعني أن اختراق هذا المشروع لا يعطي وصولاً لملفات المشاريع الأخرى.)

## 3) قاعدة PostgreSQL جديدة (نفس خادم PostgreSQL الموجود، بأسماء جديدة)
ولّد كلمة مرور وسجّلها: `openssl rand -hex 24`
    sudo -u postgres psql -c "CREATE USER axon_user WITH PASSWORD 'ضع_كلمة_المرور_هنا';"
    sudo -u postgres psql -c "CREATE DATABASE axon_db OWNER axon_user ENCODING 'UTF8';"
لا صلاحيات إضافية للمستخدم الجديد، ولا وصول له لقواعد المشاريع الأخرى.

## 4) الكود من GitHub
    sudo -u axon git clone https://github.com/Rasool-Muhiddin/care_path.git /var/www/axon/app
    sudo -u axon python3 -m venv /var/www/axon/venv
    sudo -u axon /var/www/axon/venv/bin/pip install -r /var/www/axon/app/requirements.txt
(بيئة افتراضية خاصة بالمشروع، لا تشارك حزم المشاريع الأخرى.)
إن كان المستودع خاصاً: أنشئ deploy key للسيرفر (`sudo -u axon ssh-keygen -t ed25519`)، وأضف المفتاح العام في GitHub → Settings → Deploy keys،
واستنسخ بعنوان SSH: `git@github.com:Rasool-Muhiddin/care_path.git`.

## 5) ملف البيئة وFirebase
    sudo cp /var/www/axon/app/.env.example /etc/axon/axon.env
    sudo nano /etc/axon/axon.env        # املأ SECRET_KEY و DB_PASSWORD (باقي القيم جاهزة)
    sudo chown root:axon /etc/axon/axon.env && sudo chmod 640 /etc/axon/axon.env
ولّد SECRET_KEY جديداً (لا تستعمل القديم المرفوع على GitHub):
    /var/www/axon/venv/bin/python -c "from django.core.management.utils import get_random_secret_key as g; print(g())"
ارفع ملف Firebase من جهازك (خارج Git):
    scp axon-f7a96-firebase-adminsdk-*.json USER@SERVER:/tmp/fb.json
    sudo mv /tmp/fb.json /etc/axon/firebase-service-account.json
    sudo chown root:axon /etc/axon/firebase-service-account.json && sudo chmod 640 /etc/axon/firebase-service-account.json

## 6) تهيئة Django
    cd /var/www/axon/app
    sudo -u axon bash -c 'set -a; source /etc/axon/axon.env; set +a; /var/www/axon/venv/bin/python manage.py migrate'
    sudo -u axon bash -c 'set -a; source /etc/axon/axon.env; set +a; /var/www/axon/venv/bin/python manage.py collectstatic --noinput'
    sudo -u axon bash -c 'set -a; source /etc/axon/axon.env; set +a; /var/www/axon/venv/bin/python manage.py createsuperuser'
    sudo -u axon bash -c 'set -a; source /etc/axon/axon.env; set +a; /var/www/axon/venv/bin/python manage.py check --deploy'

## 7) gunicorn عبر systemd (خدمة جديدة باسم axon)
    sudo cp /var/www/axon/app/deploy/axon.service /etc/systemd/system/axon.service
    sudo systemctl daemon-reload && sudo systemctl enable --now axon
    sudo systemctl status axon --no-pager
    sudo journalctl -u axon -n 50 --no-pager
تحقق أن socket المشروعين الآخرين لم يتأثرا: `sudo systemctl is-active gunicorn pharmacy-backend` (يجب: active active).

## 8) nginx (ملف مستقل، دون لمس الملفات الموجودة)
احتفظ بنسخة احتياطية أولاً:
    sudo cp -a /etc/nginx /etc/nginx.bak-$(date +%F)
    sudo cp /var/www/axon/app/deploy/axon-proxy.conf /etc/nginx/snippets/axon-proxy.conf
    sudo cp /var/www/axon/app/deploy/nginx-axon.conf /etc/nginx/sites-available/axon
    sudo ln -s /etc/nginx/sites-available/axon /etc/nginx/sites-enabled/axon
    sudo nginx -t
إن نجح `nginx -t` فقط:
    sudo systemctl reload nginx        # reload وليس restart: لا يقطع المشاريع الأخرى
إن فشل، احذف الرابط وتراجع فوراً: `sudo rm /etc/nginx/sites-enabled/axon && sudo nginx -t`.
لا تحذف `sites-enabled/default` ولا أي ملف آخر.

ملاحظة Cloudflare: إن كان سجل الدومين Proxied (سحابة برتقالية)، فعدّاد الحد على المعدّل سيرى IP خوادم Cloudflare بدل IP المستخدم.
الحل الأبسط أثناء الاختبار: اجعل السجل DNS only (سحابة رمادية) حتى تنتهي التجربة. وإن أردت Proxied فأخبرني لأضيف إعداد real_ip.
وإذا فعّلت Proxied فاجعل SSL/TLS في Cloudflare على وضع Full (strict) بعد إصدار الشهادة، وإلا ستحدث حلقة إعادة توجيه.

## 9) شهادة HTTPS (للدومين الجديد فقط)
    sudo certbot --nginx -d axon.tera-software1.com -m YOUR_EMAIL --agree-tos --redirect
certbot يعدّل كتلة هذا الدومين فقط. التجديد التلقائي موجود؛ تحقق: `sudo certbot renew --dry-run`.

## 10) النسخ الاحتياطي اليومي (لقاعدة axon_db فقط)
    sudo cp /var/www/axon/app/deploy/backup_db.sh /usr/local/bin/axon-backup.sh
    sudo cp /var/www/axon/app/deploy/restore_db.sh /usr/local/bin/axon-restore.sh
    sudo chmod 755 /usr/local/bin/axon-backup.sh /usr/local/bin/axon-restore.sh
    sudo cp /var/www/axon/app/deploy/axon-backup.service /var/www/axon/app/deploy/axon-backup.timer /etc/systemd/system/
    sudo systemctl daemon-reload && sudo systemctl enable --now axon-backup.timer
    sudo systemctl start axon-backup.service && ls -lh /var/backups/axon
الاسترجاع (يستبدل axon_db كلها ولا يمس غيرها):
    sudo /usr/local/bin/axon-restore.sh /var/backups/axon/axon-YYYYMMDD-HHMMSS.sql.gz
انسخ /var/backups/axon دورياً إلى مكان خارج السيرفر، وجرّب الاسترجاع مرة على قاعدة تجريبية قبل الاعتماد عليه.

## 11) التحقق
    curl -i https://axon.tera-software1.com/api/app-version/latest/?platform=android    # 404 مقبول
    curl -i http://axon.tera-software1.com/api/auth/me/                                  # يحوّل إلى https
    curl -sI https://pharmacy-api.tera-software1.com | head -1                           # المشروع الآخر ما زال يعمل
    curl -sI https://tera-software1.com | head -1
افتح `https://axon.tera-software1.com/admin/`.

## 12) تحديث الكود لاحقاً
    cd /var/www/axon/app && sudo -u axon git pull
    sudo -u axon /var/www/axon/venv/bin/pip install -r requirements.txt
    (ثم migrate و collectstatic كما في الخطوة 6)
    sudo systemctl restart axon

## 13) بعد نجاح الاختبار
ارفع `SECURE_HSTS_SECONDS` في axon.env إلى 31536000 ثم `sudo systemctl restart axon`.
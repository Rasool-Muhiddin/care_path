# /var/www/axon/app/deploy/gunicorn.conf.py
bind = "unix:/run/axon/gunicorn.sock"
workers = 2            # مؤقتاً 2 لأن السيرفر يشغّل مشاريع أخرى؛ ارفعها بعد فحص الذاكرة (free -h)
# gthread: كل عامل يخدم 4 طلبات معاً (2 × 4 = 8). طلبات الـ polling قصيرة
# ومعظم وقتها انتظار لقاعدة البيانات، فالـ threads أرخص من عمّال إضافيين.
worker_class = "gthread"
threads = 4
timeout = 60
graceful_timeout = 30
max_requests = 1000    # إعادة تدوير العمّال دورياً لمنع تسرب الذاكرة
max_requests_jitter = 100
accesslog = "-"
errorlog = "-"
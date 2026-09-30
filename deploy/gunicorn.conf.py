# /var/www/axon/app/deploy/gunicorn.conf.py
bind = "unix:/run/axon/gunicorn.sock"
workers = 2            # مؤقتاً 2 لأن السيرفر يشغّل مشاريع أخرى؛ ارفعها بعد فحص الذاكرة (free -h)
timeout = 60
graceful_timeout = 30
max_requests = 1000    # إعادة تدوير العمّال دورياً لمنع تسرب الذاكرة
max_requests_jitter = 100
accesslog = "-"
errorlog = "-"
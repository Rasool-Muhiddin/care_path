"""
Django settings for axon (care_path) project.

كل ما يختلف بين جهازك المحلي والسيرفر يُقرأ من متغيرات البيئة (.env محلياً،
وملف /etc/axon/axon.env عبر systemd على السيرفر). القيم الافتراضية آمنة
للإنتاج: إن لم تضبط شيئاً يعمل المشروع بوضع DEBUG=False.

للتطوير المحلي ضع في .env:  DEBUG=True
"""

from datetime import timedelta
from pathlib import Path
import os

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent

# تحميل .env من جذر المشروع (إن وُجد). على السيرفر تأتي القيم من systemd.
load_dotenv(BASE_DIR / '.env')


# ---------------------------------------------------------------------------
# دوال مساعدة لقراءة المتغيرات
# ---------------------------------------------------------------------------
def env_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in ('1', 'true', 'yes', 'on')


def env_list(name, default=''):
    raw = os.environ.get(name, default)
    return [item.strip() for item in raw.split(',') if item.strip()]


def env_int(name, default):
    return int(os.environ.get(name, default))


# ---------------------------------------------------------------------------
# الأمان الأساسي
# ---------------------------------------------------------------------------
# الافتراضي False: لو نسيت ضبط المتغير على السيرفر لن يعمل DEBUG بالخطأ.
DEBUG = env_bool('DEBUG', False)

SECRET_KEY = os.environ.get('SECRET_KEY', '')
if not SECRET_KEY:
    if DEBUG:
        # مفتاح تطوير محلي فقط — لا يُستعمل أبداً مع DEBUG=False
        SECRET_KEY = 'dev-only-insecure-key-do-not-use-in-production'
    else:
        raise ImproperlyConfigured(
            'SECRET_KEY غير مضبوط. ولّد مفتاحاً جديداً وضعه في ملف البيئة: '
            'python -c "from django.core.management.utils import '
            'get_random_secret_key as g; print(g())"'
        )

# أسماء النطاقات المسموحة مفصولة بفاصلة، مثال: api.example.com,example.com
ALLOWED_HOSTS = env_list('ALLOWED_HOSTS')
if not ALLOWED_HOSTS:
    if DEBUG:
        ALLOWED_HOSTS = ['*']  # تطوير محلي عبر IP الشبكة
    else:
        raise ImproperlyConfigured(
            'ALLOWED_HOSTS غير مضبوط (مثال: ALLOWED_HOSTS=api.example.com).'
        )

# مطلوب لدخول لوحة الأدمن عبر HTTPS (نفس النطاق مع https://)
CSRF_TRUSTED_ORIGINS = env_list('CSRF_TRUSTED_ORIGINS')


# ---------------------------------------------------------------------------
# التطبيقات والـ Middleware
# ---------------------------------------------------------------------------
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    "rest_framework",
    "rest_framework_simplejwt",
    "corsheaders",
    "accounts",
    "devices",
    'cases',
    'treatments',
    'feedback',
    'chat',
    'app_updates',
    'notifications',
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

AUTH_USER_MODEL = "accounts.User"
ROOT_URLCONF = 'config.urls'


# ---------------------------------------------------------------------------
# Django REST Framework + JWT
# ---------------------------------------------------------------------------
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    # تحديد المعدّل: يحمي تسجيل الدخول من تخمين كلمات المرور. الطلبات غير
    # المسجّلة (login / فحص التحديث) محدودة لكل IP، والمسجّلة لكل مستخدم.
    # الدردشة تعمل بالـ polling فالحد المسجّل مرتفع عمداً.
    "DEFAULT_THROTTLE_CLASSES": (
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ),
    "DEFAULT_THROTTLE_RATES": {
        "anon": os.environ.get('THROTTLE_ANON', '60/min'),
        "user": os.environ.get('THROTTLE_USER', '1200/min'),
    },
    # عدد الـ proxies أمام Django (nginx = 1) ليُقرأ IP العميل الحقيقي
    # من X-Forwarded-For بدل IP الـ proxy نفسه.
    "NUM_PROXIES": env_int('NUM_PROXIES', 1 if not DEBUG else 0) or None,
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=30),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=7),
    "ROTATE_REFRESH_TOKENS": True,
}


# ---------------------------------------------------------------------------
# CORS
# ---------------------------------------------------------------------------
# تطبيقات Flutter على أندرويد/iOS لا تحتاج CORS إطلاقاً (هو قيد متصفحات فقط).
# مسموح للجميع في التطوير فقط؛ في الإنتاج تُحدَّد أصول بعينها إن وُجدت واجهة ويب.
CORS_ALLOW_ALL_ORIGINS = DEBUG
CORS_ALLOWED_ORIGINS = env_list('CORS_ALLOWED_ORIGINS')


TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'


# ---------------------------------------------------------------------------
# قاعدة البيانات
# ---------------------------------------------------------------------------
# DB_ENGINE=sqlite (الافتراضي) -> تطوير محلي بدون أي إعداد إضافي.
# DB_ENGINE=postgres            -> PostgreSQL، والقيم تُقرأ من البيئة.
DB_ENGINE = os.environ.get('DB_ENGINE', 'sqlite').lower()

if DB_ENGINE in ('postgres', 'postgresql'):
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': os.environ['DB_NAME'],
            'USER': os.environ['DB_USER'],
            'PASSWORD': os.environ['DB_PASSWORD'],
            'HOST': os.environ.get('DB_HOST', '127.0.0.1'),
            'PORT': os.environ.get('DB_PORT', '5432'),
            'CONN_MAX_AGE': env_int('DB_CONN_MAX_AGE', 60),
            'CONN_HEALTH_CHECKS': True,
        }
    }
else:
    if not DEBUG:
        raise ImproperlyConfigured(
            'الإنتاج يتطلب PostgreSQL: اضبط DB_ENGINE=postgres وبيانات DB_*.'
        )
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }


AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]


LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True


# ---------------------------------------------------------------------------
# الملفات الثابتة والمرفوعة
# ---------------------------------------------------------------------------
STATIC_URL = '/static/'
# وجهة أمر collectstatic — يقدّمها nginx مباشرة على السيرفر
STATIC_ROOT = Path(os.environ.get('STATIC_ROOT', BASE_DIR / 'staticfiles'))

# ملفات مرفوعة من الأدمن (مثل APK تحديثات التطبيق). على السيرفر يقدّمها nginx.
MEDIA_URL = '/media/'
MEDIA_ROOT = Path(os.environ.get('MEDIA_ROOT', BASE_DIR / 'media'))

# مسار ملف Firebase Admin SDK (Service Account JSON) — خارج Git دائماً.
# إشعارات FCM تُعطَّل بصمت طالما هذا المتغيّر غير مضبوط.
FIREBASE_CREDENTIALS_PATH = os.environ.get('FIREBASE_CREDENTIALS_PATH')


# ---------------------------------------------------------------------------
# HTTPS وأمان الإنتاج (تُفعَّل فقط عند DEBUG=False)
# ---------------------------------------------------------------------------
if not DEBUG:
    # nginx ينهي TLS ويمرّر البروتوكول الأصلي في هذا الـ header
    SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
    USE_X_FORWARDED_HOST = False

    # nginx يحوّل 80 -> 443 أصلاً؛ هذا خط دفاع ثانٍ. عطّله بـ SECURE_SSL_REDIRECT=False
    # فقط أثناء أول اختبار قبل تفعيل الشهادة.
    SECURE_SSL_REDIRECT = env_bool('SECURE_SSL_REDIRECT', True)
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True

    # HSTS: ابدأ بساعة، وارفعها (31536000 = سنة) بعد التأكد أن كل شيء يعمل.
    SECURE_HSTS_SECONDS = env_int('SECURE_HSTS_SECONDS', 3600)
    SECURE_HSTS_INCLUDE_SUBDOMAINS = env_bool('SECURE_HSTS_INCLUDE_SUBDOMAINS', False)
    SECURE_HSTS_PRELOAD = False

    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_REFERRER_POLICY = 'same-origin'
    X_FRAME_OPTIONS = 'DENY'


# ---------------------------------------------------------------------------
# البريد الإلكتروني
# ---------------------------------------------------------------------------
# المشروع لا يرسل بريداً حالياً. في Django 6.1 إعداد MAILERS هو الإعداد
# الرسمي، وفحص النشر يرفض backend التطوير (console) في الإنتاج.
#   - EMAIL_HOST مضبوط  -> SMTP حقيقي
#   - DEBUG=True         -> console للتطوير
#   - غير ذلك            -> لا يُعرَّف MAILERS (لا بريد)
if os.environ.get('EMAIL_HOST'):
    MAILERS = {
        'default': {
            'BACKEND': 'django.core.mail.backends.smtp.EmailBackend',
            'OPTIONS': {
                'host': os.environ['EMAIL_HOST'],
                'port': env_int('EMAIL_PORT', 587),
                'username': os.environ.get('EMAIL_HOST_USER', ''),
                'password': os.environ.get('EMAIL_HOST_PASSWORD', ''),
                'use_tls': env_bool('EMAIL_USE_TLS', True),
            },
        },
    }
    DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', 'no-reply@localhost')
elif DEBUG:
    MAILERS = {
        'default': {
            'BACKEND': 'django.core.mail.backends.console.EmailBackend',
        },
    }


# ---------------------------------------------------------------------------
# Logging: يذهب إلى stdout ليجمعه systemd (journalctl -u axon)
# ---------------------------------------------------------------------------
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'default': {'format': '%(asctime)s %(levelname)s %(name)s: %(message)s'},
    },
    'handlers': {
        'console': {'class': 'logging.StreamHandler', 'formatter': 'default'},
    },
    'root': {
        'handlers': ['console'],
        'level': os.environ.get('LOG_LEVEL', 'INFO'),
    },
}
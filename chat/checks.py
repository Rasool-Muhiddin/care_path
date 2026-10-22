from django.conf import settings
from django.core.checks import Warning, register

from .voice import ffmpeg_path


@register()
def ffmpeg_available(app_configs, **kwargs):
    """بلا ffmpeg تُرفض رسائل نسخة الويب الصوتية (Safari/Chrome)؛ التطبيقات تعمل."""
    if not settings.FFMPEG_BINARY or ffmpeg_path():
        return []
    return [Warning(
        f'ffmpeg غير موجود ({settings.FFMPEG_BINARY!r}): الرسائل الصوتية من نسخة الويب ستُرفض.',
        hint='sudo apt install ffmpeg، أو اضبط FFMPEG_BINARY على مساره الكامل.',
        id='chat.W001',
    )]

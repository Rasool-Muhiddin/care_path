from django.apps import AppConfig


class ChatConfig(AppConfig):
    name = 'chat'

    def ready(self):
        from . import signals  # noqa: F401  حذف الملفات الصوتية مع رسائلها
        from . import checks  # noqa: F401  تحذير إن غاب ffmpeg (تحويل الصوت)

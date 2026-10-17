from django.apps import AppConfig


class ChatConfig(AppConfig):
    name = 'chat'

    def ready(self):
        from . import signals  # noqa: F401  حذف الملفات الصوتية مع رسائلها

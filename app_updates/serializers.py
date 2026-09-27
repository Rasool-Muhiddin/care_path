from rest_framework import serializers

from .models import AppVersion


class AppVersionSerializer(serializers.ModelSerializer):
    download_link = serializers.SerializerMethodField()

    class Meta:
        model = AppVersion
        fields = [
            "platform",
            "version_name",
            "version_code",
            "release_notes",
            "is_mandatory",
            "download_link",
        ]

    def get_download_link(self, obj: AppVersion) -> str:
        request = self.context.get("request")
        return obj.download_link(request)

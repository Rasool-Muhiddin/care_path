"""تحويل الرسائل الصوتية بـ ffmpeg الحقيقي (يُتخطى إن لم يكن مثبتاً).

العينات تُولَّد بـ ffmpeg نفسه بنفس بنية ما تسجّله المنصات:
- Safari (MediaRecorder على iPhone): AAC داخل MP4 مجزّأ؛ مدة mdhd فيه 0.
- Chrome: Opus داخل WebM.
- تطبيقات أندرويد/iOS: AAC داخل m4a عادي.

تشغيلها محلياً: FFMPEG_BINARY=/path/to/ffmpeg python manage.py test chat
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from config.testing import CareWorldMixin

from .models import ChatMessage, InquiryType
from .test_voice import messages_url
from .voice import InvalidVoiceNote, aac_duration_seconds

FFMPEG = shutil.which(os.environ.get("FFMPEG_BINARY") or "ffmpeg")


def generate(seconds, *, codec="aac", fmt="ipod", flags=(), source=None):
    """ملف صوتي حقيقي (نغمة sine) بالمدة والصيغة المطلوبة."""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "out"
        source = source or ["-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}"]
        subprocess.run(
            [FFMPEG, "-nostdin", "-hide_banner", "-loglevel", "error", *source,
             "-c:a", codec, *flags, "-f", fmt, str(out)],
            check=True, capture_output=True,
        )
        return out.read_bytes()


def safari_mp4(seconds):
    return generate(seconds, fmt="mp4", flags=["-movflags", "frag_keyframe+empty_moov+default_base_moof"])


@unittest.skipUnless(FFMPEG, "ffmpeg غير مثبت")
@mock.patch("chat.views.notify_in_background")
class VoiceTranscodeTests(CareWorldMixin, APITestCase):
    def setUp(self):
        super().setUp()
        self.voice_root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.voice_root, ignore_errors=True)
        override = override_settings(
            VOICE_NOTES_ROOT=self.voice_root, VOICE_NOTES_X_ACCEL_PREFIX="", FFMPEG_BINARY=FFMPEG
        )
        override.enable()
        self.addCleanup(override.disable)

    def send(self, data, name, content_type):
        upload = SimpleUploadedFile(name, data, content_type=content_type)
        return self.client_for(self.patient_1).post(
            messages_url(self.case_1),
            {"inquiry_type": InquiryType.MEDICAL, "audio": upload},
            format="multipart",
        )

    def stored(self):
        message = ChatMessage.objects.get()
        with message.audio.open("rb") as f:
            return message, f.read()

    def assert_stored_as_aac_m4a(self, response, seconds):
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        message, data = self.stored()
        self.assertTrue(message.audio.name.endswith(".m4a"))
        self.assertEqual(data[4:8], b"ftyp")
        # مدة حقيقية في moov (غير مجزّأ) يقرؤها المحلل نفسه
        self.assertAlmostEqual(aac_duration_seconds(data), seconds, delta=0.2)
        self.assertEqual(message.duration_seconds, seconds)

    def test_safari_fragmented_mp4_was_rejected_before_and_is_accepted_now(self, _notify):
        data = safari_mp4(7)
        # المشكلة نفسها: مدة الترويسة في MP4 المجزّأ 0 (أو لا مسار مدة أصلاً)
        try:
            self.assertEqual(aac_duration_seconds(data), 0)
        except InvalidVoiceNote:
            pass
        response = self.send(data, "voice.m4a", "audio/mp4;codecs=mp4a.40.2")
        self.assert_stored_as_aac_m4a(response, 7)

    def test_chrome_webm_opus_is_converted(self, _notify):
        data = generate(4, codec="libopus", fmt="webm")
        self.assert_stored_as_aac_m4a(self.send(data, "voice.webm", "audio/webm;codecs=opus"), 4)

    def test_native_m4a_is_still_accepted(self, _notify):
        self.assert_stored_as_aac_m4a(self.send(generate(12), "voice.m4a", "audio/mp4"), 12)

    def test_longer_than_two_minutes_is_rejected(self, _notify):
        response = self.send(safari_mp4(125), "voice.m4a", "audio/mp4")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(ChatMessage.objects.exists())

    def test_not_audio_or_unknown_container_is_rejected(self, _notify):
        video_only = generate(
            2, codec="mpeg4", fmt="mp4",
            source=["-f", "lavfi", "-i", "testsrc=duration=2:size=64x64:rate=5"],
        )
        for data, name, content_type in [
            (video_only, "voice.m4a", "audio/mp4"),               # MP4 بلا مسار صوت
            (b"ID3\x03" + b"\x00" * 500, "voice.m4a", "audio/mp4"),  # ليس MP4/WebM
            (safari_mp4(3)[:300], "voice.m4a", "audio/mp4"),      # ملف مقطوع
            (generate(3), "voice.mp3", "audio/mpeg"),             # نوع غير مسموح
        ]:
            with self.subTest(name=name, head=data[:8]):
                response = self.send(data, name, content_type)
                self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(ChatMessage.objects.exists())
        self.assertEqual([p for p in self.voice_root.rglob("*") if p.is_file()], [])


class FfmpegMissingTests(APITestCase):
    @override_settings(FFMPEG_BINARY="definitely-not-ffmpeg-axon")
    def test_system_check_warns(self):
        from .checks import ffmpeg_available

        self.assertEqual([w.id for w in ffmpeg_available(None)], ["chat.W001"])

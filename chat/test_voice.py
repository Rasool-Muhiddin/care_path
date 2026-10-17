"""الرسائل الصوتية: نفس صلاحيات النص، التحقق من الملف، الوصول للملف، وحذفه."""

import shutil
import struct
import tempfile
from pathlib import Path
from unittest import mock

from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.deletion import delete_account
from accounts.models import UserRole
from cases.models import Case, CaseStatus
from config.testing import CareWorldMixin, make_user
from devices.models import Clinic, Device

from .models import ChatMessage, InquiryType
from .notifications import notify_new_message
from .serializers import VOICE_PREVIEW
from .voice import InvalidVoiceNote, aac_duration_seconds


def _box(kind, payload=b""):
    return struct.pack(">I4s", 8 + len(payload), kind) + payload


def m4a(seconds, *, codec=b"mp4a", mdhd_version=0, timescale=44100):
    """ملف m4a صغير بنفس بنية ما يكتبه المسجّل: ftyp + mdat + moov/trak/mdia."""
    duration = int(seconds * timescale)
    if mdhd_version == 1:
        mdhd = b"\x01\x00\x00\x00" + struct.pack(">QQIQ", 0, 0, timescale, duration) + b"\x00" * 4
    else:
        mdhd = b"\x00" * 4 + struct.pack(">IIII", 0, 0, timescale, duration) + b"\x00" * 4
    hdlr = b"\x00" * 8 + b"soun" + b"\x00" * 12 + b"SoundHandler\x00"
    sample_entry = _box(codec, b"\x00" * 28)
    stsd = b"\x00" * 4 + struct.pack(">I", 1) + sample_entry
    stbl = _box(b"stbl", _box(b"stsd", stsd) + _box(b"stts", b"\x00" * 8))
    minf = _box(b"minf", _box(b"smhd", b"\x00" * 8) + stbl)
    mdia = _box(b"mdia", _box(b"mdhd", mdhd) + _box(b"hdlr", hdlr) + minf)
    trak = _box(b"trak", _box(b"tkhd", b"\x00" * 84) + mdia)
    moov = _box(b"moov", _box(b"mvhd", b"\x00" * 100) + trak)
    ftyp = _box(b"ftyp", b"M4A \x00\x00\x00\x00M4A mp42isom")
    return ftyp + _box(b"mdat", b"\x21" * 512) + moov


def voice_file(seconds=5, name="voice.m4a", content_type="audio/mp4", data=None):
    return SimpleUploadedFile(name, m4a(seconds) if data is None else data, content_type=content_type)


def messages_url(case):
    return f"/api/chat/cases/{case.pk}/messages/"


def audio_url(message):
    return f"/api/chat/messages/{message.pk}/audio/"


class VoiceStorageMixin:
    """كل اختبار يكتب الملفات الصوتية في مجلد مؤقت خاص به."""

    def setUp(self):
        super().setUp()
        self.voice_root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.voice_root, ignore_errors=True)
        override = override_settings(VOICE_NOTES_ROOT=self.voice_root, VOICE_NOTES_X_ACCEL_PREFIX="")
        override.enable()
        self.addCleanup(override.disable)

    def voice_message(self, case, sender, inquiry_type, seconds=5):
        return ChatMessage.objects.create(
            case=case, sender=sender, inquiry_type=inquiry_type,
            audio=voice_file(seconds), duration_seconds=seconds,
        )

    def send_voice(self, user, case, inquiry_type, upload=None, **extra):
        return self.client_for(user).post(
            messages_url(case),
            {"inquiry_type": inquiry_type, "audio": upload or voice_file(), **extra},
            format="multipart",
        )

    def send_text(self, user, case, inquiry_type):
        return self.client_for(user).post(
            messages_url(case), {"text": "hello", "inquiry_type": inquiry_type}, format="json"
        )


class AacParserTests(APITestCase):
    def test_reads_duration(self):
        self.assertAlmostEqual(aac_duration_seconds(m4a(37.5)), 37.5, places=2)

    def test_reads_64_bit_mdhd(self):
        self.assertAlmostEqual(aac_duration_seconds(m4a(90, mdhd_version=1)), 90, places=2)

    def test_rejects_other_codec_and_garbage(self):
        for data in (m4a(5, codec=b"Opus"), b"ID3\x03" + b"\x00" * 200, b"", b"\x00\x00\x00\x08ftyp"):
            with self.subTest(data=data[:12]), self.assertRaises(InvalidVoiceNote):
                aac_duration_seconds(data)


@mock.patch("chat.views.notify_in_background")
class VoicePermissionTests(VoiceStorageMixin, CareWorldMixin, APITestCase):
    """الصوت يمر بنفس مسار النص تماماً: كل حالة تُختبر بالنوعين وتعطي نفس الرد."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.engineer_b = make_user("engineer_b", UserRole.ENGINEER)
        # case_1: عيادة مسؤولها engineer. case_2: عيادة بلا مسؤول.
        cls.clinic_a = Clinic.objects.create(name="Clinic A", responsible_engineer=cls.engineer)
        cls.clinic_free = Clinic.objects.create(name="Clinic Free")
        Device.objects.filter(pk=cls.device_1.pk).update(clinic=cls.clinic_a)
        Device.objects.filter(pk=cls.device_2.pk).update(clinic=cls.clinic_free)

    def assert_both(self, user, case, inquiry_type, expected):
        text = self.send_text(user, case, inquiry_type)
        voice = self.send_voice(user, case, inquiry_type)
        self.assertEqual(text.status_code, expected, text.data)
        self.assertEqual(voice.status_code, expected, voice.data)

    def test_allowed_senders(self, _notify):
        T, M = InquiryType.TECHNICAL, InquiryType.MEDICAL
        for user, case, channel in [
            (self.patient_1, self.case_1, M),
            (self.patient_1, self.case_1, T),
            (self.doctor_a, self.case_1, M),
            (self.engineer, self.case_1, T),     # المسؤول عن العيادة
            (self.engineer_b, self.case_2, T),   # عيادة بلا مسؤول: أي مهندس
            (self.manager, self.case_1, T),      # المدير في أي محادثة
        ]:
            with self.subTest(user=user.username, channel=channel):
                self.assert_both(user, case, channel, status.HTTP_201_CREATED)

    def test_denied_senders(self, _notify):
        T, M = InquiryType.TECHNICAL, InquiryType.MEDICAL
        for user, case, channel, expected in [
            (self.doctor_a, self.case_1, T, status.HTTP_400_BAD_REQUEST),  # الطبيب طبي فقط
            (self.engineer, self.case_1, M, status.HTTP_403_FORBIDDEN),    # لا كتابة في الطبية
            (self.manager, self.case_1, M, status.HTTP_403_FORBIDDEN),     # المدير يقرأ الطبية فقط
            (self.engineer_b, self.case_1, T, status.HTTP_403_FORBIDDEN),  # غير المسؤول
            (self.patient_2, self.case_1, M, status.HTTP_403_FORBIDDEN),
            (self.doctor_b, self.case_1, M, status.HTTP_403_FORBIDDEN),
            (self.no_role, self.case_1, M, status.HTTP_403_FORBIDDEN),
        ]:
            with self.subTest(user=user.username, channel=channel):
                self.assert_both(user, case, channel, expected)
        self.assertFalse(ChatMessage.objects.exists())

    def test_anonymous_is_rejected(self, _notify):
        response = self.client_for(None).post(
            messages_url(self.case_1), {"inquiry_type": "medical", "audio": voice_file()}, format="multipart"
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_closed_case_rejects_text_and_voice(self, _notify):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        for user, channel in [
            (self.patient_1, InquiryType.MEDICAL),
            (self.doctor_a, InquiryType.MEDICAL),
            (self.engineer, InquiryType.TECHNICAL),
            (self.manager, InquiryType.TECHNICAL),
        ]:
            with self.subTest(user=user.username):
                self.assert_both(user, self.case_1, channel, status.HTTP_403_FORBIDDEN)
        self.assertFalse(ChatMessage.objects.exists())
        # القراءة تبقى متاحة في الحالة المغلقة
        self.assertEqual(self.client_for(self.patient_1).get(messages_url(self.case_1)).status_code, 200)

    def test_voice_message_shape_and_push(self, notify):
        with self.captureOnCommitCallbacks(execute=True):
            response = self.send_voice(self.patient_1, self.case_1, InquiryType.MEDICAL, voice_file(42))
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        message = ChatMessage.objects.get()
        self.assertEqual(response.data["kind"], "voice")
        self.assertEqual(response.data["text"], "")
        self.assertEqual(response.data["duration_seconds"], 42)
        self.assertEqual(response.data["audio_url"], audio_url(message))
        self.assertNotIn("audio", response.data)
        notify.assert_called_once_with(message.pk)


@mock.patch("chat.views.notify_in_background")
class VoiceValidationTests(VoiceStorageMixin, CareWorldMixin, APITestCase):
    def assert_rejected(self, response):
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST, response.data)
        self.assertFalse(ChatMessage.objects.exists())
        # لا يبقى ملف مرفوض على القرص
        self.assertEqual([p for p in self.voice_root.rglob("*") if p.is_file()], [])

    def send(self, upload=None, **extra):
        return self.send_voice(self.patient_1, self.case_1, InquiryType.MEDICAL, upload, **extra)

    def test_wrong_extension(self, _notify):
        self.assert_rejected(self.send(voice_file(name="voice.mp3")))

    def test_wrong_content_type(self, _notify):
        for content_type in ("audio/mpeg", "audio/ogg", "application/octet-stream", "text/plain"):
            with self.subTest(content_type=content_type):
                self.assert_rejected(self.send(voice_file(content_type=content_type)))

    def test_content_is_not_aac_m4a(self, _notify):
        self.assert_rejected(self.send(voice_file(data=b"ID3\x03" + b"\x00" * 500)))
        self.assert_rejected(self.send(voice_file(data=m4a(5, codec=b"Opus"))))

    def test_longer_than_two_minutes(self, _notify):
        self.assert_rejected(self.send(voice_file(121)))

    def test_exactly_two_minutes_is_accepted(self, _notify):
        self.assertEqual(self.send(voice_file(120)).status_code, status.HTTP_201_CREATED)

    def test_duration_comes_from_file_not_client(self, _notify):
        response = self.send(voice_file(30), duration_seconds=5)
        self.assertEqual(response.data["duration_seconds"], 30)

    @override_settings(VOICE_NOTE_MAX_BYTES=1024)
    def test_too_large(self, _notify):
        self.assert_rejected(self.send(voice_file(data=m4a(5) + b"\x00" * 2048)))

    def test_text_and_voice_together_or_neither(self, _notify):
        self.assert_rejected(self.send(voice_file(), text="hi"))
        response = self.client_for(self.patient_1).post(
            messages_url(self.case_1), {"inquiry_type": "medical"}, format="multipart"
        )
        self.assert_rejected(response)
        response = self.client_for(self.patient_1).post(
            messages_url(self.case_1), {"inquiry_type": "medical", "text": "   "}, format="json"
        )
        self.assert_rejected(response)


@mock.patch("chat.views.notify_in_background")
class VoiceFileAccessTests(VoiceStorageMixin, CareWorldMixin, APITestCase):
    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.engineer_b = make_user("engineer_b", UserRole.ENGINEER)
        clinic = Clinic.objects.create(name="Clinic A", responsible_engineer=cls.engineer)
        Device.objects.filter(pk=cls.device_1.pk).update(clinic=clinic)

    def setUp(self):
        super().setUp()
        self.medical = self.voice_message(self.case_1, self.patient_1, InquiryType.MEDICAL)
        self.technical = self.voice_message(self.case_1, self.patient_1, InquiryType.TECHNICAL)

    def get(self, user, message):
        return self.client_for(user).get(audio_url(message))

    def test_allowed_readers_get_the_file(self, _notify):
        for user, message in [
            (self.patient_1, self.medical),
            (self.patient_1, self.technical),
            (self.doctor_a, self.medical),
            (self.engineer, self.technical),
            (self.engineer_b, self.technical),  # كل المهندسين يقرؤون التقنية
            (self.manager, self.medical),       # المدير يقرأ الطبية
        ]:
            with self.subTest(user=user.username, channel=message.inquiry_type):
                response = self.get(user, message)
                self.assertEqual(response.status_code, status.HTTP_200_OK)
                self.assertEqual(response["Content-Type"], "audio/mp4")
                self.assertIn("no-store", response["Cache-Control"])
                self.assertEqual(b"".join(response.streaming_content), m4a(5))

    def test_denied_readers(self, _notify):
        for user, message, expected in [
            (self.doctor_a, self.technical, status.HTTP_404_NOT_FOUND),   # الطبيب لا يرى التقنية
            (self.engineer, self.medical, status.HTTP_404_NOT_FOUND),     # مهندس عادي: لا طبية
            (self.engineer_b, self.medical, status.HTTP_404_NOT_FOUND),
            (self.patient_2, self.medical, status.HTTP_403_FORBIDDEN),
            (self.doctor_b, self.medical, status.HTTP_403_FORBIDDEN),
            (self.no_role, self.medical, status.HTTP_403_FORBIDDEN),
            (None, self.medical, status.HTTP_401_UNAUTHORIZED),
        ]:
            with self.subTest(user=getattr(user, "username", None), channel=message.inquiry_type):
                response = self.get(user, message)
                self.assertEqual(response.status_code, expected)
                self.assertFalse(getattr(response, "streaming", False))

    def test_text_message_and_unknown_id_have_no_audio(self, _notify):
        text = ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="hi")
        self.assertEqual(self.get(self.patient_1, text).status_code, status.HTTP_404_NOT_FOUND)
        response = self.client_for(self.patient_1).get("/api/chat/messages/999999/audio/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_reading_audio_does_not_mark_read(self, _notify):
        self.get(self.doctor_a, self.medical)
        self.medical.refresh_from_db()
        self.assertFalse(self.medical.is_read)

    def test_x_accel_redirect_in_production(self, _notify):
        with override_settings(VOICE_NOTES_X_ACCEL_PREFIX="/_protected/voice/"):
            response = self.get(self.doctor_a, self.medical)
            denied = self.get(self.engineer, self.medical)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response["X-Accel-Redirect"], f"/_protected/voice/{self.medical.audio.name}")
        self.assertEqual(response.content, b"")
        self.assertEqual(response["Content-Type"], "audio/mp4")
        self.assertEqual(denied.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(denied.has_header("X-Accel-Redirect"))

    def test_files_are_private_and_names_random(self, _notify):
        path = Path(self.medical.audio.path)
        self.assertTrue(path.is_relative_to(self.voice_root))
        self.assertFalse(path.is_relative_to(Path(settings.MEDIA_ROOT)))
        self.assertNotIn("voice", path.name)  # اسم الملف الأصلي لا يُستعمل
        self.assertNotEqual(self.medical.audio.name, self.technical.audio.name)
        self.assertGreaterEqual(len(path.stem), 32)
        with self.assertRaises(ValueError):
            self.medical.audio.url


@mock.patch("chat.views.notify_in_background")
class VoiceListingTests(VoiceStorageMixin, CareWorldMixin, APITestCase):
    """غير المقروء وصندوق الوارد والترقيم تعامل الصوت كأي رسالة."""

    def test_unread_count_includes_voice(self, _notify):
        self.voice_message(self.case_1, self.patient_1, InquiryType.MEDICAL)
        response = self.client_for(self.doctor_a).get("/api/chat/unread-count/")
        self.assertEqual(response.data["total_unread"], 1)
        self.client_for(self.doctor_a).get(messages_url(self.case_1))
        response = self.client_for(self.doctor_a).get("/api/chat/unread-count/")
        self.assertEqual(response.data["total_unread"], 0)

    def test_after_and_before_id_include_voice(self, _notify):
        first = ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="a")
        voice = self.voice_message(self.case_1, self.doctor_a, InquiryType.MEDICAL)
        last = ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="b")
        client = self.client_for(self.patient_1)

        after = client.get(messages_url(self.case_1), {"after_id": first.pk}).data
        self.assertEqual([m["id"] for m in after], [voice.pk, last.pk])
        self.assertEqual(after[0]["kind"], "voice")
        self.assertEqual(after[0]["audio_url"], audio_url(voice))
        self.assertEqual(after[0]["duration_seconds"], 5)
        self.assertEqual(after[1]["kind"], "text")
        self.assertIsNone(after[1]["audio_url"])

        before = client.get(messages_url(self.case_1), {"before_id": last.pk}).data
        self.assertEqual([m["id"] for m in before], [first.pk, voice.pk])

    def test_inbox_preview_for_voice(self, _notify):
        ChatMessage.objects.create(
            case=self.case_1, sender=self.patient_1, text="old", inquiry_type=InquiryType.TECHNICAL
        )
        self.voice_message(self.case_1, self.patient_1, InquiryType.TECHNICAL)
        row = self.client_for(self.engineer).get("/api/chat/engineer/inbox/").data["results"][0]
        self.assertEqual(row["last_message_text"], VOICE_PREVIEW)
        self.assertEqual(row["unread_count"], 2)

    @mock.patch("notifications.services.send_push_to_users")
    def test_push_for_voice_is_generic(self, send_push, _notify):
        message = self.voice_message(self.case_1, self.patient_1, InquiryType.MEDICAL)
        notify_new_message(message)
        kwargs = send_push.call_args.kwargs
        self.assertEqual(kwargs["title"], "رسالة جديدة")
        self.assertEqual(kwargs["body"], "رسالة صوتية جديدة")
        self.assertNotIn(self.patient_1.username, kwargs["title"] + kwargs["body"])


class VoiceFileCleanupTests(VoiceStorageMixin, CareWorldMixin, APITestCase):
    def test_patient_deletion_removes_audio_files(self):
        from_patient = self.voice_message(self.case_1, self.patient_1, InquiryType.MEDICAL)
        from_doctor = self.voice_message(self.case_1, self.doctor_a, InquiryType.MEDICAL)
        other_case = self.voice_message(self.case_2, self.patient_2, InquiryType.MEDICAL)
        paths = [Path(m.audio.path) for m in (from_patient, from_doctor, other_case)]
        self.assertTrue(all(p.exists() for p in paths))

        with self.captureOnCommitCallbacks(execute=True):
            delete_account(self.patient_1)

        self.assertFalse(ChatMessage.objects.filter(case_id=self.case_1.pk).exists())
        # رسائل حالة المريض المحذوف (منه ومن طبيبه) تُحذف ملفاتها؛ غيرها يبقى
        self.assertFalse(paths[0].exists())
        self.assertFalse(paths[1].exists())
        self.assertTrue(paths[2].exists())

    def test_deleted_staff_keeps_voice_as_deleted_user(self):
        message = self.voice_message(self.case_1, self.engineer, InquiryType.TECHNICAL)
        path = Path(message.audio.path)
        with self.captureOnCommitCallbacks(execute=True):
            delete_account(self.engineer)
        message.refresh_from_db()
        self.assertIsNone(message.sender_id)
        self.assertTrue(path.exists())
        response = self.client_for(self.patient_1).get(audio_url(message))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        response.close()

    def test_file_is_kept_if_deletion_rolls_back(self):
        message = self.voice_message(self.case_1, self.patient_1, InquiryType.MEDICAL)
        path = Path(message.audio.path)
        with self.captureOnCommitCallbacks(execute=False) as callbacks:
            message.delete()
        self.assertEqual(len(callbacks), 1)  # يُنفَّذ بعد commit فقط
        self.assertTrue(path.exists())

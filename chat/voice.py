"""
الرسائل الصوتية في المحادثة: التخزين الخاص، أسماء الملفات، والتحقق من الملف.

- التخزين في settings.VOICE_NOTES_ROOT (خارج MEDIA_ROOT) بلا رابط عام؛ الملف
  يُقدَّم فقط عبر VoiceNoteView بعد فحص صلاحية قراءة الرسالة.
- اسم الملف عشوائي (لا يُشتق من الحالة أو المرسل أو الوقت الدقيق).
- المخزَّن دائماً: AAC أحادي داخل m4a عادي (غير مجزّأ). كل رفع يُحوَّل بـ
  ffmpeg (prepare_voice_note) فيُشغَّل كل ملف على كل جهاز: تطبيقات
  أندرويد/iOS (m4a)، Safari على iPhone (MP4 مجزّأ مدته في الترويسة 0)،
  و Chrome (WebM/Opus). المدة تُقرأ من الملف المحوَّل ولا نثق بما يرسله
  التطبيق.
- بلا ffmpeg على الخادم (settings.FFMPEG_BINARY): يُقبل AAC m4a العادي
  فقط كما كان قبل نسخة الويب، فلا تتعطل التطبيقات أثناء النشر.
"""

import logging
import secrets
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import FileSystemStorage
from django.utils import timezone
from django.utils.functional import cached_property
from rest_framework import serializers

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = ('.m4a',)
# ما يرسله التطبيق (audio/mp4) وما ترسله مكتبات أخرى لنفس الملف
ALLOWED_CONTENT_TYPES = ('audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac')
CONTENT_TYPE = 'audio/mp4'

# مع ffmpeg: يُقبل أيضاً ما يسجّله المتصفح (MediaRecorder)
TRANSCODE_EXTENSIONS = ('.m4a', '.mp4', '.webm')
TRANSCODE_CONTENT_TYPES = (*ALLOWED_CONTENT_TYPES, 'audio/webm')


class VoiceNoteStorage(FileSystemStorage):
    """FileSystemStorage على VOICE_NOTES_ROOT. يقرأ الإعداد عند الاستعمال (لا
    عند الاستيراد) كي يعمل override_settings في الاختبارات. لا رابط عاماً له."""

    def __init__(self):
        # nginx (مجموعة www-data) يقرأ الملف عبر X-Accel-Redirect؛ لا أحد غيره
        super().__init__(file_permissions_mode=0o640, directory_permissions_mode=0o750)

    @cached_property
    def base_location(self):
        return settings.VOICE_NOTES_ROOT

    def _clear_cached_properties(self, setting, **kwargs):
        super()._clear_cached_properties(setting, **kwargs)
        if setting == 'VOICE_NOTES_ROOT':
            self.__dict__.pop('base_location', None)
            self.__dict__.pop('location', None)

    def url(self, name):
        raise ValueError('Voice notes have no public URL; use the chat-voice-note endpoint.')


_storage = VoiceNoteStorage()


def voice_storage():
    """callable للـ FileField كي لا تُكتب إعدادات التخزين في الـ migration."""
    return _storage


def voice_upload_to(instance, filename):
    # مجلد شهري لسهولة النسخ الاحتياطي والصيانة، واسم عشوائي 192-bit
    return f"{timezone.now():%Y/%m}/{secrets.token_urlsafe(24)}.m4a"


# ---------------------------------------------------------------------------
# قراءة حاوية MP4 (ISO BMFF): نحتاج فقط التأكد من وجود مسار صوت AAC ومدته
# ---------------------------------------------------------------------------
class InvalidVoiceNote(Exception):
    pass


def _boxes(data, start, end):
    pos = start
    while pos + 8 <= end:
        size, kind = struct.unpack_from('>I4s', data, pos)
        header = 8
        if size == 1:
            if pos + 16 > end:
                raise InvalidVoiceNote('truncated box')
            size = struct.unpack_from('>Q', data, pos + 8)[0]
            header = 16
        elif size == 0:
            size = end - pos
        if size < header or pos + size > end:
            raise InvalidVoiceNote('bad box size')
        yield kind, pos + header, pos + size
        pos += size


def _child(data, start, end, kind):
    for child_kind, child_start, child_end in _boxes(data, start, end):
        if child_kind == kind:
            return child_start, child_end
    return None


def _path(data, start, end, *kinds):
    span = (start, end)
    for kind in kinds:
        span = _child(data, span[0], span[1], kind)
        if span is None:
            return None
    return span


def aac_duration_seconds(data: bytes) -> float:
    """مدة أول مسار صوت AAC في ملف m4a بالثواني. يرفع InvalidVoiceNote إن
    لم يكن الملف MP4 فيه مسار صوت بترميز AAC (mp4a)."""
    top = list(_boxes(data, 0, len(data)))
    if not top or top[0][0] != b'ftyp':
        raise InvalidVoiceNote('not an MP4 container')
    moov = next(((s, e) for k, s, e in top if k == b'moov'), None)
    if moov is None:
        raise InvalidVoiceNote('missing moov')

    for kind, start, end in _boxes(data, *moov):
        if kind != b'trak':
            continue
        mdia = _child(data, start, end, b'mdia')
        if mdia is None:
            continue
        hdlr = _child(data, *mdia, b'hdlr')
        # hdlr: version/flags(4) + pre_defined(4) + handler_type(4)
        if hdlr is None or data[hdlr[0] + 8:hdlr[0] + 12] != b'soun':
            continue
        stsd = _path(data, *mdia, b'minf', b'stbl', b'stsd')
        # stsd: version/flags(4) + entry_count(4)، ثم أول sample entry
        if stsd is None or data[stsd[0] + 12:stsd[0] + 16] != b'mp4a':
            raise InvalidVoiceNote('audio track is not AAC')
        mdhd = _child(data, *mdia, b'mdhd')
        if mdhd is None:
            raise InvalidVoiceNote('missing mdhd')
        s = mdhd[0]
        if data[s] == 1:
            timescale, duration = struct.unpack_from('>IQ', data, s + 20)
            unknown = duration == 0xFFFFFFFFFFFFFFFF
        else:
            timescale, duration = struct.unpack_from('>II', data, s + 12)
            unknown = duration == 0xFFFFFFFF
        if not timescale or unknown:
            raise InvalidVoiceNote('unknown duration')
        return duration / timescale
    raise InvalidVoiceNote('no audio track')


def ffmpeg_path():
    """مسار ffmpeg إن كان التحويل مفعّلاً ومتاحاً، وإلا None."""
    binary = settings.FFMPEG_BINARY
    return shutil.which(binary) if binary else None


def _check_size(upload):
    if upload.size > settings.VOICE_NOTE_MAX_BYTES:
        raise serializers.ValidationError(
            f'حجم الرسالة الصوتية أكبر من الحد المسموح ({settings.VOICE_NOTE_MAX_BYTES // (1024 * 1024)}MB).'
        )


def _check_type(upload, extensions, content_types):
    name = (upload.name or '').lower()
    content_type = (getattr(upload, 'content_type', '') or '').split(';')[0].strip().lower()
    if not name.endswith(extensions) or content_type not in content_types:
        raise serializers.ValidationError('صيغة الرسالة الصوتية غير مدعومة (المسموح: AAC بصيغة m4a).')


def _read(upload) -> bytes:
    upload.seek(0)
    data = upload.read()
    upload.seek(0)
    return data


def _demuxer_for(data: bytes):
    """الحاوية من أول البايتات (لا من الاسم): MP4 أو WebM فقط. يُمرَّر
    لـ ffmpeg صراحةً بـ -f فلا يجرّب صيغاً أخرى على ملف من المستخدم."""
    if data[4:8] == b'ftyp':
        return 'mov'
    if data[:4] == b'\x1a\x45\xdf\xa3':
        return 'matroska'
    return None


def transcode_to_m4a(data: bytes, demuxer: str, ffmpeg: str) -> bytes:
    """AAC-LC أحادي 64kbps في m4a عادي (moov في البداية: +faststart).
    يُقطع عند الحد + ثانية، فالأطول منه يُرفض بعد القياس دون معالجة كاملة."""
    with tempfile.TemporaryDirectory(prefix='axon-voice-') as tmp:
        source, target = Path(tmp) / 'in', Path(tmp) / 'out.m4a'
        source.write_bytes(data)
        command = [
            ffmpeg, '-nostdin', '-hide_banner', '-loglevel', 'error',
            '-protocol_whitelist', 'file',
            '-f', demuxer, '-i', str(source),
            '-map', '0:a:0', '-vn', '-sn', '-dn', '-map_metadata', '-1',
            '-ac', '1', '-c:a', 'aac', '-b:a', '64k',
            '-t', str(settings.VOICE_NOTE_MAX_SECONDS + 1),
            '-movflags', '+faststart', '-f', 'ipod', str(target),
        ]
        try:
            result = subprocess.run(
                command, capture_output=True, timeout=settings.VOICE_TRANSCODE_TIMEOUT_SECONDS
            )
        except subprocess.TimeoutExpired:
            raise InvalidVoiceNote('ffmpeg timed out')
        if result.returncode != 0 or not target.exists():
            raise InvalidVoiceNote(result.stderr.decode(errors='replace')[-500:])
        return target.read_bytes()


def _checked_seconds(seconds: float) -> int:
    if seconds <= 0:
        raise serializers.ValidationError('الرسالة الصوتية فارغة.')
    # هامش نصف ثانية: التطبيق يوقف التسجيل عند الحد بالضبط، والترميز قد يزيد إطاراً
    if seconds > settings.VOICE_NOTE_MAX_SECONDS + 0.5:
        raise serializers.ValidationError(
            f'مدة الرسالة الصوتية أطول من الحد المسموح ({settings.VOICE_NOTE_MAX_SECONDS} ثانية).'
        )
    return min(max(1, round(seconds)), settings.VOICE_NOTE_MAX_SECONDS)

_INVALID = 'ملف الرسالة الصوتية غير صالح (المسموح: AAC بصيغة m4a).'


def _parsed_seconds(data: bytes) -> float:
    try:
        return aac_duration_seconds(data)
    except (InvalidVoiceNote, struct.error, IndexError):
        raise serializers.ValidationError(_INVALID)


def validate_voice_note(upload) -> int:
    """بلا ffmpeg: يتحقق من m4a عادي ويرجع مدته بالثواني (عدد صحيح ≥ 1).

    الترتيب: الحجم أولاً (قبل قراءة الملف في الذاكرة)، ثم الامتداد والنوع،
    ثم محتوى الملف نفسه (حاوية MP4 بمسار AAC) والمدة المقروءة منه.
    """
    _check_size(upload)
    _check_type(upload, ALLOWED_EXTENSIONS, ALLOWED_CONTENT_TYPES)
    return _checked_seconds(_parsed_seconds(_read(upload)))


def prepare_voice_note(upload):
    """يرجع (الملف الذي يُخزَّن، المدة بالثواني).

    مع ffmpeg: أي MP4/WebM صوتي يُحوَّل إلى AAC m4a، والمدة من الناتج
    (تسجيل Safari المجزّأ مدته في الترويسة 0 فيُرفض لو قُرئ كما هو).
    بلا ffmpeg: المسار القديم (m4a عادي فقط، يُخزَّن كما رُفع).
    """
    ffmpeg = ffmpeg_path()
    if ffmpeg is None:
        return upload, validate_voice_note(upload)

    _check_size(upload)
    _check_type(upload, TRANSCODE_EXTENSIONS, TRANSCODE_CONTENT_TYPES)
    data = _read(upload)
    demuxer = _demuxer_for(data)
    if demuxer is None:
        raise serializers.ValidationError(_INVALID)
    try:
        converted = transcode_to_m4a(data, demuxer, ffmpeg)
    except InvalidVoiceNote as e:
        logger.warning('تعذّر تحويل رسالة صوتية (%s، %s بايت): %s', demuxer, len(data), e)
        raise serializers.ValidationError(_INVALID)
    seconds = _checked_seconds(_parsed_seconds(converted))
    return ContentFile(converted, name='voice.m4a'), seconds

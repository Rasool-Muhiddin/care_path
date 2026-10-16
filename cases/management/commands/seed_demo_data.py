"""
بيانات تجريبية واقعية للعرض: يمسح البيانات الحالية ثم ينشئ فريقاً وعيادتين
وأربعة أجهزة وخمسة مرضى بتاريخ علاج (جلسات، نوبات، تأكيدات، محادثات).

    python manage.py seed_demo_data --yes

- يرفض العمل بدون --yes. كل شيء داخل معاملة واحدة.
- قابل لإعادة التشغيل: يمسح ثم يعيد إنشاء نفس البيانات (بذرة عشوائية ثابتة،
  والتواريخ نسبية لليوم بتوقيت بغداد).
- لا يمس المستخدم rasool (superuser) ولا سجلات نسخ التطبيق ولا جداول Django
  الداخلية.
- كل الحسابات المنشأة بكلمة المرور DEMO_PASSWORD.
- قبل الحفظ يتحقق من كل قواعد العمل (جلسة واحدة يومياً، لا نوبة قبل إنشاء
  الحالة، حالة نشطة واحدة لكل مريض، جهاز واحد لكل حالة نشطة، الشدة للشقيقة
  فقط) ويلغي كل شيء إن خُرقت أي قاعدة.
"""

import math
import random
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import Count
from django.db.models.functions import TruncDate
from django.utils import timezone

from accounts.models import User, UserRole
from cases.models import (
    MAX_ATTACK_DURATION_SECONDS,
    AttackEvent,
    AttackLogConfirmation,
    Case,
    CaseStatus,
    DiagnosisType,
    EpilepsyType,
    MigraineType,
)
from chat.models import ChatMessage, InquiryType
from devices.models import Clinic, Device, DeviceStatus, DeviceType
from notifications.models import DeviceToken
from treatments.models import TreatmentSession

BAGHDAD = ZoneInfo("Asia/Baghdad")
DEMO_PASSWORD = "aassddff"
KEPT_SUPERUSER = "rasool"
SEED = 2026

# أوقات "تقريبية" كما يخزّنها التطبيق (صباحاً/ظهراً/مساءً/ليلاً)
APPROXIMATE_HOURS = (9, 13, 18, 22)

TVNS_SCHEMA = {
    "fields": [
        {"key": "frequency_hz", "label": "التردد (Hz)", "type": "number", "min": 1, "max": 100},
        {"key": "pulse_width_us", "label": "عرض النبضة (µs)", "type": "number", "min": 50, "max": 500},
        {"key": "intensity_ma", "label": "الشدة (mA)", "type": "number", "min": 0.5, "max": 10},
        {"key": "session_minutes", "label": "مدة الجلسة (دقيقة)", "type": "number", "min": 5, "max": 60},
        {"key": "mode", "label": "نمط التحفيز", "type": "choice", "choices": ["continuous", "burst"]},
    ]
}


def at(day: date, hour: int, minute: int = 0, second: int = 0) -> datetime:
    """وقت بغداد (aware) ليوم وساعة معيّنين."""
    return datetime.combine(day, time(hour, minute, second), tzinfo=BAGHDAD)


def baghdad_day(moment: datetime) -> date:
    return moment.astimezone(BAGHDAD).date()


@dataclass
class PatientPlan:
    username: str
    first_name: str
    last_name: str
    phone: str
    doctor: str
    device: str
    diagnosis: str
    disease_type: str
    registered_days_ago: int
    monthly_episodes: int
    episode_minutes: int
    symptoms: str
    medications: str
    initial_evaluation: str
    treatment_plan: str
    total_sessions_planned: int | None
    setup: dict
    # الالتزام بالجلسات: احتمال تفويت يوم، واحتمال بدء انقطاع وطوله
    skip_chance: float
    gap_chance: float
    gap_days: tuple[int, int]
    # منحنى التحسن: نسبة المعدل النهائي من الأساس، وسرعة الوصول إليه (أيام)
    final_ratio: float
    improvement_days: float
    confirm_week_chance: float
    closed_days_ago: int | None = None
    # يُملأ أثناء الإنشاء
    case: Case | None = None
    user: User | None = None
    sessions: list = field(default_factory=list)


class Command(BaseCommand):
    help = "Wipe the current data and create realistic demo data (requires --yes)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--yes",
            action="store_true",
            help="Confirm wiping ALL users (except rasool), clinics, devices, cases and their history.",
        )

    def handle(self, *args, **options):
        if not options["yes"]:
            raise CommandError(
                "This deletes every user except 'rasool' and all clinics, devices, cases, sessions, "
                "attacks, confirmations, chat messages and push tokens. Re-run with --yes to confirm."
            )
        keeper = User.objects.filter(username=KEPT_SUPERUSER, is_superuser=True).first()
        if keeper is None:
            raise CommandError(
                f"Superuser '{KEPT_SUPERUSER}' not found — refusing to wipe (it would lock everyone out)."
            )

        self.rng = random.Random(SEED)
        self.now = timezone.now()
        self.today = baghdad_day(self.now)
        keeper_state = self._user_state(keeper)

        with transaction.atomic():
            wiped = self._wipe(keeper)
            self._create_staff()
            self._create_devices()
            plans = self._patient_plans()
            for plan in plans:
                self._create_patient(plan)
            for plan in plans:
                self._create_history(plan)
            self._create_chat(plans)
            self._verify(plans)
            if self._user_state(User.objects.get(pk=keeper.pk)) != keeper_state:
                raise CommandError(f"'{KEPT_SUPERUSER}' changed unexpectedly — rolled back.")

        self._summary(plans, wiped)

    # ------------------------------------------------------------------ wipe

    @staticmethod
    def _user_state(user):
        return (user.pk, user.password, user.is_superuser, user.is_staff, user.role, user.is_manager,
                user.first_name, user.last_name, user.email, user.is_active)

    def _wipe(self, keeper):
        counts = {}
        # الأبناء قبل الآباء (Device.device_type = PROTECT)
        for label, queryset in (
            ("chat messages", ChatMessage.objects.all()),
            ("attack confirmations", AttackLogConfirmation.objects.all()),
            ("attacks", AttackEvent.objects.all()),
            ("sessions", TreatmentSession.objects.all()),
            ("cases", Case.objects.all()),
            ("devices", Device.objects.all()),
            ("device types", DeviceType.objects.all()),
            ("clinics", Clinic.objects.all()),
            ("push tokens", DeviceToken.objects.all()),
            ("users", User.objects.exclude(pk=keeper.pk)),
        ):
            counts[label] = queryset.count()
            queryset.delete()
        return counts

    # ----------------------------------------------------------- staff/devices

    def _make_user(self, username, role, first_name, last_name, phone="", specialty="", joined=None, **extra):
        user = User(
            username=username, role=role, first_name=first_name, last_name=last_name,
            phone_number=phone, specialty=specialty, **extra,
        )
        # set_password مباشرة: لا تمر عبر AUTH_PASSWORD_VALIDATORS
        user.set_password(DEMO_PASSWORD)
        user.save()
        if joined:
            User.objects.filter(pk=user.pk).update(date_joined=joined)
        return user

    def _create_staff(self):
        joined = at(self.today - timedelta(days=1180), 10)
        self.users = {
            "amir": self._make_user("amir", UserRole.ENGINEER, "أمير", "سعد الربيعي", "07711203345",
                                    joined=joined, is_manager=True),
            "baneen": self._make_user("baneen", UserRole.ENGINEER, "بنين", "محمد الخفاجي", "07802231456",
                                      joined=joined + timedelta(days=20)),
            "ahmed": self._make_user("ahmed", UserRole.DOCTOR, "أحمد", "جبار الموسوي", "07901122334",
                                     specialty="Neurology", joined=joined + timedelta(days=5)),
            "omer": self._make_user("omer", UserRole.DOCTOR, "عمر", "فاضل العبيدي", "07733445566",
                                    specialty="Neurology", joined=joined + timedelta(days=9)),
        }
        self.clinics = {
            "ahmed": Clinic.objects.create(
                name="عيادة د. أحمد", address="بغداد، الكرادة، شارع 62",
                phone_number="07901122334", contact_person="د. أحمد جبار الموسوي",
                responsible_engineer=self.users["amir"],
            ),
            "omer": Clinic.objects.create(
                name="عيادة د. عمر", address="بغداد، المنصور، شارع 14 رمضان",
                phone_number="07733445566", contact_person="د. عمر فاضل العبيدي",
                responsible_engineer=self.users["baneen"],
            ),
        }
        Clinic.objects.update(created_at=joined + timedelta(days=30))

    def _create_devices(self):
        created = at(self.today - timedelta(days=1150), 11)
        self.device_types = {
            "M": DeviceType.objects.create(
                name="TVNS M",
                description="جهاز تحفيز العصب المبهم عبر الجلد — بروتوكول الشقيقة",
                setup_schema=TVNS_SCHEMA,
            ),
            "E": DeviceType.objects.create(
                name="TVNS E",
                description="جهاز تحفيز العصب المبهم عبر الجلد — بروتوكول الصرع",
                setup_schema=TVNS_SCHEMA,
            ),
        }
        DeviceType.objects.update(created_at=created, updated_at=created)
        # (serial, type, clinic, installed days ago, last maintenance days ago)
        specs = {
            "M1": ("TVNS-M-2023-0041", "M", "ahmed", 1110, 75),
            "M2": ("TVNS-M-2023-0057", "M", "ahmed", 1100, 120),
            "E1": ("TVNS-E-2025-0112", "E", "omer", 250, 40),
            "E2": ("TVNS-E-2024-0086", "E", "omer", 560, 95),
        }
        self.devices = {}
        for key, (serial, type_key, clinic, installed, maintained) in specs.items():
            device = Device.objects.create(
                serial_number=serial,
                device_type=self.device_types[type_key],
                clinic=self.clinics[clinic],
                status=DeviceStatus.ACTIVE,
                installed_at=self.today - timedelta(days=installed),
                last_maintenance_at=self.today - timedelta(days=maintained),
            )
            stamp = at(self.today - timedelta(days=installed + 3), 12)
            Device.objects.filter(pk=device.pk).update(created_at=stamp)
            self.devices[key] = device

    # ----------------------------------------------------------------- patients

    def _patient_plans(self):
        migraine_setup = {"frequency_hz": 25, "pulse_width_us": 250, "intensity_ma": 2.5,
                          "session_minutes": 30, "mode": "continuous"}
        epilepsy_setup = {"frequency_hz": 20, "pulse_width_us": 300, "intensity_ma": 3.0,
                          "session_minutes": 45, "mode": "burst"}
        return [
            PatientPlan(
                username="zainab.ali", first_name="زينب", last_name="علي حسين", phone="07712345678",
                doctor="ahmed", device="M1", diagnosis=DiagnosisType.MIGRAINE,
                disease_type=MigraineType.WITH_AURA, registered_days_ago=45,
                monthly_episodes=8, episode_minutes=360,
                symptoms="صداع نابض بجهة واحدة يسبقه زغللة ونقاط مضيئة بالعين، غثيان وحساسية من الضوء والصوت.",
                medications="Propranolol 40 mg مرتين يومياً، Sumatriptan 50 mg عند النوبة",
                initial_evaluation="شقيقة مع أورة منذ 6 سنوات، النوبات تزداد مع قلة النوم والتوتر. الفحص العصبي طبيعي.",
                treatment_plan="جلسة TVNS يومية 30 دقيقة، الاستمرار على Propranolol، مراجعة بعد 3 أشهر.",
                total_sessions_planned=90, setup=migraine_setup,
                skip_chance=0.13, gap_chance=0.012, gap_days=(2, 3),
                final_ratio=0.45, improvement_days=60, confirm_week_chance=0.75,
            ),
            PatientPlan(
                username="mustafa.kareem", first_name="مصطفى", last_name="كريم جاسم", phone="07809876543",
                doctor="omer", device="E1", diagnosis=DiagnosisType.EPILEPSY,
                disease_type=EpilepsyType.FOCAL, registered_days_ago=240,
                monthly_episodes=12, episode_minutes=2,
                symptoms="نوبات بؤرية مع شرود وحركات لا إرادية باليد اليمنى، أحياناً فقدان وعي قصير.",
                medications="Carbamazepine 200 mg ثلاث مرات يومياً",
                initial_evaluation="صرع بؤري في الفص الصدغي الأيسر، الاستجابة للدواء جزئية. EEG يؤكد بؤرة صدغية.",
                treatment_plan="جلسة TVNS يومية 45 دقيقة مع الاستمرار على Carbamazepine، مراجعة شهرية.",
                total_sessions_planned=180, setup=epilepsy_setup,
                skip_chance=0.45, gap_chance=0.03, gap_days=(5, 18),
                final_ratio=0.72, improvement_days=160, confirm_week_chance=0.2,
            ),
            PatientPlan(
                username="noor.salman", first_name="نور الهدى", last_name="سلمان داود", phone="07505556677",
                doctor="omer", device="E2", diagnosis=DiagnosisType.EPILEPSY,
                disease_type=EpilepsyType.GENERALIZED, registered_days_ago=548,
                monthly_episodes=6, episode_minutes=3,
                symptoms="نوبات توترية رمعية معممة مع فقدان وعي وتعب شديد بعدها، أحياناً نوبات غياب قصيرة.",
                medications="Sodium valproate 500 mg مرتين يومياً، Levetiracetam 500 mg مرتين يومياً",
                initial_evaluation="صرع معمم منذ الطفولة، نوبات مستمرة رغم دواءين. MRI طبيعي.",
                treatment_plan="جلسة TVNS يومية 45 دقيقة، تقييم تقليل Levetiracetam بعد سنة من الاستقرار.",
                total_sessions_planned=540, setup=epilepsy_setup,
                skip_chance=0.16, gap_chance=0.01, gap_days=(2, 4),
                final_ratio=0.3, improvement_days=170, confirm_week_chance=0.7,
            ),
            PatientPlan(
                username="hassan.abdullah", first_name="حسن", last_name="عبد الله محمد", phone="07834455667",
                doctor="ahmed", device="M2", diagnosis=DiagnosisType.MIGRAINE,
                disease_type=MigraineType.CHRONIC, registered_days_ago=1095,
                monthly_episodes=16, episode_minutes=720,
                symptoms="صداع شبه يومي ضاغط ونابض، يشتد مع الغثيان والدوار، يؤثر على العمل والنوم.",
                medications="Topiramate 50 mg مرتين يومياً، Amitriptyline 10 mg ليلاً، Ibuprofen 400 mg عند النوبة",
                initial_evaluation="شقيقة مزمنة مع إفراط في استخدام المسكنات. الفحص العصبي طبيعي.",
                treatment_plan="جلسة TVNS يومية 30 دقيقة، تقليل المسكنات تدريجياً، مراجعة كل 3 أشهر.",
                total_sessions_planned=None, setup=migraine_setup,
                skip_chance=0.18, gap_chance=0.008, gap_days=(2, 5),
                final_ratio=0.3, improvement_days=240, confirm_week_chance=0.65,
            ),
            PatientPlan(
                username="sara.haider", first_name="سارة", last_name="حيدر عباس", phone="07723344556",
                doctor="ahmed", device="M1", diagnosis=DiagnosisType.MIGRAINE,
                disease_type=MigraineType.WITHOUT_AURA, registered_days_ago=365,
                monthly_episodes=10, episode_minutes=480,
                symptoms="صداع نابض بالصدغين مع غثيان وتقيؤ أحياناً، يستمر يوماً كاملاً دون علاج.",
                medications="Propranolol 80 mg يومياً، Paracetamol 1 g عند النوبة",
                initial_evaluation="شقيقة بدون أورة، النوبات مرتبطة بالإجهاد. الفحص العصبي طبيعي.",
                treatment_plan="جلسة TVNS يومية 30 دقيقة لمدة 10 أشهر ثم التقييم.",
                total_sessions_planned=270, setup=migraine_setup,
                skip_chance=0.15, gap_chance=0.01, gap_days=(2, 4),
                final_ratio=0.4, improvement_days=110, confirm_week_chance=0.7,
                closed_days_ago=60,
            ),
        ]

    def _create_patient(self, plan: PatientPlan):
        start_day = self.today - timedelta(days=plan.registered_days_ago)
        registered = at(start_day, 10, self.rng.randint(0, 50))
        plan.user = self._make_user(
            plan.username, UserRole.PATIENT, plan.first_name, plan.last_name, plan.phone,
            joined=registered - timedelta(minutes=20),
        )
        closed = plan.closed_days_ago is not None
        plan.case = Case.objects.create(
            patient=plan.user,
            doctor=self.users[plan.doctor],
            device=self.devices[plan.device],
            device_setup_parameters=plan.setup,
            diagnosis_type=plan.diagnosis,
            disease_type=plan.disease_type,
            status=CaseStatus.CLOSED if closed else CaseStatus.IN_TREATMENT,
            monthly_episode_count=plan.monthly_episodes,
            episode_duration_minutes=plan.episode_minutes,
            symptoms=plan.symptoms,
            current_medications=plan.medications,
            total_sessions_planned=plan.total_sessions_planned,
            initial_evaluation=plan.initial_evaluation,
            treatment_plan=plan.treatment_plan,
        )
        updated = at(self.today - timedelta(days=plan.closed_days_ago), 12) if closed else self.now
        Case.objects.filter(pk=plan.case.pk).update(created_at=registered, updated_at=updated)
        plan.case.refresh_from_db()

    def _treatment_days(self, plan: PatientPlan):
        """أيام العلاج من يوم إنشاء الحالة حتى اليوم (أو حتى الإغلاق)."""
        first = baghdad_day(plan.case.created_at)
        last = self.today - timedelta(days=plan.closed_days_ago) if plan.closed_days_ago else self.today
        return first, last

    # ------------------------------------------------------------------ history

    def _create_history(self, plan: PatientPlan):
        first, last = self._treatment_days(plan)
        created = plan.case.created_at
        sessions, attacks, confirmations = [], [], []

        # --- sessions: one per day at most, missed days and gaps ---
        gap_left = 0
        day = first
        while day <= last:
            if gap_left:
                gap_left -= 1
            elif day > first and self.rng.random() < plan.gap_chance:
                gap_left = self.rng.randint(*plan.gap_days) - 1
            elif day == first or self.rng.random() >= plan.skip_chance:
                moment = at(day, self.rng.choice((7, 8, 19, 20, 21, 22)), self.rng.randint(0, 59),
                            self.rng.randint(0, 59))
                if day == first:
                    moment = created + timedelta(hours=1, minutes=self.rng.randint(0, 50))
                if moment <= self.now:
                    sessions.append(moment)
            day += timedelta(days=1)
        plan.sessions = sessions

        # --- attacks: start near the baseline rate, improve with noise ---
        daily_base = plan.monthly_episodes / 30.0
        week_factor = 1.0
        day = first
        while day <= last:
            t = (day - first).days
            if day.weekday() == 5 or t == 0:  # new week (Saturday): some weeks are worse
                week_factor = math.exp(self.rng.gauss(0, 0.25))
                if self.rng.random() < 0.12:
                    week_factor *= 1.6
            progress = 1 - math.exp(-t / plan.improvement_days)
            ratio = 1 - (1 - plan.final_ratio) * progress
            rate = daily_base * ratio * week_factor
            for _ in range(self._attacks_on_day(plan, rate)):
                attack = self._attack(plan, day, progress, created)
                if attack is not None:
                    attacks.append(attack)
            day += timedelta(days=1)

        # --- confirmations: some weeks, one per day at most ---
        day = first + timedelta(days=7)
        while day <= last:
            if self.rng.random() < plan.confirm_week_chance:
                moment = at(day, self.rng.randint(9, 22), self.rng.randint(0, 59))
                if moment <= self.now:
                    confirmations.append((moment, self.rng.random() < 0.08))
            day += timedelta(days=7 + self.rng.randint(-1, 2))

        self._save_history(plan, sessions, attacks, confirmations)

    def _attacks_on_day(self, plan, rate):
        if plan.diagnosis == DiagnosisType.MIGRAINE:
            # نوبة شقيقة واحدة يومياً على الأكثر (تدوم ساعات)
            return 1 if self.rng.random() < min(rate, 0.9) else 0
        # الصرع: توزيع Poisson مع عناقيد نادرة (نوبتان يومياً على الأكثر)
        count, threshold, p = 0, math.exp(-rate), 1.0
        while True:
            p *= self.rng.random()
            if p <= threshold or count == 2:
                return count
            count += 1

    def _attack(self, plan, day, progress, created):
        approximate = self.rng.random() < 0.2
        if approximate:
            occurred = at(day, self.rng.choice(APPROXIMATE_HOURS))
        else:
            occurred = at(day, self.rng.randint(5, 23), self.rng.randint(0, 59))
        if occurred < created or occurred > self.now - timedelta(minutes=30):
            return None
        if plan.diagnosis == DiagnosisType.MIGRAINE:
            severity = round(7.5 - 3.0 * progress + self.rng.gauss(0, 1.2))
            severity = max(1, min(10, severity))
            minutes = plan.episode_minutes * (0.45 + 0.08 * severity) * math.exp(self.rng.gauss(0, 0.35))
            seconds = int(max(30 * 60, minutes * 60))
            took_medication = self.rng.random() < min(0.95, max(0.1, 0.12 * severity - 0.15))
        else:
            severity = None
            base = plan.episode_minutes * 60 * (1 - 0.35 * progress)
            seconds = int(max(10, base * math.exp(self.rng.gauss(0, 0.5))))
            # دواء إسعافي (مثل Clobazam) للنوبات الطويلة غالباً
            took_medication = self.rng.random() < (0.55 if seconds > 240 else 0.12)
        seconds = min(seconds, MAX_ATTACK_DURATION_SECONDS[plan.diagnosis])
        # يُسجَّل غالباً بعد انتهاء النوبة بقليل، وأحياناً متأخراً (حتى 3 أيام)
        delay = timedelta(seconds=seconds) + timedelta(minutes=self.rng.randint(5, 180))
        if self.rng.random() < 0.12:
            delay += timedelta(days=self.rng.randint(1, 3))
        logged = min(occurred + delay, self.now - timedelta(minutes=1))
        return occurred, approximate, seconds, severity, took_medication, logged

    def _save_history(self, plan, sessions, attacks, confirmations):
        case, user = plan.case, plan.user
        device = self.devices[plan.device]
        objs = TreatmentSession.objects.bulk_create([
            TreatmentSession(case=case, device=device, performed_by=user, session_date=moment,
                             device_parameters=plan.setup)
            for moment in sessions
        ])
        # created_at = وقت التسجيل الفعلي (قاعدة "جلسة يومياً" تعتمد عليه)
        for obj, moment in zip(objs, sessions):
            obj.created_at = moment
        TreatmentSession.objects.bulk_update(objs, ["created_at"])

        objs = AttackEvent.objects.bulk_create([
            AttackEvent(case=case, occurred_at=o, time_is_approximate=a, duration_seconds=s,
                        severity=sev, took_medication=m)
            for o, a, s, sev, m, _ in attacks
        ])
        for obj, row in zip(objs, attacks):
            obj.created_at = row[5]
        AttackEvent.objects.bulk_update(objs, ["created_at"])

        objs = AttackLogConfirmation.objects.bulk_create([
            AttackLogConfirmation(case=case, had_unlogged=had) for _, had in confirmations
        ])
        for obj, (moment, _) in zip(objs, confirmations):
            obj.confirmed_at = moment
        AttackLogConfirmation.objects.bulk_update(objs, ["confirmed_at"])

        last_seen = max([*sessions, case.created_at])
        User.objects.filter(pk=user.pk).update(last_seen_at=last_seen)

    # --------------------------------------------------------------------- chat

    def _create_chat(self, plans):
        by_user = {p.username: p for p in plans}
        engineer_of = {"ahmed": self.users["amir"], "omer": self.users["baneen"]}
        T, M = InquiryType.TECHNICAL, InquiryType.MEDICAL
        # (patient, channel, sender key, days ago, hour, text, is_read)
        # sender: "p" = المريض، "d" = الطبيب، "e" = المهندس المسؤول
        script = [
            ("zainab.ali", T, "p", 30, 19, "السلام عليكم، الجهاز يطلع صوت تنبيه بعد عشر دقائق من الجلسة، هل هذا طبيعي؟", True),
            ("zainab.ali", T, "e", 30, 20, "وعليكم السلام، هذا تنبيه انخفاض البطارية. اشحني الجهاز ساعتين قبل الجلسة وراح يختفي.", True),
            ("zainab.ali", T, "p", 29, 18, "تمام شكراً، اشتغل بدون مشكلة.", True),
            ("zainab.ali", M, "p", 6, 21, "دكتور صار عندي صداع قوي يومين ورا بعض، هل أزيد جرعة البروبرانولول؟", True),
            ("zainab.ali", M, "d", 5, 10, "لا تزيدين الجرعة بدون مراجعة. استمري على الجلسات وسجلي النوبات، وإذا تكرر راجعيني بالعيادة.", True),
            ("zainab.ali", M, "p", 1, 22, "صار أحسن الحمد لله، بس أحس بدوخة خفيفة بعد الجلسة.", False),

            ("mustafa.kareem", T, "p", 20, 17, "القطعة اللي على الأذن ما تثبت زين، تنزل أثناء الجلسة.", True),
            ("mustafa.kareem", T, "e", 20, 19, "جرب تنظف الأذن والقطعة بمنديل كحولي قبل الجلسة، وإذا استمرت المشكلة نبدلها لك بالعيادة.", True),
            ("mustafa.kareem", M, "d", 12, 11, "مصطفى، لاحظت إنك منقطع عن الجلسات أكثر من أسبوع. الالتزام اليومي مهم حتى نشوف نتيجة.", True),
            ("mustafa.kareem", M, "p", 11, 23, "آسف دكتور كنت مسافر، راح أرجع ألتزم.", True),
            ("mustafa.kareem", M, "d", 3, 9, "صارت عندك نوبتين هذا الأسبوع، هل أخذت الكاربامازيبين بانتظام؟", False),

            ("noor.salman", T, "p", 45, 16, "شلون أعرف إن شدة التحفيز مضبوطة؟ أحس بوخز خفيف فقط.", True),
            ("noor.salman", T, "e", 45, 18, "الوخز الخفيف طبيعي ويعني الإعدادات صحيحة (3 mA). لا تغيرين الإعدادات بنفسك.", True),
            ("noor.salman", T, "p", 2, 20, "الشاحن ما يشتغل من البارحة، هل أقدر أستخدم شاحن موبايل عادي؟", False),
            ("noor.salman", M, "p", 15, 20, "دكتور صار لي شهرين بدون نوبة كبيرة، هل نقدر نقلل الدواء؟", True),
            ("noor.salman", M, "d", 14, 12, "هذا تحسن ممتاز. نناقش تقليل الليفيتيراسيتام بالمراجعة القادمة، لا توقفين أي دواء الآن.", True),

            ("hassan.abdullah", T, "p", 60, 21, "الجهاز يطفي لوحده بعد خمس دقائق.", True),
            ("hassan.abdullah", T, "e", 60, 22, "نسوي له إعادة ضبط: اضغط زر التشغيل 10 ثواني لحد ما يومض الضوء الأزرق، بعدها شغله من جديد.", True),
            ("hassan.abdullah", T, "p", 59, 9, "زبط، شكراً جزيلاً.", True),
            ("hassan.abdullah", M, "p", 8, 19, "دكتور صرت آخذ المسكن مرة أو مرتين بالأسبوع بس، الصداع صار أخف بكثير.", True),
            ("hassan.abdullah", M, "d", 7, 10, "ممتاز يا حسن، هذا بالضبط الهدف. استمر على التوبيراميت والجلسات ونشوفك بالمراجعة.", False),

            ("sara.haider", M, "p", 70, 18, "دكتور حاسة إن النوبات خفت كثير، متى ننهي العلاج؟", True),
            ("sara.haider", M, "d", 69, 11, "نكمل لنهاية الخطة ونسلم الجهاز للعيادة، وبعدها مراجعة كل 3 أشهر.", True),
        ]
        rows = []
        for username, channel, who, days_ago, hour, text, is_read in script:
            plan = by_user[username]
            sender = {"p": plan.user, "d": self.users[plan.doctor], "e": engineer_of[plan.doctor]}[who]
            moment = at(self.today - timedelta(days=days_ago), hour, self.rng.randint(0, 59))
            moment = max(moment, plan.case.created_at + timedelta(hours=2))
            rows.append((ChatMessage(case=plan.case, sender=sender, inquiry_type=channel, text=text,
                                     is_read=is_read), min(moment, self.now - timedelta(minutes=5))))
        objs = ChatMessage.objects.bulk_create([r[0] for r in rows])
        for obj, (_, moment) in zip(objs, rows):
            obj.created_at = moment
        ChatMessage.objects.bulk_update(objs, ["created_at"])

    # ------------------------------------------------------------------- checks

    def _verify(self, plans):
        problems = []
        per_day = (
            TreatmentSession.objects.annotate(day=TruncDate("created_at", tzinfo=BAGHDAD))
            .values("case", "day").annotate(n=Count("id")).filter(n__gt=1)
        )
        if per_day.exists():
            problems.append("more than one session on the same day")
        for plan in plans:
            case = plan.case
            start = baghdad_day(case.created_at)
            for attack in case.attack_events.all():
                if baghdad_day(attack.occurred_at) < start:
                    problems.append(f"{plan.username}: attack before the case was created")
                if (attack.severity is None) == (case.diagnosis_type == DiagnosisType.MIGRAINE):
                    problems.append(f"{plan.username}: severity must be set for migraine only")
                if attack.occurred_at > self.now or attack.created_at < attack.occurred_at:
                    problems.append(f"{plan.username}: attack timestamps out of order")
            if case.status == CaseStatus.CLOSED:
                end = self.today - timedelta(days=plan.closed_days_ago)
                if case.attack_events.filter(occurred_at__gte=at(end + timedelta(days=1), 0)).exists():
                    problems.append(f"{plan.username}: attack after the case was closed")
        active = Case.objects.exclude(status=CaseStatus.CLOSED)
        if active.values("patient").annotate(n=Count("id")).filter(n__gt=1).exists():
            problems.append("a patient has more than one open case")
        if active.exclude(device=None).values("device").annotate(n=Count("id")).filter(n__gt=1).exists():
            problems.append("a device is linked to more than one open case")
        if problems:
            raise CommandError("Demo data broke business rules (rolled back): " + "; ".join(sorted(set(problems))))

    # ------------------------------------------------------------------ summary

    def _summary(self, plans, wiped):
        out = self.stdout
        out.write(self.style.SUCCESS("Demo data created (password for every new account: %s)" % DEMO_PASSWORD))
        out.write("Wiped: " + ", ".join(f"{n} {label}" for label, n in wiped.items()))
        out.write("")
        out.write(f"{'username':17} {'role':9} {'clinic':14} {'doctor':7} {'diagnosis':10} {'registered':11} device")
        clinic_of = {"amir": self.clinics["ahmed"].name, "baneen": self.clinics["omer"].name,
                     "ahmed": self.clinics["ahmed"].name, "omer": self.clinics["omer"].name}
        for key, user in self.users.items():
            role = f"{user.role}{' (manager)' if user.is_manager else ''}"
            out.write(f"{key:17} {role:9} {clinic_of[key]:14} {'':7} {'':10} "
                      f"{User.objects.get(pk=user.pk).date_joined.astimezone(BAGHDAD).date()!s:11}")
        for plan in plans:
            case = plan.case
            status = " (closed)" if case.status == CaseStatus.CLOSED else ""
            out.write(f"{plan.username:17} {'patient':9} {self.clinics[plan.doctor].name:14} {plan.doctor:7} "
                      f"{case.diagnosis_type:10} {baghdad_day(case.created_at)!s:11} "
                      f"{case.device.serial_number}{status}")
        out.write("")
        out.write(f"{'patient':17} {'sessions':>8} {'adherence':>9} {'attacks 1st month':>17} "
                  f"{'attacks last month':>18} {'confirmations':>13}")
        for plan in plans:
            first, last = self._treatment_days(plan)
            days = (last - first).days + 1
            attacks = plan.case.attack_events
            first_month = attacks.filter(occurred_at__lt=at(first + timedelta(days=30), 0)).count()
            last_month = attacks.filter(occurred_at__gte=at(last - timedelta(days=29), 0)).count()
            out.write(f"{plan.username:17} {len(plan.sessions):>8} {len(plan.sessions) / days:>9.0%} "
                      f"{first_month:>17} {last_month:>18} {plan.case.attack_log_confirmations.count():>13}")
        out.write("")
        out.write(f"'{KEPT_SUPERUSER}' was left untouched.")

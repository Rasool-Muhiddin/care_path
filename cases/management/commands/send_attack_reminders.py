from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db.models import Q
from django.utils import timezone

from accounts.models import User, UserRole
from cases.models import Case, CaseStatus

# مريض لم يستخدم التطبيق (ولم يسجّل أي نوبة) منذ هذه المدة يصله تذكير،
# وتذكير واحد على الأكثر لكل مدة مماثلة.
INACTIVITY = timedelta(days=3)

# نص عام بلا أي تفاصيل طبية: الإشعار يظهر على شاشة القفل ويمر عبر Google.
TITLE = "تذكير"
BODY = "هل صارت عندك نوبات خلال الأيام الماضية؟ سجّلها الآن"

# حد FCM هو 500 توكن لكل رسالة multicast؛ مجموعات صغيرة من المستخدمين تبقى تحته
BATCH_SIZE = 100


def patients_due_for_reminder(now=None):
    """
    مرضى لهم حالة غير مغلقة وتوكن FCM مسجَّل، لم يفتحوا التطبيق ولم
    يسجّلوا نوبة منذ 3 أيام، ولم يصلهم تذكير خلال آخر 3 أيام.
    المريض الذي لم يُرَ إطلاقاً (last_seen_at فارغ) يُعامل بتاريخ انضمامه.
    """
    cutoff = (now or timezone.now()) - INACTIVITY
    return (
        User.objects.filter(role=UserRole.PATIENT, is_active=True)
        .filter(cases_as_patient__in=Case.objects.exclude(status=CaseStatus.CLOSED))
        .filter(device_tokens__isnull=False)
        .filter(Q(last_seen_at__lt=cutoff) | Q(last_seen_at__isnull=True, date_joined__lt=cutoff))
        .filter(Q(attack_reminder_sent_at__isnull=True) | Q(attack_reminder_sent_at__lt=cutoff))
        .exclude(cases_as_patient__attack_events__created_at__gte=cutoff)
        .distinct()
    )


class Command(BaseCommand):
    help = "يرسل تذكير push عاماً للمرضى غير النشطين منذ 3 أيام لتسجيل نوباتهم."

    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true", help="اعرض العدد فقط بدون إرسال")

    def handle(self, *args, dry_run=False, **options):
        from notifications.services import send_push_to_users

        patients = list(patients_due_for_reminder())
        if dry_run:
            self.stdout.write(f"{len(patients)} patient(s) due for an attack reminder (dry run).")
            return

        for start in range(0, len(patients), BATCH_SIZE):
            batch = patients[start:start + BATCH_SIZE]
            send_push_to_users(batch, title=TITLE, body=BODY, data={"type": "attack_reminder"})
            # يُعلَّم حتى لو فشل الإرسال: الأفضل تفويت تذكير على إغراق المريض
            User.objects.filter(pk__in=[p.pk for p in batch]).update(
                attack_reminder_sent_at=timezone.now()
            )
        self.stdout.write(f"Sent attack reminders to {len(patients)} patient(s).")

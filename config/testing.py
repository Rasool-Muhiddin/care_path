"""
بيانات اختبار مشتركة لاختبارات الصلاحيات في cases / treatments /
feedback / chat. كل اختبار يبدأ من نفس "العالم":

    doctor_a ── case_1 (patient_1, device_1, in_treatment) ── session_1
    doctor_b ── case_2 (patient_2, device_2, in_treatment) ── session_2
    (بلا طبيب) ─ orphan_case (patient_3, بلا جهاز)
    device_free: جهاز غير مرتبط بأي حالة
    patient_4: مريض بلا حالة
    no_role: superuser بدور فارغ '' (كما ينشئه createsuperuser)
"""

from datetime import timedelta

from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User, UserRole
from cases.models import Case, CaseStatus
from devices.models import Device
from treatments.models import TreatmentSession

PASSWORD = "Passw0rd!x-test"


def make_user(username, role, **extra):
    return User.objects.create_user(username=username, password=PASSWORD, role=role, **extra)


class CareWorldMixin:
    @classmethod
    def setUpTestData(cls):
        cls.doctor_a = make_user("doctor_a", UserRole.DOCTOR)
        cls.doctor_b = make_user("doctor_b", UserRole.DOCTOR)
        cls.patient_1 = make_user("patient_1", UserRole.PATIENT)
        cls.patient_2 = make_user("patient_2", UserRole.PATIENT)
        cls.patient_3 = make_user("patient_3", UserRole.PATIENT)
        cls.patient_4 = make_user("patient_4", UserRole.PATIENT)
        cls.engineer = make_user("engineer", UserRole.ENGINEER)
        cls.no_role = User.objects.create_superuser("root", "root@example.com", PASSWORD)

        cls.device_1 = Device.objects.create(serial_number="SN-1")
        cls.device_2 = Device.objects.create(serial_number="SN-2")
        cls.device_free = Device.objects.create(serial_number="SN-FREE")

        cls.case_1 = Case.objects.create(
            patient=cls.patient_1, doctor=cls.doctor_a, device=cls.device_1,
            diagnosis_type="migraine", status=CaseStatus.IN_TREATMENT,
        )
        cls.case_2 = Case.objects.create(
            patient=cls.patient_2, doctor=cls.doctor_b, device=cls.device_2,
            diagnosis_type="migraine", status=CaseStatus.IN_TREATMENT,
        )
        cls.orphan_case = Case.objects.create(
            patient=cls.patient_3, doctor=None, diagnosis_type="epilepsy",
        )

        cls.session_1 = TreatmentSession.objects.create(
            case=cls.case_1, device=cls.device_1, performed_by=cls.doctor_a,
            session_date=timezone.now(),
        )
        cls.session_2 = TreatmentSession.objects.create(
            case=cls.case_2, device=cls.device_2, performed_by=cls.doctor_b,
            session_date=timezone.now(),
        )
        # جلسات قديمة (قبل يومين) حتى لا تحجز "جلسة اليوم" للمرضى
        TreatmentSession.objects.update(created_at=timezone.now() - timedelta(days=2))

    def client_for(self, user=None):
        client = APIClient()
        if user is not None:
            client.force_authenticate(user)
        return client

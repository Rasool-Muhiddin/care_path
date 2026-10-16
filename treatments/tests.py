from datetime import date, datetime, timedelta
from datetime import timezone as dt_timezone
from unittest import mock

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from cases.models import Case, CaseStatus
from config.testing import CareWorldMixin, results

from .models import TreatmentSession

SESSIONS = "/api/sessions/"


def session_url(session):
    return f"{SESSIONS}{session.pk}/"


def payload(case, **extra):
    return {"case": case.pk, "session_date": timezone.now().isoformat(), **extra}


class SessionScopeTests(CareWorldMixin, APITestCase):
    """C2: الجلسات للقراءة فقط عبر الـ API — الإنشاء للمريض وحده لحالته."""

    def test_doctor_and_engineer_cannot_create_sessions(self):
        before = TreatmentSession.objects.count()
        for user in (self.doctor_a, self.engineer):
            response = self.client_for(user).post(SESSIONS, payload(self.case_1), format="json")
            self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(TreatmentSession.objects.count(), before)

    def test_nobody_can_edit_or_delete_sessions_via_api(self):
        for user in (self.doctor_a, self.engineer, self.patient_1):
            client = self.client_for(user)
            for response in (
                client.patch(session_url(self.session_1), {"doctor_notes": "x"}, format="json"),
                client.put(session_url(self.session_1), payload(self.case_1), format="json"),
                client.delete(session_url(self.session_1)),
            ):
                self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)
        self.session_1.refresh_from_db()
        self.assertEqual(self.session_1.case, self.case_1)
        self.assertNotEqual(self.session_1.doctor_notes, "x")

    def test_doctor_and_engineer_can_read_sessions(self):
        self.assertEqual(
            [s["id"] for s in results(self.client_for(self.doctor_a).get(SESSIONS))], [self.session_1.pk]
        )
        engineer_ids = {s["id"] for s in results(self.client_for(self.engineer).get(SESSIONS))}
        self.assertEqual(engineer_ids, {self.session_1.pk, self.session_2.pk})

    def test_patient_cannot_create_session_for_another_patient(self):
        response = self.client_for(self.patient_1).post(SESSIONS, payload(self.case_2), format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_patient_sees_only_own_sessions(self):
        response = self.client_for(self.patient_1).get(SESSIONS)
        self.assertEqual([s["id"] for s in results(response)], [self.session_1.pk])

    def test_unknown_role_sees_and_creates_nothing(self):
        client = self.client_for(self.no_role)
        self.assertEqual(results(client.get(SESSIONS)), [])
        response = client.post(SESSIONS, payload(self.case_1), format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class PatientSessionRuleTests(CareWorldMixin, APITestCase):
    """H8 + H9: قواعد جلسة المريض اليومية."""

    def test_device_and_date_come_from_server(self):
        old_date = (timezone.now() - timedelta(days=30)).isoformat()
        response = self.client_for(self.patient_1).post(
            SESSIONS,
            {"case": self.case_1.pk, "session_date": old_date, "device": str(self.device_2.pk)},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        session = TreatmentSession.objects.get(pk=response.data["id"])
        self.assertEqual(session.device, self.device_1)
        self.assertLess(abs(timezone.now() - session.session_date), timedelta(minutes=1))

    def test_no_session_on_closed_case(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        response = self.client_for(self.patient_1).post(SESSIONS, payload(self.case_1), format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_patient_cannot_send_doctor_notes(self):
        response = self.client_for(self.patient_1).post(
            SESSIONS, payload(self.case_1, doctor_notes="x"), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_one_session_per_day(self):
        client = self.client_for(self.patient_1)
        self.assertEqual(client.post(SESSIONS, payload(self.case_1), format="json").status_code, 201)
        self.assertEqual(client.post(SESSIONS, payload(self.case_1), format="json").status_code, 400)
        self.assertEqual(TreatmentSession.objects.filter(case=self.case_1).count(), 2)  # القديمة + اليوم

    def test_daily_limit_rechecked_under_lock(self):
        # طلب متزامن: فحص validate مرّ (False)، لكن الطلب الآخر حفظ قبله
        # فيرى create() الجلسة داخل القفل (True) ويرفض.
        with mock.patch("treatments.serializers.patient_logged_today", side_effect=[False, True]):
            response = self.client_for(self.patient_1).post(SESSIONS, payload(self.case_1), format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(TreatmentSession.objects.filter(case=self.case_1).count(), 1)


# 10:00 صباحاً بتوقيت بغداد يوم 2026-10-08 (07:00 UTC)
BAGHDAD_MORNING = datetime(2026, 10, 8, 7, 0, tzinfo=dt_timezone.utc)


class BaghdadDayTests(CareWorldMixin, APITestCase):
    """H7: "اليوم" في قاعدة الجلسة اليومية هو يوم بغداد وليس يوم UTC."""

    def post_with_previous_session_at(self, created_at_utc):
        previous = TreatmentSession.objects.create(case=self.case_1, session_date=created_at_utc)
        TreatmentSession.objects.filter(pk=previous.pk).update(created_at=created_at_utc)
        with mock.patch("django.utils.timezone.now", return_value=BAGHDAD_MORNING):
            return self.client_for(self.patient_1).post(SESSIONS, payload(self.case_1), format="json")

    def test_session_after_baghdad_midnight_counts_as_today(self):
        # 22:30 UTC يوم 7 = 01:30 بغداد يوم 8 → جلسة اليوم موجودة
        response = self.post_with_previous_session_at(datetime(2026, 10, 7, 22, 30, tzinfo=dt_timezone.utc))
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_session_before_baghdad_midnight_counts_as_yesterday(self):
        # 20:30 UTC يوم 7 = 23:30 بغداد يوم 7 → أمس
        response = self.post_with_previous_session_at(datetime(2026, 10, 7, 20, 30, tzinfo=dt_timezone.utc))
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_server_session_date_is_baghdad_local(self):
        with mock.patch("django.utils.timezone.now", return_value=BAGHDAD_MORNING):
            response = self.client_for(self.patient_1).post(SESSIONS, payload(self.case_1), format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        session = TreatmentSession.objects.get(pk=response.data["id"])
        self.assertEqual(timezone.localdate(session.session_date), date(2026, 10, 8))
        # الـ API يرسل الوقت مع إزاحة بغداد؛ Flutter يحوّله بـ toLocal()
        self.assertTrue(response.data["session_date"].endswith("+03:00"))

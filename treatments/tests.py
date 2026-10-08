from datetime import timedelta
from unittest import mock

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from cases.models import Case, CaseStatus
from config.testing import CareWorldMixin

from .models import TreatmentSession

SESSIONS = "/api/sessions/"


def session_url(session):
    return f"{SESSIONS}{session.pk}/"


def payload(case, **extra):
    return {"case": case.pk, "session_date": timezone.now().isoformat(), **extra}


class SessionScopeTests(CareWorldMixin, APITestCase):
    """C2: لا أحد يسجّل أو ينقل جلسات خارج نطاقه."""

    def test_doctor_cannot_create_session_on_other_doctors_case(self):
        before = TreatmentSession.objects.filter(case=self.case_2).count()
        response = self.client_for(self.doctor_a).post(SESSIONS, payload(self.case_2), format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("case", response.data)
        self.assertEqual(TreatmentSession.objects.filter(case=self.case_2).count(), before)

    def test_doctor_can_create_session_on_own_case(self):
        response = self.client_for(self.doctor_a).post(SESSIONS, payload(self.case_1), format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_doctor_cannot_move_session_to_another_case(self):
        response = self.client_for(self.doctor_a).patch(
            session_url(self.session_1), {"case": self.case_2.pk}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.session_1.refresh_from_db()
        self.assertEqual(self.session_1.case, self.case_1)

    def test_doctor_cannot_edit_other_doctors_session(self):
        response = self.client_for(self.doctor_a).patch(
            session_url(self.session_2), {"doctor_notes": "x"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_patient_cannot_create_session_for_another_patient(self):
        response = self.client_for(self.patient_1).post(SESSIONS, payload(self.case_2), format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_patient_cannot_edit_or_delete_session(self):
        client = self.client_for(self.patient_1)
        self.assertEqual(
            client.patch(session_url(self.session_1), {"patient_response": "x"}, format="json").status_code,
            status.HTTP_403_FORBIDDEN,
        )
        self.assertEqual(client.delete(session_url(self.session_1)).status_code, status.HTTP_403_FORBIDDEN)

    def test_patient_sees_only_own_sessions(self):
        response = self.client_for(self.patient_1).get(SESSIONS)
        self.assertEqual([s["id"] for s in response.data], [self.session_1.pk])

    def test_unknown_role_sees_and_creates_nothing(self):
        client = self.client_for(self.no_role)
        self.assertEqual(client.get(SESSIONS).data, [])
        response = client.post(SESSIONS, payload(self.case_1), format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


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

    def test_doctor_also_blocked_on_closed_case(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        response = self.client_for(self.doctor_a).post(SESSIONS, payload(self.case_1), format="json")
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

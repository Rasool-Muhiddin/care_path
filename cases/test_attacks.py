from datetime import datetime, time, timedelta

from django.core.cache import cache
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from config.testing import CareWorldMixin, results

from .models import AttackEvent, AttackLogConfirmation, Case, CaseStatus

ATTACKS = "/api/attack-events/"
CONFIRMATIONS = "/api/attack-log-confirmations/"


class AttackEventTestBase(CareWorldMixin, APITestCase):
    def setUp(self):
        cache.clear()  # عدّاد throttle مشترك بين الاختبارات
        # حالات عمرها أسبوعان حتى يُقبل تسجيل نوبات قبل أيام
        Case.objects.update(created_at=timezone.now() - timedelta(days=14))
        # orphan_case (صرع) يصبح حالة المريض 3 النشطة
        self.epilepsy_case = self.orphan_case

    def payload(self, case=None, **overrides):
        data = {
            "case": (case or self.case_1).pk,
            "occurred_at": (timezone.now() - timedelta(hours=2)).isoformat(),
            "duration_seconds": 3 * 3600,
            "severity": 6,
            "took_medication": True,
        }
        data.update(overrides)
        return {k: v for k, v in data.items() if v is not None}

    def post(self, user, **kwargs):
        return self.client_for(user).post(ATTACKS, self.payload(**kwargs), format="json")


class AttackEventCreateTests(AttackEventTestBase):
    def test_migraine_patient_logs_attack(self):
        response = self.post(self.patient_1)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        event = AttackEvent.objects.get(pk=response.data["id"])
        self.assertEqual(event.severity, 6)
        self.assertTrue(event.took_medication)
        self.assertFalse(event.time_is_approximate)

    def test_migraine_requires_severity_in_range(self):
        for severity in (None, 0, 11):
            response = self.client_for(self.patient_1).post(
                ATTACKS, self.payload(severity=severity), format="json"
            )
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST, severity)

    def test_epilepsy_rejects_severity(self):
        response = self.post(self.patient_3, case=self.epilepsy_case, duration_seconds=90, severity=4)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("severity", response.data)

    def test_epilepsy_logs_without_severity(self):
        data = self.payload(case=self.epilepsy_case, duration_seconds=90)
        del data["severity"]
        response = self.client_for(self.patient_3).post(ATTACKS, data, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        self.assertIsNone(AttackEvent.objects.get(pk=response.data["id"]).severity)

    def test_medication_answer_is_required(self):
        data = self.payload()
        del data["took_medication"]
        response = self.client_for(self.patient_1).post(ATTACKS, data, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("took_medication", response.data)

    def test_duration_limits_depend_on_diagnosis(self):
        self.assertEqual(self.post(self.patient_1, duration_seconds=0).status_code, 400)
        self.assertEqual(self.post(self.patient_1, duration_seconds=72 * 3600 + 1).status_code, 400)
        data = self.payload(case=self.epilepsy_case, duration_seconds=3601)
        del data["severity"]
        response = self.client_for(self.patient_3).post(ATTACKS, data, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_future_time_rejected_but_small_clock_skew_allowed(self):
        future = (timezone.now() + timedelta(minutes=30)).isoformat()
        self.assertEqual(self.post(self.patient_1, occurred_at=future).status_code, 400)
        skew = (timezone.now() + timedelta(minutes=2)).isoformat()
        self.assertEqual(self.post(self.patient_1, occurred_at=skew).status_code, 201)

    def test_seven_calendar_days_back_limit(self):
        today = timezone.localdate()
        tz = timezone.get_current_timezone()
        start_of_limit = timezone.make_aware(
            datetime.combine(today - timedelta(days=7), time.min), tz
        )
        ok = self.post(self.patient_1, occurred_at=(start_of_limit + timedelta(hours=1)).isoformat())
        self.assertEqual(ok.status_code, status.HTTP_201_CREATED, ok.data)
        too_old = self.post(self.patient_1, occurred_at=(start_of_limit - timedelta(hours=1)).isoformat())
        self.assertEqual(too_old.status_code, status.HTTP_400_BAD_REQUEST)

    def test_not_before_case_creation_day(self):
        Case.objects.filter(pk=self.case_1.pk).update(created_at=timezone.now())
        response = self.post(self.patient_1, occurred_at=(timezone.now() - timedelta(days=2)).isoformat())
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_closed_case_rejected(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        self.assertEqual(self.post(self.patient_1).status_code, status.HTTP_400_BAD_REQUEST)

    def test_patient_cannot_log_for_another_patients_case(self):
        response = self.post(self.patient_2, case=self.case_1)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_staff_cannot_create(self):
        for user in (self.doctor_a, self.engineer):
            self.assertEqual(self.post(user).status_code, status.HTTP_403_FORBIDDEN)

    def test_identical_request_within_a_minute_is_a_duplicate(self):
        occurred = (timezone.now() - timedelta(hours=1)).isoformat()
        self.assertEqual(self.post(self.patient_1, occurred_at=occurred).status_code, 201)
        self.assertEqual(self.post(self.patient_1, occurred_at=occurred).status_code, 400)
        self.assertEqual(AttackEvent.objects.filter(case=self.case_1).count(), 1)

    def test_several_different_missed_attacks_in_a_row_are_allowed(self):
        for days in (1, 2, 3):
            occurred = (timezone.now() - timedelta(days=days)).isoformat()
            response = self.post(self.patient_1, occurred_at=occurred, time_is_approximate=True)
            self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        self.assertEqual(AttackEvent.objects.filter(case=self.case_1).count(), 3)


class AttackEventReadDeleteTests(AttackEventTestBase):
    def setUp(self):
        super().setUp()
        self.event_1 = AttackEvent.objects.create(
            case=self.case_1, occurred_at=timezone.now(), duration_seconds=3600,
            severity=5, took_medication=False,
        )
        self.event_2 = AttackEvent.objects.create(
            case=self.case_2, occurred_at=timezone.now(), duration_seconds=3600,
            severity=5, took_medication=False,
        )

    def ids(self, user, query=""):
        return {e["id"] for e in results(self.client_for(user).get(ATTACKS + query))}

    def test_scoping(self):
        self.assertEqual(self.ids(self.patient_1), {self.event_1.pk})
        self.assertEqual(self.ids(self.doctor_a), {self.event_1.pk})
        self.assertEqual(self.ids(self.doctor_b), {self.event_2.pk})
        self.assertEqual(self.ids(self.engineer), {self.event_1.pk, self.event_2.pk})
        self.assertEqual(self.ids(self.engineer, f"?case={self.case_2.pk}"), {self.event_2.pk})
        self.assertEqual(self.ids(self.no_role), set())

    def test_patient_deletes_own_attack_within_24_hours(self):
        response = self.client_for(self.patient_1).delete(f"{ATTACKS}{self.event_1.pk}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

    def test_patient_cannot_delete_after_24_hours(self):
        AttackEvent.objects.filter(pk=self.event_1.pk).update(
            created_at=timezone.now() - timedelta(hours=25)
        )
        response = self.client_for(self.patient_1).delete(f"{ATTACKS}{self.event_1.pk}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_patient_cannot_delete_other_patients_attack(self):
        response = self.client_for(self.patient_1).delete(f"{ATTACKS}{self.event_2.pk}/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_doctor_cannot_delete_engineer_can(self):
        url = f"{ATTACKS}{self.event_1.pk}/"
        self.assertEqual(self.client_for(self.doctor_a).delete(url).status_code, 403)
        AttackEvent.objects.filter(pk=self.event_1.pk).update(
            created_at=timezone.now() - timedelta(days=30)
        )
        self.assertEqual(self.client_for(self.engineer).delete(url).status_code, 204)

    def test_no_edit(self):
        response = self.client_for(self.patient_1).patch(
            f"{ATTACKS}{self.event_1.pk}/", {"severity": 9}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)


class AttackLogConfirmationTests(AttackEventTestBase):
    def confirm(self, user, case=None, had_unlogged=False):
        return self.client_for(user).post(
            CONFIRMATIONS, {"case": (case or self.case_1).pk, "had_unlogged": had_unlogged}, format="json"
        )

    def test_patient_confirms_once_per_day(self):
        self.assertEqual(self.confirm(self.patient_1).status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.confirm(self.patient_1, had_unlogged=True).status_code, 400)
        self.assertEqual(AttackLogConfirmation.objects.filter(case=self.case_1).count(), 1)

    def test_only_own_case_and_only_patients(self):
        self.assertEqual(self.confirm(self.patient_2).status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.confirm(self.doctor_a).status_code, status.HTTP_403_FORBIDDEN)

    def test_staff_read_within_scope(self):
        self.confirm(self.patient_1)
        self.assertEqual(len(results(self.client_for(self.doctor_a).get(CONFIRMATIONS))), 1)
        self.assertEqual(len(results(self.client_for(self.doctor_b).get(CONFIRMATIONS))), 0)
        self.assertEqual(len(results(self.client_for(self.engineer).get(CONFIRMATIONS))), 1)

from datetime import timedelta
from unittest import mock

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from config.testing import CareWorldMixin
from feedback.models import Feedback

from .models import Case, CaseProgressNote, CaseStatus, WeeklyEpisodeLog
from .serializers import CaseSerializer, WeeklyEpisodeLogSerializer

CASES = "/api/cases/"


def case_url(case):
    return f"{CASES}{case.pk}/"


class PatientCaseReadOnlyTests(CareWorldMixin, APITestCase):
    """C1: المريض يقرأ حالته فقط — لا تعديل ولا حذف ولا رؤية حالات غيره."""

    def test_patient_lists_only_own_case(self):
        response = self.client_for(self.patient_1).get(CASES)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([c["id"] for c in response.data], [self.case_1.pk])

    def test_patient_cannot_retrieve_other_patients_case(self):
        response = self.client_for(self.patient_1).get(case_url(self.case_2))
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_patient_cannot_reassign_case_to_another_patient(self):
        response = self.client_for(self.patient_1).patch(
            case_url(self.case_1), {"patient": self.patient_2.pk}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.case_1.refresh_from_db()
        self.assertEqual(self.case_1.patient, self.patient_1)

    def test_patient_cannot_change_diagnosis(self):
        response = self.client_for(self.patient_1).patch(
            case_url(self.case_1), {"diagnosis_type": "epilepsy"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.case_1.refresh_from_db()
        self.assertEqual(self.case_1.diagnosis_type, "migraine")

    def test_patient_cannot_delete_own_case(self):
        response = self.client_for(self.patient_1).delete(case_url(self.case_1))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(Case.objects.filter(pk=self.case_1.pk).exists())

    def test_doctor_cannot_delete_case(self):
        response = self.client_for(self.doctor_a).delete(case_url(self.case_1))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(Case.objects.filter(pk=self.case_1.pk).exists())

    def test_engineer_can_delete_case(self):
        response = self.client_for(self.engineer).delete(case_url(self.orphan_case))
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)


class CaseBusinessRuleTests(CareWorldMixin, APITestCase):
    """C4: قواعد العمل مطبّقة في السيرفر وليس في الواجهة فقط."""

    def test_doctor_cannot_link_device_already_on_another_case(self):
        response = self.client_for(self.doctor_a).post(
            CASES,
            {"patient": self.patient_4.pk, "diagnosis_type": "migraine", "device": str(self.device_1.pk)},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("device", response.data)
        self.assertEqual(Case.objects.filter(device=self.device_1).count(), 1)

    def test_doctor_can_link_free_device(self):
        response = self.client_for(self.doctor_a).post(
            CASES,
            {"patient": self.patient_4.pk, "diagnosis_type": "migraine", "device": str(self.device_free.pk)},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_engineer_cannot_move_device_onto_case_when_linked_elsewhere(self):
        response = self.client_for(self.engineer).patch(
            case_url(self.orphan_case), {"device": str(self.device_2.pk)}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_editing_case_keeps_its_own_device(self):
        response = self.client_for(self.doctor_a).patch(
            case_url(self.case_1), {"device": str(self.device_1.pk), "treatment_plan": "x"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_doctor_cannot_create_case_for_another_doctor(self):
        response = self.client_for(self.doctor_a).post(
            CASES,
            {"patient": self.patient_4.pk, "doctor": self.doctor_b.pk, "diagnosis_type": "migraine"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("doctor", response.data)
        self.assertFalse(Case.objects.filter(patient=self.patient_4).exists())

    def test_doctor_created_case_is_assigned_to_that_doctor(self):
        response = self.client_for(self.doctor_a).post(
            CASES, {"patient": self.patient_4.pk, "diagnosis_type": "migraine"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["doctor"], self.doctor_a.pk)

    def test_doctor_cannot_reassign_existing_case_to_another_doctor(self):
        response = self.client_for(self.doctor_a).patch(
            case_url(self.case_1), {"doctor": self.doctor_b.pk}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.case_1.refresh_from_db()
        self.assertEqual(self.case_1.doctor, self.doctor_a)

    def test_engineer_can_assign_doctor(self):
        response = self.client_for(self.engineer).patch(
            case_url(self.orphan_case), {"doctor": self.doctor_b.pk}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["doctor"], self.doctor_b.pk)

    def test_cannot_create_second_active_case_for_patient(self):
        response = self.client_for(self.doctor_a).post(
            CASES, {"patient": self.patient_1.pk, "diagnosis_type": "epilepsy"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cannot_reopen_closed_case_while_another_is_active(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        Case.objects.create(patient=self.patient_1, doctor=self.doctor_a, diagnosis_type="migraine")

        response = self.client_for(self.doctor_a).patch(
            case_url(self.case_1), {"status": CaseStatus.IN_TREATMENT}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            Case.objects.filter(patient=self.patient_1).exclude(status=CaseStatus.CLOSED).count(), 1
        )

    def test_staff_cannot_move_case_to_another_patient(self):
        for user in (self.doctor_a, self.engineer):
            response = self.client_for(user).patch(
                case_url(self.case_1), {"patient": self.patient_4.pk}, format="json"
            )
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.case_1.refresh_from_db()
        self.assertEqual(self.case_1.patient, self.patient_1)


class DeviceReuseTests(CareWorldMixin, APITestCase):
    """
    إرجاع الجهاز: تُغلق الحالة فيصبح الجهاز متاحاً لأي مريض، وتبقى بيانات
    المريض السابق مرتبطة بحالته الأصلية.
    """

    def close_case_1(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)

    def test_freed_device_can_be_linked_to_new_patient(self):
        feedback = Feedback.objects.create(session=self.session_1, submitted_by=self.patient_1,
                                           source="patient", rating=4)
        log = WeeklyEpisodeLog.objects.create(case=self.case_1, week_start_date=timezone.localdate(),
                                              episode_count=2)
        self.close_case_1()

        response = self.client_for(self.doctor_a).post(
            CASES,
            {"patient": self.patient_4.pk, "diagnosis_type": "migraine", "device": str(self.device_1.pk)},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        # سجل المريض السابق لم يُمس: حالته المغلقة ما زالت على نفس الجهاز
        self.case_1.refresh_from_db()
        self.session_1.refresh_from_db()
        self.assertEqual(self.case_1.device, self.device_1)
        self.assertEqual(self.case_1.status, CaseStatus.CLOSED)
        self.assertEqual(self.session_1.case, self.case_1)
        self.assertEqual(self.session_1.device, self.device_1)
        self.assertTrue(Feedback.objects.filter(pk=feedback.pk, session=self.session_1).exists())
        self.assertTrue(WeeklyEpisodeLog.objects.filter(pk=log.pk, case=self.case_1).exists())
        self.assertEqual(Case.objects.filter(device=self.device_1).count(), 2)

    def test_device_in_active_case_rejected_for_another_patient(self):
        response = self.client_for(self.doctor_a).post(
            CASES,
            {"patient": self.patient_4.pk, "diagnosis_type": "migraine", "device": str(self.device_2.pk)},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("device", response.data)

    def test_reopening_closed_case_with_taken_device_is_rejected(self):
        self.close_case_1()
        Case.objects.create(patient=self.patient_4, doctor=self.doctor_a, device=self.device_1,
                            diagnosis_type="migraine")

        response = self.client_for(self.doctor_a).patch(
            case_url(self.case_1), {"status": CaseStatus.IN_TREATMENT}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("إعادة فتح", str(response.data["device"]))
        self.case_1.refresh_from_db()
        self.assertEqual(self.case_1.status, CaseStatus.CLOSED)

    def test_reopening_without_device_is_allowed_when_device_taken(self):
        self.close_case_1()
        Case.objects.create(patient=self.patient_4, doctor=self.doctor_a, device=self.device_1,
                            diagnosis_type="migraine")

        response = self.client_for(self.doctor_a).patch(
            case_url(self.case_1), {"status": CaseStatus.IN_TREATMENT, "device": None}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_reopening_closed_case_with_free_device_is_allowed(self):
        self.close_case_1()
        response = self.client_for(self.doctor_a).patch(
            case_url(self.case_1), {"status": CaseStatus.IN_TREATMENT}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_db_allows_freed_device_but_not_two_active_cases(self):
        self.close_case_1()
        Case.objects.create(patient=self.patient_4, device=self.device_1, diagnosis_type="migraine")
        with self.assertRaises(IntegrityError), transaction.atomic():
            Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.IN_TREATMENT)


class CaseConstraintTests(CareWorldMixin, APITestCase):
    """C4 + H9: القيود في قاعدة البيانات، وتحويل IntegrityError إلى 400."""

    def test_db_rejects_second_active_case(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            Case.objects.create(patient=self.patient_1, diagnosis_type="migraine")

    def test_db_allows_new_case_after_closing(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        Case.objects.create(patient=self.patient_1, diagnosis_type="migraine")

    def test_db_rejects_device_on_two_cases(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            Case.objects.create(patient=self.patient_4, device=self.device_1, diagnosis_type="migraine")

    def test_concurrent_active_case_returns_400_not_500(self):
        # نحاكي طلباً متزامناً تجاوز فحص الـ serializer: القيد يلتقطه
        with mock.patch.object(CaseSerializer, "validate", lambda self, attrs: attrs):
            response = self.client_for(self.engineer).post(
                CASES, {"patient": self.patient_1.pk, "diagnosis_type": "migraine"}, format="json"
            )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("حالة نشطة", response.data["detail"])

    def test_concurrent_device_link_returns_400_not_500(self):
        with mock.patch.object(CaseSerializer, "validate", lambda self, attrs: attrs):
            response = self.client_for(self.engineer).post(
                CASES,
                {"patient": self.patient_4.pk, "diagnosis_type": "migraine", "device": str(self.device_1.pk)},
                format="json",
            )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("الجهاز", response.data["detail"])


class WeeklyEpisodeLogTests(CareWorldMixin, APITestCase):
    URL = "/api/weekly-episode-logs/"

    def setUp(self):
        # حالة عمرها أسبوعان: عندها أسابيع مستحقة
        Case.objects.filter(pk=self.case_1.pk).update(created_at=timezone.now() - timedelta(days=15))

    def test_patient_cannot_log_for_another_patients_case(self):
        response = self.client_for(self.patient_2).post(
            self.URL, {"case": self.case_1.pk, "episode_count": 3}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_patient_logs_pending_week(self):
        response = self.client_for(self.patient_1).post(
            self.URL, {"case": self.case_1.pk, "episode_count": 3}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_duplicate_week_from_concurrent_request_returns_400(self):
        first = self.client_for(self.patient_1).post(
            self.URL, {"case": self.case_1.pk, "episode_count": 3}, format="json"
        )
        week = WeeklyEpisodeLog.objects.get(pk=first.data["id"]).week_start_date

        def stale_validate(serializer, attrs):
            attrs["week_start_date"] = week  # طلب ثانٍ حسب نفس الأسبوع قبل حفظ الأول
            return attrs

        with mock.patch.object(WeeklyEpisodeLogSerializer, "validate", stale_validate):
            response = self.client_for(self.patient_1).post(
                self.URL, {"case": self.case_1.pk, "episode_count": 5}, format="json"
            )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(WeeklyEpisodeLog.objects.filter(case=self.case_1, week_start_date=week).count(), 1)


class DefaultDenyTests(CareWorldMixin, APITestCase):
    """H1: أي دور غير patient/doctor/engineer لا يرى شيئاً."""

    def setUp(self):
        CaseProgressNote.objects.create(
            case=self.case_1, author=self.doctor_a, note="n", sessions_completed_snapshot=1
        )
        WeeklyEpisodeLog.objects.create(
            case=self.case_1, week_start_date=timezone.localdate(), episode_count=1
        )

    def test_unknown_role_sees_nothing(self):
        client = self.client_for(self.no_role)
        for url in (CASES, "/api/case-progress-notes/", "/api/weekly-episode-logs/"):
            response = client.get(url)
            self.assertEqual(response.status_code, status.HTTP_200_OK, url)
            self.assertEqual(response.data, [], url)

    def test_unknown_role_cannot_create_case(self):
        response = self.client_for(self.no_role).post(
            CASES, {"patient": self.patient_4.pk, "diagnosis_type": "migraine"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_patient_sees_no_progress_notes(self):
        response = self.client_for(self.patient_1).get("/api/case-progress-notes/")
        self.assertEqual(response.data, [])

    def test_engineer_still_sees_everything(self):
        response = self.client_for(self.engineer).get(CASES)
        self.assertEqual(len(response.data), 3)

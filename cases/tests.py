from datetime import timedelta
from unittest import mock

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from config.testing import CareWorldMixin, make_user, results
from devices.models import Clinic, Device
from treatments.models import TreatmentSession

from .models import AttackEvent, Case, CaseStatus
from .serializers import CaseSerializer

CASES = "/api/cases/"


def case_url(case):
    return f"{CASES}{case.pk}/"


class PatientCaseReadOnlyTests(CareWorldMixin, APITestCase):
    """C1: المريض يقرأ حالته فقط — لا تعديل ولا حذف ولا رؤية حالات غيره."""

    def test_patient_lists_only_own_case(self):
        response = self.client_for(self.patient_1).get(CASES)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([c["id"] for c in results(response)], [self.case_1.pk])

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

    def test_manager_can_delete_case(self):
        response = self.client_for(self.manager).delete(case_url(self.orphan_case))
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

    def test_manager_cannot_move_device_onto_case_when_linked_elsewhere(self):
        response = self.client_for(self.manager).patch(
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

    def test_new_case_starts_in_treatment(self):
        response = self.client_for(self.doctor_a).post(
            CASES, {"patient": self.patient_4.pk, "diagnosis_type": "migraine"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["status"], CaseStatus.IN_TREATMENT)

    def test_only_two_statuses_accepted(self):
        self.assertEqual(set(CaseStatus.values), {"in_treatment", "closed"})
        for old in ("new", "under_evaluation"):
            response = self.client_for(self.doctor_a).patch(case_url(self.case_1), {"status": old}, format="json")
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_status_migration_maps_non_closed_to_in_treatment(self):
        from importlib import import_module

        from django.apps import apps

        migration = import_module("cases.migrations.0018_case_status_two_values")
        Case.objects.filter(pk=self.case_1.pk).update(status="new")
        Case.objects.filter(pk=self.case_2.pk).update(status="under_evaluation")
        Case.objects.filter(pk=self.orphan_case.pk).update(status=CaseStatus.CLOSED)
        migration.to_two_statuses(apps, None)
        statuses = dict(Case.objects.values_list("pk", "status"))
        self.assertEqual(statuses[self.case_1.pk], CaseStatus.IN_TREATMENT)
        self.assertEqual(statuses[self.case_2.pk], CaseStatus.IN_TREATMENT)
        self.assertEqual(statuses[self.orphan_case.pk], CaseStatus.CLOSED)

    def test_doctor_cannot_reassign_existing_case_to_another_doctor(self):
        response = self.client_for(self.doctor_a).patch(
            case_url(self.case_1), {"doctor": self.doctor_b.pk}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.case_1.refresh_from_db()
        self.assertEqual(self.case_1.doctor, self.doctor_a)

    def test_manager_can_assign_doctor(self):
        response = self.client_for(self.manager).patch(
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
        for user in (self.doctor_a, self.manager):
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
        attack = AttackEvent.objects.create(case=self.case_1, occurred_at=timezone.now(),
                                            duration_seconds=600, severity=5, took_medication=False)
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
        self.assertTrue(AttackEvent.objects.filter(pk=attack.pk, case=self.case_1).exists())
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
            response = self.client_for(self.manager).post(
                CASES, {"patient": self.patient_1.pk, "diagnosis_type": "migraine"}, format="json"
            )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("حالة نشطة", response.data["detail"])

    def test_concurrent_device_link_returns_400_not_500(self):
        with mock.patch.object(CaseSerializer, "validate", lambda self, attrs: attrs):
            response = self.client_for(self.manager).post(
                CASES,
                {"patient": self.patient_4.pk, "diagnosis_type": "migraine", "device": str(self.device_1.pk)},
                format="json",
            )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("الجهاز", response.data["detail"])


class DefaultDenyTests(CareWorldMixin, APITestCase):
    """H1: أي دور غير patient/doctor/engineer لا يرى شيئاً."""

    def setUp(self):
        AttackEvent.objects.create(
            case=self.case_1, occurred_at=timezone.now(), duration_seconds=60,
            severity=3, took_medication=False,
        )

    def test_unknown_role_sees_nothing(self):
        client = self.client_for(self.no_role)
        for url in (CASES, "/api/attack-events/", "/api/attack-log-confirmations/"):
            response = client.get(url)
            self.assertEqual(response.status_code, status.HTTP_200_OK, url)
            self.assertEqual(results(response), [], url)

    def test_unknown_role_cannot_create_case(self):
        response = self.client_for(self.no_role).post(
            CASES, {"patient": self.patient_4.pk, "diagnosis_type": "migraine"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_engineer_still_sees_everything(self):
        response = self.client_for(self.engineer).get(CASES)
        self.assertEqual(len(results(response)), 3)


class CaseListQueryCountTests(CareWorldMixin, APITestCase):
    """P1: عدد استعلامات قائمة الحالات ثابت مهما زادت الحالات (لا N+1)."""

    # count (الترقيم) + الحالات مع JOIN وعدد الجلسات
    EXPECTED_QUERIES = 2

    def add_cases(self, n):
        for i in range(n):
            patient = make_user(f"extra_patient_{i}", "patient")
            case = Case.objects.create(patient=patient, doctor=self.doctor_a, diagnosis_type="migraine")
            TreatmentSession.objects.create(case=case, session_date=timezone.now())

    def test_case_list_query_count_is_constant(self):
        client = self.client_for(self.engineer)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            client.get(CASES)
        self.add_cases(5)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            response = client.get(CASES)
        self.assertEqual(response.data["count"], 8)

    def test_query_count_is_constant_with_clinic_engineers(self):
        client = self.client_for(self.engineer)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            client.get(CASES)
        for i in range(5):
            engineer = make_user(f"clinic_engineer_{i}", "engineer")
            clinic = Clinic.objects.create(name=f"Clinic {i}", responsible_engineer=engineer)
            device = Device.objects.create(serial_number=f"SN-E{i}", clinic=clinic)
            patient = make_user(f"engineer_patient_{i}", "patient")
            Case.objects.create(patient=patient, doctor=self.doctor_a, device=device, diagnosis_type="migraine")
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            response = client.get(CASES)
        self.assertEqual(response.data["count"], 8)

    def test_responsible_engineer_name(self):
        self.engineer.first_name, self.engineer.last_name = "Omar", "Saleh"
        self.engineer.save()
        Clinic.objects.create(name="Assigned", responsible_engineer=self.engineer)
        self.device_1.clinic = Clinic.objects.get(name="Assigned")
        self.device_1.save()
        self.device_2.clinic = Clinic.objects.create(name="No engineer")
        self.device_2.save()
        data = {c["id"]: c for c in results(self.client_for(self.engineer).get(CASES))}
        self.assertEqual(data[self.case_1.pk]["responsible_engineer_name"], "Omar Saleh")
        self.assertIsNone(data[self.case_2.pk]["responsible_engineer_name"])  # clinic without engineer
        self.assertIsNone(data[self.orphan_case.pk]["responsible_engineer_name"])  # no device

    def test_session_counts_are_still_correct(self):
        TreatmentSession.objects.create(case=self.case_1, session_date=timezone.now())
        Case.objects.filter(pk=self.case_1.pk).update(total_sessions_planned=10)
        data = {c["id"]: c for c in results(self.client_for(self.engineer).get(CASES))}
        self.assertEqual(data[self.case_1.pk]["completed_sessions_count"], 2)
        self.assertEqual(data[self.case_1.pk]["remaining_sessions_count"], 8)
        self.assertEqual(data[self.case_2.pk]["completed_sessions_count"], 1)


class PaginationTests(CareWorldMixin, APITestCase):
    """P4: القوائم مرقّمة، والحد الأقصى للصفحة 200."""

    def test_list_is_paginated(self):
        response = self.client_for(self.engineer).get(CASES, {"page_size": 2})
        self.assertEqual(response.data["count"], 3)
        self.assertEqual(len(response.data["results"]), 2)
        self.assertIsNotNone(response.data["next"])

    def test_page_size_is_capped(self):
        for i in range(205):
            make_user(f"bulk_{i}", "patient")
        response = self.client_for(self.engineer).get("/api/patients/", {"page_size": 1000})
        self.assertEqual(len(response.data["results"]), 200)


class InvalidQueryParamTests(CareWorldMixin, APITestCase):
    """Q13: معاملات فلترة غير صالحة ترجع 400 وليس 500."""

    def test_invalid_filters_return_400(self):
        client = self.client_for(self.engineer)
        for url, params in (
            (CASES, {"device": "abc"}),
            ("/api/attack-events/", {"case": "abc"}),
            ("/api/attack-log-confirmations/", {"case": "abc"}),
            ("/api/sessions/", {"case": "abc"}),
            ("/api/sessions/", {"case": "-1"}),
            ("/api/devices/", {"exclude_case": "abc"}),
            ("/api/devices/", {"available": "true", "exclude_case": "1.5"}),
        ):
            response = client.get(url, params)
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST, (url, params))

    def test_valid_filters_still_work(self):
        client = self.client_for(self.engineer)
        response = client.get(CASES, {"device": str(self.device_1.pk)})
        self.assertEqual([c["id"] for c in results(response)], [self.case_1.pk])
        response = client.get("/api/sessions/", {"case": self.case_2.pk})
        self.assertEqual([s["id"] for s in results(response)], [self.session_2.pk])



class RelatedNameQueryCountTests(CareWorldMixin, APITestCase):
    """Related 1: أسماء الكاتب/المنفّذ تُجلب بـ JOIN، لا استعلام لكل صف."""

    # count (الترقيم) + القائمة مع JOIN على المستخدم
    EXPECTED_QUERIES = 2

    def assert_constant(self, url, add_rows):
        # صف واحد على الأقل قبل القياس الأول: مع قائمة فارغة يكتفي DRF باستعلام العدّ
        add_rows(1)
        client = self.client_for(self.engineer)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            client.get(url)
        add_rows(5)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            response = client.get(url)
        self.assertGreaterEqual(response.data["count"], 5)

    def test_sessions(self):
        def add_rows(n):
            for _ in range(n):
                performer = make_user(f"performer_{TreatmentSession.objects.count()}", "doctor")
                TreatmentSession.objects.create(
                    case=self.case_1, performed_by=performer, session_date=timezone.now()
                )
        self.assert_constant("/api/sessions/", add_rows)


class OrderingTiebreakerTests(CareWorldMixin, APITestCase):
    """Related 2: صفوف بنفس قيمة الترتيب لا تتكرر ولا تختفي بين الصفحات."""

    def walk_pages(self, url):
        client = self.client_for(self.engineer)
        ids, page = [], 1
        while True:
            response = client.get(url, {"page": page, "page_size": 1})
            ids += [row["id"] for row in results(response)]
            if response.data["next"] is None:
                return ids
            page += 1

    def test_cases_with_same_created_at(self):
        Case.objects.update(created_at=timezone.now())
        ids = self.walk_pages(CASES)
        self.assertEqual(ids, sorted(ids, reverse=True))  # -created_at ثم -id
        self.assertEqual(len(ids), len(set(ids)))

    def test_sessions_with_same_session_date(self):
        same = timezone.now()
        for _ in range(3):
            TreatmentSession.objects.create(case=self.case_1, session_date=same)
        TreatmentSession.objects.update(session_date=same)
        ids = self.walk_pages("/api/sessions/")
        self.assertEqual(ids, sorted(ids, reverse=True))
        self.assertEqual(set(ids), set(TreatmentSession.objects.values_list("id", flat=True)))


class CaseDeviceDetailsTests(CareWorldMixin, APITestCase):
    """ملخص الحالة يعرض رقم الجهاز وعيادته — بدون استعلام إضافي لكل حالة."""

    def test_serial_number_and_clinic_name(self):
        clinic = Clinic.objects.create(name="Baghdad Clinic")
        self.device_1.clinic = clinic
        self.device_1.save()
        data = {c["id"]: c for c in results(self.client_for(self.engineer).get(CASES))}
        self.assertEqual(data[self.case_1.pk]["device_serial_number"], "SN-1")
        self.assertEqual(data[self.case_1.pk]["clinic_name"], "Baghdad Clinic")
        self.assertIsNone(data[self.case_2.pk]["clinic_name"])
        self.assertIsNone(data[self.orphan_case.pk]["device_serial_number"])


class ManagerOnlyCaseWriteTests(CareWorldMixin, APITestCase):
    """إنشاء/تعديل/حذف الحالات عبر الـ API: الطبيب لحالاته، والمدير لكل الحالات،
    والمهندس العادي قراءة فقط."""

    def test_regular_engineer_reads_but_cannot_write(self):
        client = self.client_for(self.engineer)
        self.assertEqual(client.get(case_url(self.case_1)).status_code, status.HTTP_200_OK)
        response = client.post(CASES, {"patient": self.patient_4.pk, "diagnosis_type": "migraine"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        response = client.patch(case_url(self.case_1), {"treatment_plan": "x"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(client.delete(case_url(self.orphan_case)).status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(Case.objects.filter(pk=self.orphan_case.pk).exists())
        self.assertFalse(Case.objects.filter(patient=self.patient_4).exists())

    def test_manager_creates_edits_and_deletes(self):
        client = self.client_for(self.manager)
        response = client.post(CASES, {"patient": self.patient_4.pk, "diagnosis_type": "migraine"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        response = client.patch(case_url(self.case_1), {"treatment_plan": "x"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(client.delete(case_url(self.orphan_case)).status_code, status.HTTP_204_NO_CONTENT)

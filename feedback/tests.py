from rest_framework import status
from rest_framework.test import APITestCase

from config.testing import CareWorldMixin, make_user, results
from treatments.models import TreatmentSession

from .models import Feedback

FEEDBACK = "/api/feedback/"


def feedback_url(feedback):
    return f"{FEEDBACK}{feedback.pk}/"


class FeedbackOwnershipTests(CareWorldMixin, APITestCase):
    """C3: التقييم على جلسات المستخدم فقط، ويعدّله كاتبه فقط."""

    def setUp(self):
        self.doctor_feedback = Feedback.objects.create(
            session=self.session_1, submitted_by=self.doctor_a, source="doctor", rating=4
        )
        self.patient_feedback = Feedback.objects.create(
            session=self.session_1, submitted_by=self.patient_1, source="patient", rating=3
        )

    def test_patient_cannot_rate_another_patients_session(self):
        response = self.client_for(self.patient_1).post(
            FEEDBACK, {"session": self.session_2.pk, "rating": 5}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(Feedback.objects.filter(session=self.session_2).exists())

    def test_doctor_cannot_rate_other_doctors_session(self):
        response = self.client_for(self.doctor_a).post(
            FEEDBACK, {"session": self.session_2.pk, "rating": 5}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_patient_rates_own_session(self):
        response = self.client_for(self.patient_1).post(
            FEEDBACK, {"session": self.session_1.pk, "rating": 5, "comment": "ok"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["source"], "patient")

    def test_rating_must_be_between_1_and_5(self):
        client = self.client_for(self.patient_1)
        for rating in (0, 6, 99):
            response = client.post(FEEDBACK, {"session": self.session_1.pk, "rating": rating}, format="json")
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST, rating)

    def test_patient_cannot_edit_or_delete_doctors_feedback(self):
        client = self.client_for(self.patient_1)
        response = client.patch(feedback_url(self.doctor_feedback), {"rating": 1}, format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(client.delete(feedback_url(self.doctor_feedback)).status_code, status.HTTP_403_FORBIDDEN)
        self.doctor_feedback.refresh_from_db()
        self.assertEqual(self.doctor_feedback.rating, 4)

    def test_doctor_cannot_delete_patients_feedback(self):
        response = self.client_for(self.doctor_a).delete(feedback_url(self.patient_feedback))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_author_can_edit_own_feedback(self):
        response = self.client_for(self.patient_1).patch(
            feedback_url(self.patient_feedback), {"rating": 5}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_cannot_move_feedback_to_another_session(self):
        other_own_session = TreatmentSession.objects.create(
            case=self.case_1, session_date=self.session_1.session_date
        )
        response = self.client_for(self.patient_1).patch(
            feedback_url(self.patient_feedback), {"session": other_own_session.pk}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_engineer_can_read_all_feedback(self):
        self.assertEqual(len(results(self.client_for(self.engineer).get(FEEDBACK))), 2)

    def test_engineer_cannot_add_feedback(self):
        # قرار عمل: التقييم من المريض أو الطبيب فقط، حتى على جلسة يراها المهندس
        response = self.client_for(self.engineer).post(
            FEEDBACK, {"session": self.session_1.pk, "rating": 5, "comment": "x"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Feedback.objects.filter(submitted_by=self.engineer).exists())

    def test_engineer_cannot_edit_others_feedback(self):
        response = self.client_for(self.engineer).patch(
            feedback_url(self.doctor_feedback), {"rating": 1}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_unknown_role_sees_nothing(self):
        self.assertEqual(results(self.client_for(self.no_role).get(FEEDBACK)), [])



class FeedbackQueryCountTests(CareWorldMixin, APITestCase):
    """Related 1: اسم كاتب التقييم يُجلب بـ JOIN."""

    def test_feedback_list_query_count_is_constant(self):
        def add_rows(n):
            for _ in range(n):
                author = make_user(f"rater_{Feedback.objects.count()}", "patient")
                Feedback.objects.create(session=self.session_1, submitted_by=author, source="patient", rating=3)

        client = self.client_for(self.engineer)
        # صف واحد قبل القياس الأول: مع قائمة فارغة يكتفي DRF باستعلام العدّ
        add_rows(1)
        with self.assertNumQueries(2):
            client.get(FEEDBACK)
        add_rows(5)
        with self.assertNumQueries(2):
            response = client.get(FEEDBACK)
        self.assertEqual(response.data["count"], 6)

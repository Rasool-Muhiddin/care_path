from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken

from cases.models import AttackEvent, AttackLogConfirmation, Case, CaseStatus
from chat.models import ChatMessage, InquiryType
from config.testing import PASSWORD, CareWorldMixin
from devices.models import Clinic
from notifications.models import DeviceToken
from treatments.models import TreatmentSession

from .models import User

URL = "/api/auth/delete-account/"


class AccountDeletionTests(CareWorldMixin, APITestCase):
    def delete(self, user, password=PASSWORD):
        return self.client_for(user).post(URL, {"password": password}, format="json")

    def test_requires_authentication(self):
        self.assertEqual(self.client_for().post(URL, {"password": PASSWORD}).status_code, 401)

    def test_wrong_password_deletes_nothing(self):
        response = self.delete(self.patient_1, "wrong-password")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", response.data)
        self.assertTrue(User.objects.filter(pk=self.patient_1.pk).exists())
        self.assertTrue(Case.objects.filter(pk=self.case_1.pk).exists())

    def test_patient_deletes_account_and_all_data(self):
        AttackEvent.objects.create(case=self.case_1, occurred_at=timezone.now(), duration_seconds=60,
                                   severity=5, took_medication=False)
        AttackLogConfirmation.objects.create(case=self.case_1, had_unlogged=False)
        ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="hi")
        ChatMessage.objects.create(case=self.case_1, sender=self.doctor_a, text="reply")
        DeviceToken.objects.create(user=self.patient_1, token="fcm-1", platform="android")
        refresh = RefreshToken.for_user(self.patient_1)

        self.assertEqual(self.delete(self.patient_1).status_code, status.HTTP_204_NO_CONTENT)

        self.assertFalse(User.objects.filter(pk=self.patient_1.pk).exists())
        self.assertFalse(Case.objects.filter(pk=self.case_1.pk).exists())
        self.assertFalse(TreatmentSession.objects.filter(case_id=self.case_1.pk).exists())
        self.assertFalse(AttackEvent.objects.filter(case_id=self.case_1.pk).exists())
        self.assertFalse(AttackLogConfirmation.objects.filter(case_id=self.case_1.pk).exists())
        self.assertFalse(ChatMessage.objects.filter(case_id=self.case_1.pk).exists())
        self.assertFalse(DeviceToken.objects.filter(token="fcm-1").exists())
        # the refresh token is blacklisted and can't be used again
        self.assertTrue(BlacklistedToken.objects.filter(token__jti=refresh["jti"]).exists())
        response = self.client.post("/api/auth/refresh/", {"refresh": str(refresh)}, format="json")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        # the device is free again
        available = self.client_for(self.engineer).get("/api/devices/", {"available": "true"}).data["results"]
        self.assertIn(str(self.device_1.pk), [d["id"] for d in available])
        # other patients are untouched
        self.assertTrue(Case.objects.filter(pk=self.case_2.pk).exists())

    def test_doctor_with_open_case_is_blocked(self):
        info = self.client_for(self.doctor_a).get(URL).data
        self.assertEqual((info["can_delete"], info["code"]), (False, "doctor_has_active_cases"))
        response = self.delete(self.doctor_a)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["code"], "doctor_has_active_cases")
        self.assertIn("Tera", response.data["detail"])
        self.assertTrue(User.objects.filter(pk=self.doctor_a.pk).exists())

    def test_doctor_without_open_cases_keeps_closed_cases(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        message = ChatMessage.objects.create(case=self.case_1, sender=self.doctor_a, text="advice")
        self.assertTrue(self.client_for(self.doctor_a).get(URL).data["can_delete"])
        self.assertEqual(self.delete(self.doctor_a).status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(pk=self.doctor_a.pk).exists())
        case = Case.objects.get(pk=self.case_1.pk)
        self.assertIsNone(case.doctor)
        self.assertEqual(case.status, CaseStatus.CLOSED)
        message.refresh_from_db()
        self.assertIsNone(message.sender)

    def test_engineer_deletion_keeps_messages_and_frees_clinic(self):
        clinic = Clinic.objects.create(name="Clinic", responsible_engineer=self.engineer)
        message = ChatMessage.objects.create(case=self.case_1, sender=self.engineer, text="restart it",
                                             inquiry_type=InquiryType.TECHNICAL)
        self.assertEqual(self.delete(self.engineer).status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(pk=self.engineer.pk).exists())
        clinic.refresh_from_db()
        self.assertIsNone(clinic.responsible_engineer)
        message.refresh_from_db()
        self.assertIsNone(message.sender)
        response = self.client_for(self.patient_1).get(
            f"/api/chat/cases/{self.case_1.pk}/messages/", {"inquiry_type": "technical"}
        )
        row = next(m for m in response.data if m["id"] == message.pk)
        self.assertEqual((row["sender"], row["sender_name"], row["sender_role"]), (None, "Deleted user", None))

    def test_manager_and_superuser_are_blocked(self):
        for user in (self.manager, self.no_role):
            self.assertFalse(self.client_for(user).get(URL).data["can_delete"])
            response = self.delete(user)
            self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
            self.assertEqual(response.data["code"], "manager_account")
            self.assertTrue(User.objects.filter(pk=user.pk).exists())

    def test_tokens_of_other_users_are_untouched(self):
        other = RefreshToken.for_user(self.patient_2)
        self.delete(self.patient_1)
        self.assertTrue(OutstandingToken.objects.filter(jti=other["jti"]).exists())
        self.assertFalse(BlacklistedToken.objects.filter(token__jti=other["jti"]).exists())


class AccountDeletionPageTests(APITestCase):
    def test_public_page_in_arabic_and_english(self):
        response = self.client.get("/account-deletion/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        content = response.content.decode()
        self.assertIn("حذف الحساب", content)
        self.assertIn("Delete account", content)
        self.assertIn("WhatsApp", content)


class PrivacyPolicyPageTests(APITestCase):
    def test_public_page_in_arabic_and_english(self):
        response = self.client.get("/privacy/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        content = response.content.decode()
        self.assertIn("سياسة الخصوصية", content)
        self.assertIn("Privacy policy", content)
        self.assertIn("TODO(publisher)", content)

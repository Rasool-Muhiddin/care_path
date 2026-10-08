from rest_framework import status
from rest_framework.test import APIClient, APITestCase

from config.testing import PASSWORD, make_user, results

from .models import User, UserRole

REGISTER = "/api/auth/register/"


def new_user(role, username="new_user"):
    return {"username": username, "password": "Str0ng!pass-123", "role": role, "first_name": "New"}


class RegisterTests(APITestCase):
    """لا تسجيل ذاتي: الطبيب ينشئ مرضى فقط، والمهندس مرضى أو أطباء، والمهندسون من admin فقط."""

    @classmethod
    def setUpTestData(cls):
        cls.doctor = make_user("doctor", UserRole.DOCTOR)
        cls.engineer = make_user("engineer", UserRole.ENGINEER)
        cls.patient = make_user("patient", UserRole.PATIENT)

    def post_as(self, user, payload):
        client = APIClient()
        if user is not None:
            client.force_authenticate(user)
        return client.post(REGISTER, payload, format="json")

    def test_doctor_creates_patient(self):
        response = self.post_as(self.doctor, new_user(UserRole.PATIENT))
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertNotIn("password", response.data)
        created = User.objects.get(username="new_user")
        self.assertEqual(created.role, UserRole.PATIENT)
        self.assertTrue(created.check_password("Str0ng!pass-123"))

    def test_doctor_cannot_create_doctor(self):
        response = self.post_as(self.doctor, new_user(UserRole.DOCTOR))
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(User.objects.filter(username="new_user").exists())

    def test_engineer_creates_doctor(self):
        response = self.post_as(self.engineer, new_user(UserRole.DOCTOR))
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_nobody_creates_engineers_through_api(self):
        for creator in (self.doctor, self.engineer):
            response = self.post_as(creator, new_user(UserRole.ENGINEER))
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(User.objects.filter(username="new_user").exists())

    def test_patient_and_anonymous_cannot_register_users(self):
        self.assertEqual(self.post_as(self.patient, new_user(UserRole.PATIENT)).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.post_as(None, new_user(UserRole.PATIENT)).status_code, status.HTTP_401_UNAUTHORIZED)


class UserListTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.doctor = make_user("doctor", UserRole.DOCTOR)
        cls.engineer = make_user("engineer", UserRole.ENGINEER)
        cls.patient = make_user("patient", UserRole.PATIENT)

    def get_as(self, user, url):
        client = APIClient()
        client.force_authenticate(user)
        return client.get(url)

    def test_patient_cannot_list_users(self):
        for url in ("/api/patients/", "/api/doctors/", "/api/engineers/"):
            self.assertEqual(self.get_as(self.patient, url).status_code, status.HTTP_403_FORBIDDEN, url)

    def test_doctor_lists_patients_only(self):
        self.assertEqual(self.get_as(self.doctor, "/api/patients/").status_code, status.HTTP_200_OK)
        self.assertEqual(self.get_as(self.doctor, "/api/doctors/").status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.get_as(self.doctor, "/api/engineers/").status_code, status.HTTP_403_FORBIDDEN)

    def test_engineer_lists_everyone(self):
        response = self.get_as(self.engineer, "/api/doctors/")
        self.assertEqual([d["username"] for d in results(response)], ["doctor"])
        self.assertEqual(self.get_as(self.engineer, "/api/engineers/").status_code, status.HTTP_200_OK)

    def test_me_returns_role(self):
        response = self.get_as(self.patient, "/api/auth/me/")
        self.assertEqual(response.data["role"], UserRole.PATIENT)
        self.assertEqual(response.data["username"], "patient")


class InactiveAccountTests(APITestCase):
    """تعطيل الحساب يتم بـ User.is_active (حذفنا is_active_account الذي لم يكن يُقرأ أصلاً)."""

    def test_inactive_user_cannot_log_in(self):
        user = make_user("inactive", UserRole.PATIENT)
        user.is_active = False
        user.save(update_fields=["is_active"])
        response = APIClient().post(
            "/api/auth/login/", {"username": "inactive", "password": PASSWORD}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

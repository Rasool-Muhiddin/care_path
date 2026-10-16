from io import StringIO

from django.core.management import CommandError, call_command
from django.test import TestCase

from accounts.models import User, UserRole
from cases.models import Case, CaseStatus
from devices.models import Clinic, Device


class SeedDemoDataTests(TestCase):
    def setUp(self):
        self.rasool = User.objects.create_superuser("rasool", "r@example.com", "owner-pass", role=UserRole.ENGINEER)
        User.objects.create_user("old_patient", password="x", role=UserRole.PATIENT)

    def test_requires_yes_and_keeps_data(self):
        with self.assertRaises(CommandError):
            call_command("seed_demo_data")
        self.assertTrue(User.objects.filter(username="old_patient").exists())

    def test_refuses_without_rasool(self):
        self.rasool.delete()
        with self.assertRaises(CommandError):
            call_command("seed_demo_data", "--yes", stdout=StringIO())
        self.assertTrue(User.objects.filter(username="old_patient").exists())

    def test_seeds_and_is_rerunnable(self):
        before = User.objects.values().get(pk=self.rasool.pk)
        for _ in range(2):
            call_command("seed_demo_data", "--yes", stdout=StringIO())

        self.assertEqual(User.objects.values().get(pk=self.rasool.pk), before)
        self.assertFalse(User.objects.filter(username="old_patient").exists())
        self.assertEqual(User.objects.filter(role=UserRole.PATIENT).count(), 5)
        self.assertEqual(
            set(User.objects.filter(is_manager=True).values_list("username", flat=True)), {"amir"}
        )
        self.assertTrue(User.objects.get(username="ahmed").check_password("aassddff"))
        self.assertEqual(Clinic.objects.count(), 2)
        self.assertFalse(Clinic.objects.filter(responsible_engineer=self.rasool).exists())
        self.assertEqual(Device.objects.count(), 4)
        self.assertEqual(Case.objects.filter(status=CaseStatus.CLOSED).count(), 1)
        # the returned device is reused by Patient 1
        closed = Case.objects.get(status=CaseStatus.CLOSED)
        self.assertTrue(
            Case.objects.filter(device=closed.device, status=CaseStatus.IN_TREATMENT,
                                patient__username="zainab.ali").exists()
        )

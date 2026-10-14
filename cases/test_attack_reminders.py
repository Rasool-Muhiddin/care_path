from datetime import timedelta
from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import AccessToken

from accounts.models import User
from config.testing import CareWorldMixin
from notifications.models import DeviceToken

from .management.commands.send_attack_reminders import BODY, patients_due_for_reminder
from .models import AttackEvent, Case, CaseStatus


class LastSeenTrackingTests(CareWorldMixin, TestCase):
    def get_with_token(self, user):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {AccessToken.for_user(user)}")
        return client.get("/api/cases/")

    def test_authenticated_request_updates_last_seen_at_most_hourly(self):
        self.assertEqual(self.get_with_token(self.patient_1).status_code, 200)
        first = User.objects.get(pk=self.patient_1.pk).last_seen_at
        self.assertIsNotNone(first)

        self.get_with_token(self.patient_1)
        self.assertEqual(User.objects.get(pk=self.patient_1.pk).last_seen_at, first)

        User.objects.filter(pk=self.patient_1.pk).update(last_seen_at=first - timedelta(hours=2))
        self.get_with_token(self.patient_1)
        self.assertGreater(User.objects.get(pk=self.patient_1.pk).last_seen_at, first - timedelta(hours=2))


class AttackReminderTests(CareWorldMixin, TestCase):
    def setUp(self):
        old = timezone.now() - timedelta(days=4)
        User.objects.update(last_seen_at=old, date_joined=old - timedelta(days=30))
        for user in (self.patient_1, self.patient_2, self.patient_3, self.patient_4, self.doctor_a):
            DeviceToken.objects.create(user=user, token=f"tok-{user.pk}", platform="android")

    def due(self):
        return set(patients_due_for_reminder().values_list("username", flat=True))

    def test_inactive_patients_with_open_case_and_token_are_due(self):
        # patient_4 بلا حالة، والطبيب ليس مريضاً
        self.assertEqual(self.due(), {"patient_1", "patient_2", "patient_3"})

    def test_recently_seen_patient_not_due(self):
        User.objects.filter(pk=self.patient_1.pk).update(last_seen_at=timezone.now() - timedelta(days=1))
        self.assertNotIn("patient_1", self.due())

    def test_recent_attack_log_not_due(self):
        AttackEvent.objects.create(case=self.case_1, occurred_at=timezone.now(), duration_seconds=60,
                                   severity=3, took_medication=False)
        self.assertNotIn("patient_1", self.due())

    def test_closed_case_or_no_token_not_due(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        DeviceToken.objects.filter(user=self.patient_2).delete()
        self.assertEqual(self.due(), {"patient_3"})

    def test_reminder_at_most_every_three_days(self):
        with mock.patch("notifications.services.send_push_to_users") as send:
            call_command("send_attack_reminders", stdout=StringIO())
            self.assertEqual(send.call_count, 1)
            self.assertEqual(send.call_args.kwargs["body"], BODY)
            self.assertEqual(send.call_args.kwargs["data"], {"type": "attack_reminder"})
            self.assertEqual(len(send.call_args.args[0]), 3)

            call_command("send_attack_reminders", stdout=StringIO())
            self.assertEqual(send.call_count, 1)  # لا تذكير ثانٍ قبل مرور 3 أيام

        User.objects.update(attack_reminder_sent_at=timezone.now() - timedelta(days=4))
        self.assertEqual(len(self.due()), 3)

    def test_dry_run_sends_nothing(self):
        with mock.patch("notifications.services.send_push_to_users") as send:
            out = StringIO()
            call_command("send_attack_reminders", "--dry-run", stdout=out)
        send.assert_not_called()
        self.assertIn("3 patient(s)", out.getvalue())


class LastSeenBackfillMigrationTests(CareWorldMixin, TestCase):
    def test_backfill_marks_existing_users_as_seen_now(self):
        from importlib import import_module

        from django.apps import apps

        User.objects.update(last_seen_at=None, date_joined=timezone.now() - timedelta(days=30))
        DeviceToken.objects.create(user=self.patient_1, token="tok-backfill", platform="android")
        self.assertIn(self.patient_1, patients_due_for_reminder())  # بدون backfill: تذكير فوري

        migration = import_module("accounts.migrations.0004_backfill_last_seen_at")
        migration.backfill_last_seen(apps, None)

        self.assertFalse(User.objects.filter(last_seen_at__isnull=True).exists())
        self.assertEqual(set(patients_due_for_reminder()), set())

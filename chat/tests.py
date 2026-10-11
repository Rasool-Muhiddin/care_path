from unittest import mock

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import UserRole
from config.testing import CareWorldMixin, make_user
from devices.models import Clinic, Device

from .models import ChatMessage, InquiryType
from .notifications import notify_message_by_id, notify_new_message
from .views import CHAT_PAGE_SIZE


def messages_url(case):
    return f"/api/chat/cases/{case.pk}/messages/"


# لا نرسل إشعارات FCM حقيقية أثناء الاختبارات
@mock.patch("chat.views.notify_in_background")
class ChatPermissionTests(CareWorldMixin, APITestCase):
    def setUp(self):
        ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="medical",
                                   inquiry_type=InquiryType.MEDICAL)
        ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="technical",
                                   inquiry_type=InquiryType.TECHNICAL)

    def test_anonymous_gets_401_on_case_without_doctor(self, _notify):
        # H2: كان الطلب المجهول يجتاز الفحص لأن doctor_id == user.id == None
        client = self.client_for()
        self.assertEqual(client.get(messages_url(self.orphan_case)).status_code, status.HTTP_401_UNAUTHORIZED)
        response = client.post(messages_url(self.orphan_case), {"text": "hi"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertFalse(ChatMessage.objects.filter(case=self.orphan_case).exists())

    def test_other_patient_and_doctor_are_forbidden(self, _notify):
        for user in (self.patient_2, self.doctor_b):
            self.assertEqual(
                self.client_for(user).get(messages_url(self.case_1)).status_code,
                status.HTTP_403_FORBIDDEN,
            )

    def test_unknown_role_is_forbidden(self, _notify):
        response = self.client_for(self.no_role).get(messages_url(self.case_1))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_doctor_never_sees_technical_channel(self, _notify):
        response = self.client_for(self.doctor_a).get(
            messages_url(self.case_1), {"inquiry_type": "technical"}
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([m["text"] for m in response.data], [])

    def test_engineer_cannot_write_in_medical_channel(self, _notify):
        response = self.client_for(self.engineer).post(
            messages_url(self.case_1), {"text": "x", "inquiry_type": "medical"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_participant_can_send(self, notify):
        # الإشعار يُجدول بعد نجاح الحفظ (on_commit) وليس داخل الطلب
        with self.captureOnCommitCallbacks(execute=False) as callbacks:
            response = self.client_for(self.patient_1).post(
                messages_url(self.case_1), {"text": "hello", "inquiry_type": "medical"}, format="json"
            )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        notify.assert_not_called()
        self.assertEqual(len(callbacks), 1)
        callbacks[0]()
        notify.assert_called_once_with(response.data["id"])

    def test_unread_count_for_unknown_role_is_empty(self, _notify):
        response = self.client_for(self.no_role).get("/api/chat/unread-count/")
        self.assertEqual(response.data, {"total_unread": 0, "by_case": {}})

    def test_unread_count_doctor_only_counts_own_medical(self, _notify):
        response = self.client_for(self.doctor_a).get("/api/chat/unread-count/")
        self.assertEqual(response.data, {"total_unread": 1, "by_case": {self.case_1.pk: 1}})


class GenericNotificationTests(CareWorldMixin, APITestCase):
    """C5: الإشعار لا يحمل نص الرسالة الطبية ولا اسم المرسل."""

    @mock.patch("notifications.services.send_push_to_users")
    def test_push_text_is_generic(self, send_push):
        message = ChatMessage.objects.create(
            case=self.case_1, sender=self.patient_1, text="أعاني من صداع شديد منذ أمس",
            inquiry_type=InquiryType.MEDICAL,
        )
        notify_new_message(message)

        send_push.assert_called_once()
        recipients = send_push.call_args.args[0]
        kwargs = send_push.call_args.kwargs
        self.assertEqual(recipients, [self.doctor_a])
        self.assertEqual(kwargs["body"], "لديك رسالة جديدة")
        self.assertNotIn("صداع", kwargs["title"] + kwargs["body"])
        self.assertNotIn(self.patient_1.username, kwargs["title"])
        self.assertEqual(kwargs["data"]["case_id"], self.case_1.pk)



@mock.patch("chat.views.notify_in_background")
class ChatPollingTests(CareWorldMixin, APITestCase):
    """P3 + P5: عدّاد غير المقروء باستعلام واحد، والـ polling التزايدي."""

    def add_message(self, case, sender, inquiry_type=InquiryType.MEDICAL, text="m"):
        return ChatMessage.objects.create(case=case, sender=sender, text=text, inquiry_type=inquiry_type)

    def test_unread_count_is_one_query(self, _notify):
        client = self.client_for(self.engineer)
        with self.assertNumQueries(1):
            client.get("/api/chat/unread-count/")
        for case in (self.case_1, self.case_2, self.orphan_case):
            for _ in range(3):
                self.add_message(case, case.patient, InquiryType.TECHNICAL)
        with self.assertNumQueries(1):
            response = client.get("/api/chat/unread-count/")
        self.assertEqual(response.data["total_unread"], 9)
        self.assertEqual(
            response.data["by_case"],
            {self.case_1.pk: 3, self.case_2.pk: 3, self.orphan_case.pk: 3},
        )

    def test_after_id_returns_only_newer_messages(self, _notify):
        old = self.add_message(self.case_1, self.patient_1, text="old")
        new = self.add_message(self.case_1, self.patient_1, text="new")
        response = self.client_for(self.doctor_a).get(
            messages_url(self.case_1), {"inquiry_type": "medical", "after_id": old.pk}
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([m["id"] for m in response.data], [new.pk])

    def test_after_id_marks_only_new_messages_read(self, _notify):
        old = self.add_message(self.case_1, self.patient_1)
        new = self.add_message(self.case_1, self.patient_1)
        self.client_for(self.doctor_a).get(messages_url(self.case_1), {"after_id": old.pk})
        old.refresh_from_db()
        new.refresh_from_db()
        self.assertFalse(old.is_read)
        self.assertTrue(new.is_read)

    def test_message_list_query_count_is_constant(self, _notify):
        client = self.client_for(self.doctor_a)
        url = messages_url(self.case_1)
        with CaptureQueriesContext(connection) as before:
            client.get(url)
        for _ in range(5):
            self.add_message(self.case_1, self.patient_1)
        with CaptureQueriesContext(connection) as after:
            client.get(url)
        self.assertEqual(len(before), len(after))

    def test_invalid_after_id_returns_400(self, _notify):
        response = self.client_for(self.doctor_a).get(messages_url(self.case_1), {"after_id": "abc"})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_messages_are_not_paginated(self, _notify):
        response = self.client_for(self.doctor_a).get(messages_url(self.case_1))
        self.assertIsInstance(response.data, list)


class BackgroundNotificationTests(CareWorldMixin, APITestCase):
    @mock.patch("chat.notifications.notify_new_message")
    def test_notify_by_id_loads_message_and_sends(self, notify):
        message = ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="x")
        with mock.patch("chat.notifications.connection") as conn:
            notify_message_by_id(message.pk)
        notify.assert_called_once_with(message)
        conn.close.assert_called_once()

    @mock.patch("chat.notifications.notify_new_message", side_effect=RuntimeError("fcm down"))
    def test_notify_by_id_never_raises(self, _notify):
        message = ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text="x")
        with mock.patch("chat.notifications.connection"):
            notify_message_by_id(message.pk)  # يُسجَّل الخطأ فقط



@mock.patch("chat.views.notify_in_background")
class ChatHistoryPagingTests(CareWorldMixin, APITestCase):
    """Related 3: أول فتح يرجع آخر 50 رسالة، و?before_id= يرجع الأقدم."""

    def setUp(self):
        self.ids = [
            ChatMessage.objects.create(case=self.case_1, sender=self.patient_1, text=str(i)).pk
            for i in range(120)
        ]

    def get(self, **params):
        return self.client_for(self.doctor_a).get(messages_url(self.case_1), params).data

    def test_first_load_returns_latest_page_oldest_first(self, _notify):
        data = self.get()
        self.assertEqual([m["id"] for m in data], self.ids[-CHAT_PAGE_SIZE:])

    def test_before_id_walks_back_through_history(self, _notify):
        latest = self.get()
        older = self.get(before_id=latest[0]["id"])
        self.assertEqual([m["id"] for m in older], self.ids[-2 * CHAT_PAGE_SIZE:-CHAT_PAGE_SIZE])
        oldest = self.get(before_id=older[0]["id"])
        self.assertEqual([m["id"] for m in oldest], self.ids[:-2 * CHAT_PAGE_SIZE])  # آخر 20 فقط

    def test_after_id_still_returns_everything_newer(self, _notify):
        data = self.get(after_id=self.ids[10])
        self.assertEqual([m["id"] for m in data], self.ids[11:])

    def test_invalid_before_id_returns_400(self, _notify):
        response = self.client_for(self.doctor_a).get(messages_url(self.case_1), {"before_id": "x"})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


@mock.patch("chat.views.notify_in_background")
class EngineerReplyRightsTests(CareWorldMixin, APITestCase):
    """كل المهندسين يقرؤون القناة التقنية؛ الرد للمهندس المسؤول عن عيادة الجهاز فقط."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.engineer_b = make_user("engineer_b", UserRole.ENGINEER)
        # case_1: جهاز في عيادة مسؤولها engineer. case_2: عيادة بلا مسؤول.
        cls.clinic_a = Clinic.objects.create(name="Clinic A", responsible_engineer=cls.engineer)
        cls.clinic_free = Clinic.objects.create(name="Clinic Free")
        Device.objects.filter(pk=cls.device_1.pk).update(clinic=cls.clinic_a)
        Device.objects.filter(pk=cls.device_2.pk).update(clinic=cls.clinic_free)

    def setUp(self):
        self.technical = ChatMessage.objects.create(
            case=self.case_1, sender=self.patient_1, text="device beeps", inquiry_type=InquiryType.TECHNICAL
        )
        self.medical = ChatMessage.objects.create(
            case=self.case_1, sender=self.patient_1, text="headache", inquiry_type=InquiryType.MEDICAL
        )

    def send(self, user, case, inquiry_type="technical"):
        return self.client_for(user).post(
            messages_url(case), {"text": "reply", "inquiry_type": inquiry_type}, format="json"
        )

    def test_responsible_engineer_can_reply(self, _notify):
        self.assertEqual(self.send(self.engineer, self.case_1).status_code, status.HTTP_201_CREATED)

    def test_other_engineer_reads_but_gets_403_on_send(self, _notify):
        client = self.client_for(self.engineer_b)
        response = client.get(messages_url(self.case_1), {"inquiry_type": "technical"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([m["text"] for m in response.data], ["device beeps"])

        response = self.send(self.engineer_b, self.case_1)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn("المسؤول عن عيادة الجهاز", response.data["detail"])
        self.assertIn(self.engineer.username, response.data["detail"])
        self.assertEqual(ChatMessage.objects.filter(case=self.case_1).count(), 2)

    def test_reading_without_reply_rights_does_not_mark_read(self, _notify):
        self.client_for(self.engineer_b).get(messages_url(self.case_1), {"inquiry_type": "technical"})
        self.technical.refresh_from_db()
        self.assertFalse(self.technical.is_read)
        # المسؤول يفتحها فتُعلَّم مقروءة
        self.client_for(self.engineer).get(messages_url(self.case_1), {"inquiry_type": "technical"})
        self.technical.refresh_from_db()
        self.assertTrue(self.technical.is_read)

    def test_medical_channel_access_unchanged_for_non_responsible_engineer(self, _notify):
        response = self.client_for(self.engineer_b).get(messages_url(self.case_1), {"inquiry_type": "medical"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])
        response = self.client_for(self.engineer).get(messages_url(self.case_1), {"inquiry_type": "medical"})
        self.assertEqual([m["text"] for m in response.data], ["headache"])

    def test_clinic_without_engineer_lets_any_engineer_reply(self, _notify):
        for user in (self.engineer, self.engineer_b):
            self.assertEqual(self.send(user, self.case_2).status_code, status.HTTP_201_CREATED)

    def test_device_without_clinic_lets_any_engineer_reply(self, _notify):
        Device.objects.filter(pk=self.device_1.pk).update(clinic=None)
        self.assertEqual(self.send(self.engineer_b, self.case_1).status_code, status.HTTP_201_CREATED)

    def test_changing_clinic_engineer_moves_reply_rights(self, _notify):
        Clinic.objects.filter(pk=self.clinic_a.pk).update(responsible_engineer=self.engineer_b)
        self.assertEqual(self.send(self.engineer, self.case_1).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.send(self.engineer_b, self.case_1).status_code, status.HTTP_201_CREATED)

    def test_doctor_access_unchanged(self, _notify):
        self.assertEqual(self.send(self.doctor_a, self.case_1, "medical").status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.send(self.doctor_a, self.case_1).status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.send(self.doctor_b, self.case_1, "medical").status_code, status.HTTP_403_FORBIDDEN)

    def test_reply_rights_endpoint(self, _notify):
        url = f"/api/chat/cases/{self.case_1.pk}/reply-rights/"
        data = self.client_for(self.engineer_b).get(url).data
        self.assertEqual(
            data,
            {"case": self.case_1.pk, "can_reply": False, "responsible_engineer": self.engineer.pk,
             "responsible_engineer_name": self.engineer.username},
        )
        self.assertTrue(self.client_for(self.engineer).get(url).data["can_reply"])
        self.assertEqual(self.client_for(self.doctor_a).get(url).status_code, status.HTTP_403_FORBIDDEN)


class TechnicalPushRecipientsTests(CareWorldMixin, APITestCase):
    """إشعار رسالة المريض التقنية: للمهندس المسؤول فقط، وبلا مسؤول لكل المهندسين."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.engineer_b = make_user("engineer_b", UserRole.ENGINEER)
        cls.clinic_a = Clinic.objects.create(name="Clinic A", responsible_engineer=cls.engineer)
        Device.objects.filter(pk=cls.device_1.pk).update(clinic=cls.clinic_a)

    def recipients_for(self, case):
        message = ChatMessage.objects.create(
            case=case, sender=case.patient, text="x", inquiry_type=InquiryType.TECHNICAL
        )
        with mock.patch("notifications.services.send_push_to_users") as send_push:
            with mock.patch("chat.notifications.connection"):
                notify_message_by_id(message.pk)
        send_push.assert_called_once()
        return set(send_push.call_args.args[0])

    def test_patient_message_goes_to_responsible_engineer_only(self):
        self.assertEqual(self.recipients_for(self.case_1), {self.engineer})

    def test_without_responsible_engineer_all_engineers_are_notified(self):
        self.assertEqual(self.recipients_for(self.case_2), {self.engineer, self.engineer_b})

    def test_changing_clinic_engineer_moves_push(self):
        Clinic.objects.filter(pk=self.clinic_a.pk).update(responsible_engineer=self.engineer_b)
        self.assertEqual(self.recipients_for(self.case_1), {self.engineer_b})


@mock.patch("chat.views.notify_in_background")
class EngineerInboxTests(CareWorldMixin, APITestCase):
    URL = "/api/chat/engineer/inbox/"

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.engineer_b = make_user("engineer_b", UserRole.ENGINEER, first_name="Bassam", last_name="Ali")
        cls.clinic_b = Clinic.objects.create(name="Clinic B", responsible_engineer=cls.engineer_b)
        Device.objects.filter(pk=cls.device_1.pk).update(clinic=cls.clinic_b)  # case_1 → engineer_b
        # case_2: جهاز بلا عيادة. orphan_case: بلا جهاز.

    def add(self, case, sender=None, text="m", inquiry_type=InquiryType.TECHNICAL, is_read=False):
        return ChatMessage.objects.create(
            case=case, sender=sender or case.patient, text=text, inquiry_type=inquiry_type, is_read=is_read
        )

    def rows(self, user, **params):
        response = self.client_for(user).get(self.URL, params)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data["results"]

    def test_one_row_per_conversation_sorted_by_last_message(self, _notify):
        self.add(self.case_1, text="first")
        self.add(self.case_2, text="second")
        self.add(self.case_1, sender=self.engineer_b, text="latest on case 1")
        self.add(self.orphan_case, text="medical only", inquiry_type=InquiryType.MEDICAL)

        rows = self.rows(self.engineer)
        self.assertEqual([r["case"] for r in rows], [self.case_1.pk, self.case_2.pk])
        row = rows[0]
        self.assertEqual(row["patient_name"], "patient_1")
        self.assertEqual(row["device_serial"], "SN-1")
        self.assertEqual(row["clinic_name"], "Clinic B")
        self.assertEqual(row["responsible_engineer"], self.engineer_b.pk)
        self.assertEqual(row["responsible_engineer_name"], "Bassam Ali")
        self.assertEqual(row["case_status"], "in_treatment")
        self.assertEqual(row["last_message_text"], "latest on case 1")
        self.assertIsNotNone(row["last_message_at"])
        self.assertFalse(row["can_reply"])
        self.assertTrue(rows[1]["can_reply"])  # جهاز بلا عيادة
        self.assertIsNone(rows[1]["clinic_name"])
        self.assertIsNone(rows[1]["responsible_engineer_name"])

    def test_can_reply_for_responsible_engineer(self, _notify):
        self.add(self.case_1)
        self.assertTrue(self.rows(self.engineer_b)[0]["can_reply"])

    def test_mine_filter(self, _notify):
        self.add(self.case_1)
        self.add(self.case_2)
        self.add(self.orphan_case)
        mine = {r["case"] for r in self.rows(self.engineer, mine="true")}
        self.assertEqual(mine, {self.case_2.pk, self.orphan_case.pk})
        mine_b = {r["case"] for r in self.rows(self.engineer_b, mine="true")}
        self.assertEqual(mine_b, {self.case_1.pk, self.case_2.pk, self.orphan_case.pk})
        self.assertEqual(len(self.rows(self.engineer)), 3)

    def test_changing_clinic_engineer_moves_rows_between_mine(self, _notify):
        self.add(self.case_1)
        Clinic.objects.filter(pk=self.clinic_b.pk).update(responsible_engineer=self.engineer)
        self.assertEqual([r["case"] for r in self.rows(self.engineer, mine="true")], [self.case_1.pk])
        self.assertEqual(self.rows(self.engineer_b, mine="true"), [])

    def test_unread_counts_only_unread_patient_technical_messages(self, _notify):
        self.add(self.case_1)
        self.add(self.case_1)
        self.add(self.case_1, is_read=True)
        self.add(self.case_1, sender=self.engineer_b)
        self.add(self.case_1, inquiry_type=InquiryType.MEDICAL)
        self.add(self.case_2, is_read=True)
        counts = {r["case"]: r["unread_count"] for r in self.rows(self.engineer)}
        self.assertEqual(counts, {self.case_1.pk: 2, self.case_2.pk: 0})

        # يتطابق مع عدّاد التبويب (unread-count) لدى المسؤول
        by_case = self.client_for(self.engineer_b).get("/api/chat/unread-count/").data["by_case"]
        self.assertEqual(by_case, {self.case_1.pk: 2})

    def test_paginated(self, _notify):
        self.add(self.case_1)
        self.add(self.case_2)
        data = self.client_for(self.engineer).get(self.URL, {"page_size": 1}).data
        self.assertEqual(data["count"], 2)
        self.assertEqual(len(data["results"]), 1)
        self.assertIsNotNone(data["next"])

    def test_query_count_is_constant(self, _notify):
        client = self.client_for(self.engineer)
        self.add(self.case_1)
        with self.assertNumQueries(2):  # COUNT + الصفحة
            client.get(self.URL)
        for case in (self.case_1, self.case_2, self.orphan_case):
            for _ in range(3):
                self.add(case)
        with self.assertNumQueries(2):
            response = client.get(self.URL)
        self.assertEqual(len(response.data["results"]), 3)
        with self.assertNumQueries(2):
            client.get(self.URL, {"mine": "true"})

    def test_non_engineers_are_forbidden(self, _notify):
        for user in (self.doctor_a, self.patient_1, self.no_role):
            self.assertEqual(self.client_for(user).get(self.URL).status_code, status.HTTP_403_FORBIDDEN)

from rest_framework import status
from rest_framework.test import APITestCase

from cases.models import Case, CaseStatus
from config.testing import CareWorldMixin, results

from .models import Clinic, Device, DeviceType

DEVICES = "/api/devices/"


class DeviceAvailabilityTests(CareWorldMixin, APITestCase):
    """الجهاز متاح ما لم يكن مرتبطاً بحالة غير مغلقة (الحالات المغلقة لا تُحتسب)."""

    def available_serials(self, **params):
        response = self.client_for(self.doctor_a).get(DEVICES, {"available": "true", **params})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return {d["serial_number"] for d in results(response)}

    def test_available_filter_excludes_devices_in_active_cases(self):
        self.assertEqual(self.available_serials(), {"SN-FREE"})

    def test_available_filter_returns_freed_device(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        self.assertEqual(self.available_serials(), {"SN-1", "SN-FREE"})

    def test_exclude_case_keeps_current_device_in_list(self):
        self.assertEqual(self.available_serials(exclude_case=self.case_1.pk), {"SN-1", "SN-FREE"})

    def test_is_available_flag_matches_case_status(self):
        Case.objects.filter(pk=self.case_1.pk).update(status=CaseStatus.CLOSED)
        response = self.client_for(self.engineer).get(DEVICES)
        flags = {d["serial_number"]: d["is_available"] for d in results(response)}
        self.assertEqual(flags, {"SN-1": True, "SN-2": False, "SN-FREE": True})



class DeviceListQueryCountTests(CareWorldMixin, APITestCase):
    """P2: is_available محسوبة داخل استعلام القائمة، لا استعلام لكل جهاز."""

    # count (الترقيم) + الأجهزة مع العيادة والنوع و EXISTS
    EXPECTED_QUERIES = 2

    def test_device_list_query_count_is_constant(self):
        client = self.client_for(self.doctor_a)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            client.get(DEVICES)
        clinic = Clinic.objects.create(name="Clinic")
        device_type = DeviceType.objects.create(name="Type A")
        for i in range(5):
            Device.objects.create(serial_number=f"SN-X{i}", clinic=clinic, device_type=device_type)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            response = client.get(DEVICES, {"available": "true"})
        self.assertEqual(response.data["count"], 6)


class ManagerOnlyDeviceAdminTests(CareWorldMixin, APITestCase):
    """المهندس العادي: يقرأ العيادات وأنواع الأجهزة، ويضيف ويعدّل الأجهزة.
    المدير وحده: حذف الأجهزة، وإنشاء/تعديل/حذف العيادات وأنواع الأجهزة."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.clinic = Clinic.objects.create(name="Clinic")
        cls.device_type = DeviceType.objects.create(name="Type A")

    def test_regular_engineer_device_rights(self):
        client = self.client_for(self.engineer)
        response = client.post(DEVICES, {"serial_number": "SN-NEW"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        response = client.patch(f"{DEVICES}{self.device_free.pk}/", {"status": "maintenance"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        response = client.delete(f"{DEVICES}{self.device_free.pk}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(Device.objects.filter(pk=self.device_free.pk).exists())

    def test_manager_deletes_device(self):
        response = self.client_for(self.manager).delete(f"{DEVICES}{self.device_free.pk}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

    def _write_all(self, client, url, item_url, create, edit):
        return (
            client.post(url, create, format="json").status_code,
            client.patch(item_url, edit, format="json").status_code,
            client.delete(item_url).status_code,
        )

    def test_regular_engineer_reads_but_cannot_change_clinics_or_types(self):
        client = self.client_for(self.engineer)
        for url, item, create in (
            ("/api/clinics/", self.clinic, {"name": "New clinic"}),
            ("/api/device-types/", self.device_type, {"name": "Type B"}),
        ):
            self.assertEqual(client.get(url).status_code, status.HTTP_200_OK)
            codes = self._write_all(client, url, f"{url}{item.pk}/", create, {"name": "Renamed"})
            self.assertEqual(codes, (403, 403, 403))
        response = client.patch(
            f"/api/clinics/{self.clinic.pk}/", {"responsible_engineer": self.engineer.pk}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.clinic.refresh_from_db()
        self.assertEqual((self.clinic.name, self.clinic.responsible_engineer), ("Clinic", None))
        self.assertFalse(Clinic.objects.filter(name="New clinic").exists())
        self.assertTrue(DeviceType.objects.filter(pk=self.device_type.pk, name="Type A").exists())

    def test_manager_manages_clinics_and_types(self):
        client = self.client_for(self.manager)
        response = client.patch(
            f"/api/clinics/{self.clinic.pk}/", {"responsible_engineer": self.engineer.pk}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        for url, item, create in (
            ("/api/clinics/", self.clinic, {"name": "New clinic"}),
            ("/api/device-types/", self.device_type, {"name": "Type B"}),
        ):
            codes = self._write_all(client, url, f"{url}{item.pk}/", create, {"name": "Renamed"})
            self.assertEqual(codes, (201, 200, 204))

    def test_doctor_has_no_access(self):
        client = self.client_for(self.doctor_a)
        for url in ("/api/clinics/", "/api/device-types/"):
            self.assertEqual(client.get(url).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(client.delete(f"{DEVICES}{self.device_free.pk}/").status_code, 403)


class ClinicResponsibleEngineerNameTests(CareWorldMixin, APITestCase):
    """responsible_engineer_name للعرض فقط، بلا استعلام إضافي لكل عيادة."""

    # count (الترقيم) + العيادات مع JOIN للمهندس المسؤول
    EXPECTED_QUERIES = 2

    def names(self):
        response = self.client_for(self.engineer).get("/api/clinics/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return {c["name"]: c["responsible_engineer_name"] for c in results(response)}

    def test_full_name_username_fallback_and_unassigned(self):
        self.engineer.first_name, self.engineer.last_name = "Omar", "Saleh"
        self.engineer.save()
        Clinic.objects.create(name="Named", responsible_engineer=self.engineer)
        Clinic.objects.create(name="No name", responsible_engineer=self.manager)
        Clinic.objects.create(name="Unassigned")
        self.assertEqual(
            self.names(),
            {"Named": "Omar Saleh", "No name": self.manager.username, "Unassigned": None},
        )

    def test_read_only(self):
        clinic = Clinic.objects.create(name="C", responsible_engineer=self.engineer)
        response = self.client_for(self.manager).patch(
            f"/api/clinics/{clinic.pk}/", {"responsible_engineer_name": "X"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["responsible_engineer_name"], self.engineer.username)

    def test_query_count_is_constant(self):
        Clinic.objects.create(name="C0", responsible_engineer=self.engineer)
        client = self.client_for(self.engineer)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            client.get("/api/clinics/")
        for i in range(5):
            Clinic.objects.create(name=f"C{i + 1}", responsible_engineer=self.manager)
        with self.assertNumQueries(self.EXPECTED_QUERIES):
            response = client.get("/api/clinics/")
        self.assertEqual(response.data["count"], 6)

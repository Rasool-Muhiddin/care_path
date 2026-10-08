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

"""
نطاق البيانات حسب الدور — المكان الوحيد الذي يحدد ماذا يرى كل دور من
الحالات وكل ما يتفرع منها (جلسات، تقييمات، ملاحظات،
نوبات مسجّلة وتأكيداتها).

القاعدة: الرفض كافتراض (default-deny). الأدوار المعروفة فقط تحصل على
بيانات؛ أي دور آخر (فارغ كحساب superuser، أو دور جديد يُضاف لاحقاً)
لا يرى شيئاً إلى أن يُضاف له فرع صريح هنا.
"""

from accounts.models import UserRole

from .models import Case


def _lookup(case_path, field):
    return f"{case_path}__{field}" if case_path else field


def scope_by_case(queryset, user, case_path="case"):
    """
    يفلتر queryset لأي موديل مرتبط بـ Case حسب دور المستخدم.
    case_path: مسار الوصول إلى Case من الموديل (مثلاً "session__case")،
    أو "" إذا كان الـ queryset نفسه من Case.
    """
    role = getattr(user, "role", None)
    if role == UserRole.ENGINEER:
        return queryset
    if role == UserRole.DOCTOR:
        return queryset.filter(**{_lookup(case_path, "doctor"): user})
    if role == UserRole.PATIENT:
        return queryset.filter(**{_lookup(case_path, "patient"): user})
    return queryset.none()


def scoped_cases(user):
    return scope_by_case(Case.objects.all(), user, case_path="")

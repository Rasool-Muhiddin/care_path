from django.contrib.auth import get_user_model
from rest_framework import serializers

from .models import UserRole

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    """يُستخدم لإرجاع بيانات المستخدم الحالي (مثلاً في /api/me/)."""

    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "first_name",
            "last_name",
            "email",
            "role",
            "phone_number",
            "specialty",
            "date_joined",
        ]
        # date_joined تُستخدم بواجهة المريض لحساب "عدد الأيام منذ التسجيل"
        read_only_fields = ["id", "role", "date_joined"]  # لا يمكن للمستخدم تغيير دوره بنفسه


class RegisterSerializer(serializers.ModelSerializer):
    """
    تسجيل مستخدم جديد. مهم: تسجيل دور "engineer" يجب أن يقتصر على
    استدعاء داخلي من فريقكم (مثلاً عبر Django admin أو endpoint محمي)،
    وليس متاحاً للعامة — بخلاف تسجيل الطبيب والمريض.
    """

    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "password",
            "first_name",
            "last_name",
            "email",
            "role",
            "phone_number",
            "specialty",
        ]
        read_only_fields = ["id"]

    def validate_role(self, value):
        if value == UserRole.ENGINEER:
            raise serializers.ValidationError(
                "لا يمكن تسجيل حساب مهندس عبر التسجيل العام."
            )
        return value

    def create(self, validated_data):
        password = validated_data.pop("password")
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user


class PatientListSerializer(serializers.ModelSerializer):
    """
    عرض مختصر للمريض — يُستخدم في قائمة اختيار المريض عند إنشاء حالة
    جديدة (GET /api/patients/). لا نعرض حقول حساسة كالبريد الإلكتروني
    هنا، فقط ما يحتاجه الطبيب/المهندس للتعرف على المريض واختياره.
    """

    full_name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "username", "full_name", "phone_number"]

    def get_full_name(self, obj):
        # لو first_name/last_name فاضيين (حساب أُنشئ بدون اسم كامل مثلاً
        # عبر admin)، نرجع اليوزرنيم كبديل بدل ما نرجع نص فاضي
        return obj.get_full_name() or obj.username


class EngineerListSerializer(serializers.ModelSerializer):
    """
    عرض مختصر لمهندسي الفريق — يُستخدم لاختيار "المهندس المسؤول" عند
    إنشاء/تعديل عيادة (GET /api/engineers/).
    """

    full_name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "username", "full_name", "phone_number"]

    def get_full_name(self, obj):
        return obj.get_full_name() or obj.username
import 'package:flutter/material.dart';

/// مفتاح عام يسمح لأي كود خارج شجرة الودجت (مثل معالج إشعار FCM أثناء
/// عمل التطبيق بالمقدمة) بعرض SnackBar دون الحاجة لـ BuildContext محلي.
/// يُمرَّر إلى MaterialApp.router في main.dart.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

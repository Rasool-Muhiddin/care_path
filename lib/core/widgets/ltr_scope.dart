import 'package:flutter/material.dart';

/// يجبر اتجاه LTR على الشاشات الإنجليزية (طبيب/مهندس) بغض النظر عن
/// locale التطبيق العام (المضبوط على 'ar' لأجل واجهة المريض العربية).
/// بدون هذا، أي نص إنجليزي يظهر بترتيب معكوس لأن Directionality تُشتق
/// من locale التطبيق ككل، مو من لغة النص المعروض فعلياً.
class LtrScope extends StatelessWidget {
  const LtrScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.ltr, child: child);
  }
}
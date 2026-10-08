import 'package:flutter/material.dart';

/// ألوان التمييز المشتركة بين الشاشات (طبيب، مريض، حالة، جهاز، عيادة...).
/// كانت منسوخة كـ `_Accent` في كل شاشة بنفس القيم.
class AppAccent {
  AppAccent._();

  static const Color doctor = Color(0xFF5AC8FA);
  static const Color patient = Color(0xFF34D399);
  static const Color caseC = Color(0xFFFBBF24);
  static const Color device = Color(0xFFA78BFA);
  static const Color unlinked = Color(0xFFF87171);
  static const Color clinic = Color(0xFF22D3EE);
}

/// أنماط النصوص المشتركة (أبيض على الخلفية الزجاجية الداكنة).
/// الشاشات ذات المقاسات المختلفة تحتفظ بـ `_Txt` محلي لما يختلف فقط.
class AppText {
  AppText._();

  static const headline = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
  static const sectionTitle = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700);
  static const sectionSubtitle = TextStyle(color: Colors.white60, fontSize: 12.5);
  static const tileTitle = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
  static const tileSubtitle = TextStyle(color: Colors.white60, fontSize: 12);
  static const body = TextStyle(color: Colors.white60, fontSize: 13);
  static const error = TextStyle(color: Color(0xFFF87171));
}

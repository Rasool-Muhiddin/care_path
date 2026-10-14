import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/attacks/attack_models.dart';
import '../../../core/attacks/attack_repository.dart';
import '../../../core/time/baghdad_time.dart';
import '../../../core/widgets/glass_container.dart';
import '../../doctor/models/case_model.dart' show CaseModel, CaseStatus;
import 'log_attack_dialog.dart';

/// كل كم يوم نسأل (= الأيام التي يغطيها التأكيد = حد التسجيل المتأخر)
const int _askEveryDays = AttackLogConfirmationModel.coveredDays;

/// هل نعرض السؤال الأسبوعي الخفيف الآن؟ لا نسأل لو: الحالة مغلقة، أو
/// عمرها أقل من أسبوع، أو أكّد المريض خلال آخر 7 أيام، أو أغلق السؤال
/// (بدون إجابة) خلال آخر 7 أيام على هذا الجهاز.
bool shouldAskAttackConfirmation({
  required CaseModel myCase,
  required List<AttackLogConfirmationModel> confirmations,
  DateTime? dismissedDay,
  DateTime? today,
}) {
  final day = today ?? baghdadToday();
  if (myCase.status == CaseStatus.closed) return false;
  if (day.difference(baghdadDayOf(myCase.createdAt)).inDays < _askEveryDays) return false;
  for (final c in confirmations) {
    if (day.difference(baghdadDayOf(c.confirmedAt)).inDays < _askEveryDays) return false;
  }
  if (dismissedDay != null && day.difference(dismissedDay).inDays < _askEveryDays) return false;
  return true;
}

/// تذكّر إغلاق السؤال بدون إجابة (على هذا الجهاز فقط) حتى لا يتكرر كل
/// مرة يُفتح فيها التطبيق — يبقى الأسبوع "غير مؤكَّد" بالإحصائيات.
class AttackPromptDismissals {
  AttackPromptDismissals._();
  static const _storage = FlutterSecureStorage();
  static String _key(int caseId) => 'axon_attack_prompt_dismissed_$caseId';

  static Future<DateTime?> read(int caseId) async {
    try {
      final value = await _storage.read(key: _key(caseId));
      return value == null ? null : DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  static Future<void> markToday(int caseId) async {
    try {
      await _storage.write(key: _key(caseId), value: baghdadToday().toIso8601String());
    } catch (_) {
      // أسوأ حالة: يظهر السؤال مرة أخرى عند الفتح التالي
    }
  }
}

enum _Answer { none, yes }

/// السؤال الأسبوعي: "لا" يسجّل تأكيداً (had_unlogged=false). "نعم" يفتح
/// تسجيل النوبات، وإن سجّل المريض نوبة واحدة على الأقل يُحفظ تأكيد
/// (had_unlogged=true). الإغلاق بدون إجابة يُذكَّر محلياً فقط.
Future<void> showAttackConfirmationPrompt(BuildContext context, WidgetRef ref, CaseModel myCase) async {
  final answer = await showDialog<_Answer>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: 'سؤال أسبوعي',
      content: const Text(
        'هل كانت لديك نوبات لم تسجّلها هذا الأسبوع؟',
        style: TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(_Answer.none),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('لا'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
          ),
          onPressed: () => Navigator.of(dialogContext).pop(_Answer.yes),
          child: const Text('نعم، أسجّلها الآن'),
        ),
      ],
    ),
  );

  final repository = ref.read(attackRepositoryProvider);
  try {
    switch (answer) {
      case null:
        await AttackPromptDismissals.markToday(myCase.id);
      case _Answer.none:
        await repository.confirmLog(caseId: myCase.id, hadUnlogged: false);
      case _Answer.yes:
        if (!context.mounted) return;
        final logged = await showLogAttackDialog(context, myCase);
        if (logged > 0) {
          await repository.confirmLog(caseId: myCase.id, hadUnlogged: true);
        } else {
          await AttackPromptDismissals.markToday(myCase.id);
        }
    }
  } catch (_) {
    // فشل الشبكة: نتذكّر الإغلاق محلياً ونسأل مجدداً بعد أسبوع
    await AttackPromptDismissals.markToday(myCase.id);
  }
  ref.invalidate(caseAttackConfirmationsProvider(myCase.id));
}

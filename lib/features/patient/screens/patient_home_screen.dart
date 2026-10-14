import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/attacks/attack_models.dart';
import '../../../core/attacks/attack_repository.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/attack_list.dart';
import '../../../core/time/baghdad_time.dart';
import '../../../core/widgets/session_calendar.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../doctor/models/case_model.dart' show CaseModel, CaseStatus;
import '../models/session_model.dart';
import '../patient_providers.dart';
import 'attack_confirmation_prompt.dart';
import 'log_attack_dialog.dart';

/// الشاشة الرئيسية للمريض: ملخص حالته (خطة العلاج ونوع الجهاز)، زر إنهاء
/// الجلسة اليومية، زر فتح المحادثة مع الطبيب، وقائمة بجلساته السابقة.
class PatientHomeScreen extends ConsumerStatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  bool _confirmationChecked = false;
  bool _isEndingSession = false;

  /// "إنهاء الجلسة": تأكيد بسيط (نعم/لا) ثم حفظ الجلسة مباشرة — بدون
  /// تقييم أو ملاحظة. التأكيد يمنع ضغطة بالخطأ لأن الجلسة مرة واحدة يومياً.
  Future<void> _endSession(int caseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: 'إنهاء الجلسة',
        content: const Text('هل تريد إنهاء الجلسة؟', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
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
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('نعم'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isEndingSession = true);
    try {
      await ref.read(patientRepositoryProvider).createSession(NewSessionPayload(caseId: caseId));
      ref.invalidate(mySessionsProvider);
      ref.invalidate(myCaseProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الجلسة بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isEndingSession = false);
    }
  }

  /// عدد النوبات هذا الشهر (بتوقيت بغداد)
  int _attacksThisMonth(List<AttackEventModel> attacks) {
    final today = baghdadToday();
    return attacks.where((a) {
      final day = baghdadDayOf(a.occurredAt);
      return day.year == today.year && day.month == today.month;
    }).length;
  }

  /// السؤال الأسبوعي الخفيف (غير إلزامي) — يُفحص مرة واحدة لكل فتح للشاشة.
  Future<void> _maybeAskAttackConfirmation(CaseModel myCase) async {
    if (_confirmationChecked) return;
    _confirmationChecked = true;
    try {
      final confirmations = await ref.read(caseAttackConfirmationsProvider(myCase.id).future);
      final dismissedDay = await AttackPromptDismissals.read(myCase.id);
      if (!mounted) return;
      final ask = shouldAskAttackConfirmation(
        myCase: myCase,
        confirmations: confirmations,
        dismissedDay: dismissedDay,
      );
      if (ask) await showAttackConfirmationPrompt(context, ref, myCase);
    } catch (_) {
      // خطأ شبكة: لا نزعج المريض الآن، نسأل عند الفتح التالي
    }
  }

  Future<void> _logAttack(CaseModel myCase) async {
    final logged = await showLogAttackDialog(context, myCase);
    if (logged > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(logged == 1 ? 'تم تسجيل النوبة' : 'تم تسجيل $logged نوبات')),
      );
    }
  }

  /// حذف نوبة سُجّلت بالخطأ (خلال 24 ساعة من تسجيلها فقط).
  Future<void> _deleteAttack(AttackEventModel attack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: 'حذف النوبة',
        content: const Text('هل تريد حذف هذه النوبة؟', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('لا'),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppAccent.unlinked),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(attackRepositoryProvider).deleteAttack(attack.id);
      ref.invalidate(caseAttacksProvider(attack.caseId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final authState = ref.watch(authStateProvider);
    final username =
        authState is AuthAuthenticated ? authState.user.username : '';
    final sessionsAsync = ref.watch(mySessionsProvider);
    final caseAsync = ref.watch(myCaseProvider);
    final myCaseId = caseAsync.value?.id;
    final unreadByCase = ref.watch(unreadByCaseProvider).value ?? {};
    final unreadForMyCase = myCaseId != null ? (unreadByCase[myCaseId] ?? 0) : 0;
    final attacksAsync =
        myCaseId != null ? ref.watch(caseAttacksProvider(myCaseId)) : const AsyncValue<List<AttackEventModel>>.data([]);

    final loadedCase = caseAsync.value;
    if (loadedCase != null && !_confirmationChecked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAskAttackConfirmation(loadedCase);
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text('مرحباً $username', style: const TextStyle(color: Colors.white)),
        actions: [
          if (myCaseId != null)
            IconButton(
              icon: Badge(
                isLabelVisible: unreadForMyCase > 0,
                label: Text('$unreadForMyCase'),
                child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              ),
              tooltip: 'المحادثة مع الطبيب',
              onPressed: () => context.push('/patient/chat/$myCaseId'),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => ref.read(authStateProvider.notifier).logout(),
          ),
        ],
      ),
      body: AppGradientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppGlassColors.baseDark,
            backgroundColor: Colors.white,
            onRefresh: () async {
              ref.invalidate(mySessionsProvider);
              ref.invalidate(myCaseProvider);
              if (myCaseId != null) ref.invalidate(caseAttacksProvider(myCaseId));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                caseAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
                  error: (error, _) => _ErrorView(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(myCaseProvider),
                  ),
                  data: (myCase) {
                    if (myCase == null) return const SizedBox.shrink();
                    return _CaseSummaryCard(myCase: myCase);
                  },
                ),
                const SizedBox(height: 16),
                caseAsync.when(
                  loading: () => const SizedBox.shrink(),
                  // خطأ تحميل الحالة معروض مرة واحدة بأعلى الشاشة مع زر إعادة المحاولة
                  error: (_, __) => const SizedBox.shrink(),
                  data: (myCase) {
                    if (myCase == null) return const SizedBox.shrink();
                    return sessionsAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
                      // خطأ الجلسات معروض في قسم "جلساتي" بالأسفل مع زر إعادة المحاولة
                      error: (_, __) => const SizedBox.shrink(),
                      data: (sessions) {
                        final hasCompletedToday = sessions.any(
                          (session) => isBaghdadToday(session.sessionDate),
                        );
                        return SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: (hasCompletedToday || _isEndingSession)
                                ? null
                                : () => _endSession(myCase.id),
                            icon: _isEndingSession
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(
                                    hasCompletedToday
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                  ),
                            label: Text(
                              hasCompletedToday
                                  ? 'تم إنهاء الجلسة اليومية'
                                  : 'إنهاء الجلسة اليومية',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.18),
                              disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                if (loadedCase != null && loadedCase.status != CaseStatus.closed) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => _logAttack(loadedCase),
                      icon: const Icon(Icons.bolt_outlined),
                      label: const Text('تسجيل نوبة'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppAccent.unlinked.withValues(alpha: 0.22),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppAccent.unlinked.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                caseAsync.when(
                  loading: () => const SizedBox.shrink(),
                  // خطأ تحميل الحالة معروض مرة واحدة بأعلى الشاشة مع زر إعادة المحاولة
                  error: (_, __) => const SizedBox.shrink(),
                  data: (myCase) {
                    if (myCase == null || myCase.totalSessionsPlanned == null) {
                      // لو ما حدد الطبيب عدد الجلسات الإجمالي، نعرض المكتملة فقط
                      if (myCase == null) return const SizedBox.shrink();
                      return _SessionCounters(completed: myCase.completedSessionsCount);
                    }
                    return _SessionCounters(
                      completed: myCase.completedSessionsCount,
                      remaining: myCase.remainingSessionsCount,
                    );
                  },
                ),
                if (loadedCase != null) ...[
                  const SizedBox(height: 24),
                  SectionHeader(
                    icon: Icons.bolt_outlined,
                    color: AppAccent.unlinked,
                    title: 'نوباتي',
                    subtitleText: 'هذا الشهر: ${_attacksThisMonth(attacksAsync.value ?? const [])}',
                  ),
                  const SizedBox(height: 10),
                  attacksAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                    error: (error, _) => _ErrorView(
                      message: error.toString(),
                      onRetry: () => ref.invalidate(caseAttacksProvider(loadedCase.id)),
                    ),
                    data: (attacks) {
                      if (attacks.isEmpty) {
                        return const GlassContainer(
                          padding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                          child: Text(
                            'لا توجد نوبات مسجّلة. اضغط "تسجيل نوبة" عند حدوث أي نوبة.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                      final sorted = [...attacks]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
                      return AttackList(
                        attacks: sorted,
                        strings: AttackListStrings.ar,
                        initialLimit: 5,
                        canDelete: (a) =>
                            DateTime.now().difference(a.createdAt) < const Duration(hours: 24),
                        onDelete: _deleteAttack,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 24),
                SectionHeader(
                  icon: Icons.event_note_outlined,
                  color: AppAccent.patient,
                  title: 'جلساتي',
                  subtitleSpans: [
                    TextSpan(
                      text: '${sessionsAsync.value?.length ?? 0}',
                      style: TextStyle(
                        color: AppAccent.patient,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        shadows: [
                          Shadow(color: AppAccent.patient.withValues(alpha: 0.55), blurRadius: 14),
                        ],
                      ),
                    ),
                    const TextSpan(text: ' جلسة مسجّلة'),
                  ],
                ),
                const SizedBox(height: 10),
                sessionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                  error: (error, _) => _ErrorView(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(mySessionsProvider),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return const _EmptyView();
                    }
                    return SessionCalendar(
                      sessions: sessions,
                      strings: SessionCalendarStrings.ar,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaseSummaryCard extends StatelessWidget {
  const _CaseSummaryCard({required this.myCase});
  final CaseModel myCase;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (myCase.deviceTypeName != null) ...[
            Row(
              children: [
                IconBadge(icon: Icons.medical_services_outlined, color: AppAccent.device, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('الجهاز: ${myCase.deviceTypeName}', style: AppText.tileTitle),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (myCase.treatmentPlan.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.assignment_outlined, size: 16, color: AppAccent.patient),
                const SizedBox(width: 6),
                const Text('خطة العلاج', style: AppText.tileTitle),
              ],
            ),
            const SizedBox(height: 6),
            Text(myCase.treatmentPlan, style: const TextStyle(color: Colors.white)),
          ],
        ],
      ),
    );
  }
}

/// عدّادات الجلسات المكتملة/المتبقية، بأرقام بارزة ذات توهّج.
class _SessionCounters extends StatelessWidget {
  const _SessionCounters({required this.completed, this.remaining});
  final int completed;
  final int? remaining;

  @override
  Widget build(BuildContext context) {
    Widget counter(String label, int value, Color color) {
      return Expanded(
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: color.withValues(alpha: 0.55), blurRadius: 14)],
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: AppText.tileSubtitle),
            ],
          ),
        ),
      );
    }

    if (remaining == null) {
      // counter() يُرجع Expanded، ولا يجوز وضعه مباشرة داخل ListView — لازم
      // يكون داخل Row/Column، وإلا ينهار البناء ويظهر مربع رمادي بالـ release.
      return Row(
        children: [counter('الجلسات المكتملة', completed, AppAccent.patient)],
      );
    }
    return Row(
      children: [
        counter('الجلسات المكتملة', completed, AppAccent.patient),
        const SizedBox(width: 10),
        counter('المتبقية', remaining!, AppAccent.caseC),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon: Icons.event_busy_outlined, color: AppAccent.patient, size: 44),
          const SizedBox(height: 12),
          const Text('لا توجد جلسات بعد', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      child: Column(
        children: [
          IconBadge(icon: Icons.error_outline, color: AppAccent.unlinked, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: AppText.error),
          const SizedBox(height: 14),
          _RetryButton(onPressed: onRetry),
        ],
      ),
    );
  }
}

/// زر إعادة المحاولة بالنمط الزجاجي الموحّد لكل الحالات الفارغة/الأخطاء.
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
      label: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}
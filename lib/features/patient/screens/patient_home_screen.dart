import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/session_calendar.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../doctor/models/case_model.dart' show CaseModel;
import '../../doctor/models/weekly_episode_log_model.dart';
import '../models/session_model.dart';
import '../patient_providers.dart';

/// الشاشة الرئيسية للمريض: ملخص حالته (خطة العلاج ونوع الجهاز)، زر إنهاء
/// الجلسة اليومية، زر فتح المحادثة مع الطبيب، وقائمة بجلساته السابقة.
class PatientHomeScreen extends ConsumerStatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  bool _isWeeklyDialogShowing = false;
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

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// يعرض رسالة التقرير الأسبوعي الإلزامية (كم نوبة هذا الأسبوع) لو فيه
  /// أسبوع مستحق لم يُجب عنه المريض بعد. لا يمكن تجاهلها أو إغلاقها إلا
  /// بالإجابة (لا زر إغلاق، لا سحب للخارج، لا زر رجوع). لو كان المريض
  /// غايباً أكثر من أسبوع، تُعرض الأسابيع المتراكمة واحداً تلو الآخر
  /// تلقائياً لحد ما يكمّلها كلها.
  Future<void> _maybeShowWeeklyEpisodePrompt(CaseModel myCase) async {
    if (_isWeeklyDialogShowing) return;
    // يبقى العلم true طوال فترة عرض الحوار وإعادة جلب الحالة، حتى لا تفتح
    // إعادة بناء الشاشة حواراً ثانياً بالبيانات القديمة (نفس الأسبوع).
    _isWeeklyDialogShowing = true;
    try {
      CaseModel? current = myCase;
      while (mounted &&
          current != null &&
          current.pendingWeeklyEpisodeWeek != null) {
        await _showWeeklyEpisodeDialog(
          caseId: current.id,
          weekStart: current.pendingWeeklyEpisodeWeek!,
        );
        if (!mounted) return;
        final latest = await ref.refresh(myCaseProvider.future);
        current = latest;
      }
    } catch (_) {
      // تجاهل أخطاء الشبكة هنا — الشاشة ستحاول مجدداً عند إعادة البناء التالية
    } finally {
      _isWeeklyDialogShowing = false;
    }
  }

  Future<void> _showWeeklyEpisodeDialog({required int caseId, required DateTime weekStart}) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? errorText;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              return GlassDialog(
                title: 'تقرير أسبوعي إلزامي',
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كم نوبة كانت لديك خلال الأسبوع من '
                        '${_formatDate(weekStart)} إلى ${_formatDate(weekEnd)}؟',
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: glassInputDecoration(
                          'عدد النوبات',
                        ).copyWith(errorText: errorText),
                      ),
                    ],
                  ),
                ),
                actions: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final text = controller.text.trim();
                            if (text.isEmpty || int.tryParse(text) == null) {
                              setStateDialog(() => errorText = 'أدخل رقماً صحيحاً');
                              return;
                            }
                            setStateDialog(() {
                              errorText = null;
                              isSubmitting = true;
                            });
                            try {
                              await ref.read(patientRepositoryProvider).submitWeeklyEpisodeLog(
                                    NewWeeklyEpisodeLogPayload(
                                      caseId: caseId,
                                      episodeCount: int.parse(text),
                                    ),
                                  );
                              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                            } catch (e) {
                              // ربما سُجّل هذا الأسبوع مسبقاً (حوار قديم): تحقق من الباكند
                              try {
                                final latest = await ref.refresh(myCaseProvider.future);
                                final stillPending = latest?.pendingWeeklyEpisodeWeek;
                                if (stillPending == null || stillPending != weekStart) {
                                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                                  return;
                                }
                              } catch (_) {}
                              setStateDialog(() {
                                isSubmitting = false;
                                errorText = 'حدث خطأ، حاول مرة أخرى';
                              });
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('إرسال'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
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

    // رسالة التقرير الأسبوعي الإلزامية — تُفحص بكل مرة تُبنى فيها
    // الشاشة (أي فتح للتطبيق أو رجوع لهذي الشاشة)، وتعتمد بالكامل على
    // حالة الـ backend (pendingWeeklyEpisodeWeek)، فتبقى تظهر تلقائياً
    // لحد ما المريض يجاوب حتى لو أغلق التطبيق ورجع.
    final pendingCase = caseAsync.value;
    if (pendingCase != null && pendingCase.pendingWeeklyEpisodeWeek != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowWeeklyEpisodePrompt(pendingCase);
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
                          (session) => _isToday(session.sessionDate),
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
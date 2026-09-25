import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../doctor/models/case_model.dart' show CaseModel;
import '../../doctor/models/weekly_episode_log_model.dart';
import '../models/session_model.dart';
import '../patient_providers.dart';
import 'end_session_dialog.dart';

/// الشاشة الرئيسية للمريض: ملخص حالته (خطة العلاج ونوع الجهاز)، زر إنهاء
/// الجلسة اليومية، زر فتح المحادثة مع الطبيب، وقائمة بجلساته السابقة.
class PatientHomeScreen extends ConsumerStatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  bool _isWeeklyDialogShowing = false;

  Future<void> _endSession(int caseId) async {
    final wasSaved = await showEndSessionDialog(context, caseId);
    if (wasSaved == true) {
      ref.invalidate(myCaseProvider);
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
    final week = myCase.pendingWeeklyEpisodeWeek;
    if (week == null) return;

    _isWeeklyDialogShowing = true;
    await _showWeeklyEpisodeDialog(caseId: myCase.id, weekStart: week);
    _isWeeklyDialogShowing = false;

    if (!mounted) return;
    try {
      final latest = await ref.refresh(myCaseProvider.future);
      if (latest != null && latest.pendingWeeklyEpisodeWeek != null && mounted) {
        await _maybeShowWeeklyEpisodePrompt(latest);
      }
    } catch (_) {
      // تجاهل أي خطأ بإعادة الجلب هنا — لو لسا فيه أسبوع مستحق، الشاشة
      // ستحاول عرض الرسالة مرة ثانية بمجرد نجاح أي إعادة بناء لاحقة
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
                  error: (_, __) => const SizedBox.shrink(),
                  data: (myCase) {
                    if (myCase == null) return const SizedBox.shrink();
                    return _CaseSummaryCard(myCase: myCase);
                  },
                ),
                const SizedBox(height: 16),
                caseAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (myCase) {
                    if (myCase == null) return const SizedBox.shrink();
                    return sessionsAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (sessions) {
                        final hasCompletedToday = sessions.any(
                          (session) => _isToday(session.sessionDate),
                        );
                        return SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: hasCompletedToday
                                ? null
                                : () => _endSession(myCase.id),
                            icon: Icon(
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
                _SectionHeader(
                  icon: Icons.event_note_outlined,
                  color: _Accent.patient,
                  title: 'جلساتي',
                  subtitleSpans: [
                    TextSpan(
                      text: '${sessionsAsync.value?.length ?? 0}',
                      style: TextStyle(
                        color: _Accent.patient,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        shadows: [
                          Shadow(color: _Accent.patient.withValues(alpha: 0.55), blurRadius: 14),
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
                    final sorted = [...sessions]
                      ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
                    return _SessionsGroup(sessions: sorted);
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

/// Category accent colors — every screen picks its palette from here so
/// data reads by color instead of a flat, uniform white.
class _Accent {
  static const Color doctor = Color(0xFF5AC8FA);
  static const Color patient = Color(0xFF34D399);
  static const Color caseC = Color(0xFFFBBF24);
  static const Color device = Color(0xFFA78BFA);
  static const Color unlinked = Color(0xFFF87171);
  static const Color clinic = Color(0xFF22D3EE);
}

/// Fixed text styles so every screen stays visually consistent.
class _Txt {
  static const headline = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);
  static const sectionTitle = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700);
  static const sectionSubtitle = TextStyle(color: Colors.white60, fontSize: 12.5);
  static const tileTitle = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
  static const tileSubtitle = TextStyle(color: Colors.white60, fontSize: 12);
  static const body = TextStyle(color: Colors.white60, fontSize: 13);
  static const error = TextStyle(color: Color(0xFFF87171));
}

/// Small circular badge behind a data-category icon: tinted fill,
/// tinted border, colored icon — replaces flat white avatars/icons.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Unified section header: colored side bar + small icon + white title
/// + a lighter subtitle line (which may contain a glowing highlight,
/// e.g. a count).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
    this.subtitleSpans,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<InlineSpan>? subtitleSpans;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: subtitleSpans != null ? 34 : 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _Txt.sectionTitle),
              if (subtitleSpans != null) ...[
                const SizedBox(height: 2),
                Text.rich(TextSpan(style: _Txt.sectionSubtitle, children: subtitleSpans)),
              ],
            ],
          ),
        ),
      ],
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
                _IconBadge(icon: Icons.medical_services_outlined, color: _Accent.device, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('الجهاز: ${myCase.deviceTypeName}', style: _Txt.tileTitle),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (myCase.treatmentPlan.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.assignment_outlined, size: 16, color: _Accent.patient),
                const SizedBox(width: 6),
                const Text('خطة العلاج', style: _Txt.tileTitle),
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
              Text(label, style: _Txt.tileSubtitle),
            ],
          ),
        ),
      );
    }

    if (remaining == null) {
      return counter('الجلسات المكتملة', completed, _Accent.patient);
    }
    return Row(
      children: [
        counter('الجلسات المكتملة', completed, _Accent.patient),
        const SizedBox(width: 10),
        counter('المتبقية', remaining!, _Accent.caseC),
      ],
    );
  }
}

/// كل جلسات المريض مجمّعة داخل حاوية زجاجية واحدة، مفصولة بخطوط رفيعة
/// شفافة بدل بطاقة مستقلة لكل جلسة.
class _SessionsGroup extends StatelessWidget {
  const _SessionsGroup({required this.sessions});
  final List<SessionModel> sessions;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < sessions.length; i++) ...[
            _SessionTile(session: sessions[i]),
            if (i != sessions.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: Colors.white.withValues(alpha: 0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final SessionModel session;

  @override
  Widget build(BuildContext context) {
    final date = session.sessionDate;
    final dateLabel = '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    final completed = session.patientResponse.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _IconBadge(icon: Icons.event_note, color: _Accent.patient),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('جلسة $dateLabel', style: _Txt.tileTitle),
                if (session.patientResponse.isNotEmpty)
                  Text(session.patientResponse, style: _Txt.tileSubtitle)
                else if (session.durationMinutes != null)
                  Text('المدة: ${session.durationMinutes} دقيقة', style: _Txt.tileSubtitle),
              ],
            ),
          ),
          Icon(
            completed ? Icons.check_circle : Icons.radio_button_unchecked,
            color: completed ? _Accent.patient : Colors.white38,
          ),
        ],
      ),
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
          _IconBadge(icon: Icons.event_busy_outlined, color: _Accent.patient, size: 44),
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
          _IconBadge(icon: Icons.error_outline, color: _Accent.unlinked, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: _Txt.error),
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
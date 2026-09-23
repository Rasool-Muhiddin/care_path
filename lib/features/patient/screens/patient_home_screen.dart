import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../doctor/models/case_model.dart' show CaseModel;
import '../../doctor/models/weekly_episode_log_model.dart';
import '../models/session_model.dart';
import '../patient_providers.dart';
import 'end_session_dialog.dart';

/// الشاشة الرئيسية للمريض: ملخص حالته (خطة العلاج ونوع الجهاز)، عداد
/// بدء/إنهاء الجلسة، زر فتح المحادثة مع الطبيب، وقائمة بجلساته السابقة.
class PatientHomeScreen extends ConsumerStatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  DateTime? _sessionStartedAt;
  Timer? _tickTimer;
  Duration _elapsed = Duration.zero;
  bool _isWeeklyDialogShowing = false;

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  void _startSession() {
    setState(() {
      _sessionStartedAt = DateTime.now();
      _elapsed = Duration.zero;
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sessionStartedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_sessionStartedAt!));
    });
  }

  Future<void> _endSession(int caseId) async {
    // نقرّب المدة لأقرب دقيقة، وبحد أدنى دقيقة واحدة حتى لا تُسجَّل جلسة
    // بمدة صفر لو ضغط المريض "إنهاء" بعد ثوانٍ من "بدء"
    final minutes = _elapsed.inSeconds >= 30
        ? (_elapsed.inSeconds / 60).round()
        : 1;
    _tickTimer?.cancel();
    final started = _sessionStartedAt != null;
    setState(() {
      _tickTimer = null;
      _sessionStartedAt = null;
      _elapsed = Duration.zero;
    });
    await showEndSessionDialog(
      context,
      caseId,
      durationMinutes: started ? minutes : null,
    );
    ref.invalidate(myCaseProvider);
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

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
              return AlertDialog(
                title: const Text('تقرير أسبوعي إلزامي'),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كم نوبة كانت لديك خلال الأسبوع من '
                        '${_formatDate(weekStart)} إلى ${_formatDate(weekEnd)}؟',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'عدد النوبات',
                          errorText: errorText,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  FilledButton(
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
                            child: CircularProgressIndicator(strokeWidth: 2),
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
      appBar: AppBar(
        title: Text('مرحباً $username'),
        actions: [
          if (myCaseId != null)
            IconButton(
              icon: Badge(
                isLabelVisible: unreadForMyCase > 0,
                label: Text('$unreadForMyCase'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              tooltip: 'المحادثة مع الطبيب',
              onPressed: () => context.push('/patient/chat/$myCaseId'),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authStateProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mySessionsProvider);
          ref.invalidate(myCaseProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            caseAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
                if (_sessionStartedAt == null) {
                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _startSession,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('بدء الجلسة'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  );
                }
                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _formatElapsed(_elapsed),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const Text('الجلسة جارية...'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _endSession(myCase.id),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('إنهاء الجلسة'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ],
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
                  return Text(
                    'الجلسات المكتملة: ${myCase.completedSessionsCount}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الجلسات المكتملة: ${myCase.completedSessionsCount}'),
                    Text('المتبقية: ${myCase.remainingSessionsCount}'),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('جلساتي', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            sessionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
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
                return Column(
                  children: sorted.map((s) => _SessionTile(session: s)).toList(),
                );
              },
            ),
          ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (myCase.deviceTypeName != null) ...[
              Row(
                children: [
                  const Icon(Icons.medical_services_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('الجهاز: ${myCase.deviceTypeName}'),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (myCase.treatmentPlan.isNotEmpty) ...[
              const Text('خطة العلاج', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(myCase.treatmentPlan),
            ],
          ],
        ),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.event_note)),
        title: Text('جلسة $dateLabel'),
        subtitle: session.patientResponse.isNotEmpty
            ? Text(session.patientResponse)
            : (session.durationMinutes != null
                ? Text('المدة: ${session.durationMinutes} دقيقة')
                : null),
        trailing: session.patientResponse.isNotEmpty
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text('لا توجد جلسات بعد')),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../chat/logic/chat_notifier.dart';
import '../../doctor/models/case_model.dart' show CaseModel;
import '../models/session_model.dart';
import '../patient_providers.dart';
import 'end_session_dialog.dart';

/// الشاشة الرئيسية للمريض: ملخص حالته (خطة العلاج ونوع الجهاز)، زر
/// إنهاء الجلسة، زر فتح المحادثة مع الطبيب، وقائمة بجلساته السابقة.
class PatientHomeScreen extends ConsumerWidget {
  const PatientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final username =
        authState is AuthAuthenticated ? authState.user.username : '';
    final sessionsAsync = ref.watch(mySessionsProvider);
    final caseAsync = ref.watch(myCaseProvider);
    final myCaseId = caseAsync.value?.id;
    final unreadByCase = ref.watch(unreadByCaseProvider).value ?? {};
    final unreadForMyCase = myCaseId != null ? (unreadByCase[myCaseId] ?? 0) : 0;

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
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => showEndSessionDialog(context, myCase.id),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('تم إنهاء الجلسة'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
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
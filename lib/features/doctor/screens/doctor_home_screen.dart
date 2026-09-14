import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/ltr_scope.dart';
import '../doctor_providers.dart';
import '../models/case_model.dart';
import 'case_details_screen.dart';

/// Doctor's home screen: list of their cases, prioritized (active cases
/// needing follow-up first).
///
/// Note: sorting currently relies only on `status`, because "last
/// session" data isn't available here yet. To actually show "patients
/// who haven't logged a session today", we'd need to fetch each case's
/// latest TreatmentSession (either a new aggregate endpoint, or a field
/// added to CaseSerializer).
class DoctorHomeScreen extends ConsumerWidget {
  const DoctorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final username = authState is AuthAuthenticated ? authState.user.username : '';
    final casesAsync = ref.watch(myCasesProvider);

    return LtrScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Dr. $username'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authStateProvider.notifier).logout(),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/doctor/new-case'),
          icon: const Icon(Icons.add),
          label: const Text('New Case'),
        ),
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myCasesProvider),
          child: casesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(myCasesProvider),
            ),
            data: (cases) {
              if (cases.isEmpty) {
                return const _EmptyView();
              }
              final sorted = _sortByPriority(cases);
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) => _CaseTile(caseModel: sorted[index]),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Display priority: in-treatment/under-evaluation first (need daily
  /// follow-up), then new, then closed last (no attention needed now)
  List<CaseModel> _sortByPriority(List<CaseModel> cases) {
    int priorityOf(CaseStatus status) {
      switch (status) {
        case CaseStatus.inTreatment:
          return 0;
        case CaseStatus.underEvaluation:
          return 1;
        case CaseStatus.newCase:
          return 2;
        case CaseStatus.closed:
          return 3;
      }
    }

    final sorted = [...cases]
      ..sort((a, b) {
        final p = priorityOf(a.status).compareTo(priorityOf(b.status));
        if (p != 0) return p;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return sorted;
  }
}

class _CaseTile extends ConsumerWidget {
  const _CaseTile({required this.caseModel});
  final CaseModel caseModel;

  Color _statusColor(CaseStatus status) {
    switch (status) {
      case CaseStatus.inTreatment:
        return Colors.green;
      case CaseStatus.underEvaluation:
        return Colors.orange;
      case CaseStatus.newCase:
        return Colors.blue;
      case CaseStatus.closed:
        return Colors.grey;
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(caseSessionsProvider(caseModel.id));

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(caseModel.status).withValues(alpha: 0.15),
        child: Icon(Icons.person, color: _statusColor(caseModel.status)),
      ),
      title: Text(caseModel.patientName.isNotEmpty ? caseModel.patientName : 'Patient #${caseModel.patientId}'),
      subtitle: Row(
        children: [
          Text(caseModel.diagnosisType.label),
          const Text(' • '),
          sessionsAsync.when(
            loading: () => const Text('...'),
            error: (_, __) => const Text('Sessions: —'),
            data: (sessions) {
              final completedToday = sessions.any((s) => _isToday(s.sessionDate));
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${sessions.length} sessions'),
                  if (completedToday) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.check_circle, size: 14, color: Colors.green),
                    const Text(' Today', style: TextStyle(color: Colors.green, fontSize: 12)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
      trailing: Chip(
        label: Text(caseModel.status.label, style: const TextStyle(fontSize: 12)),
        backgroundColor: _statusColor(caseModel.status).withValues(alpha: 0.15),
        side: BorderSide.none,
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaseDetailsScreen(caseModel: caseModel)),
        );
      },
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No cases yet — tap "New Case" to get started'),
            ),
          ),
        ),
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
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
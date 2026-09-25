import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
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
    final topPadding = kToolbarHeight + MediaQuery.of(context).padding.top;

    return LtrScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: AppGlassColors.baseDark,
        appBar: AppBar(
          title: Text('Dr. $username', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => ref.read(authStateProvider.notifier).logout(),
            ),
          ],
        ),
        floatingActionButton: _GlassFab(
          onPressed: () => context.push('/doctor/new-case'),
        ),
        body: AppGradientBackground(
          child: Padding(
            padding: EdgeInsets.only(top: topPadding),
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(myCasesProvider),
              child: casesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
                error: (error, _) => _ErrorView(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(myCasesProvider),
                ),
                data: (cases) {
                  if (cases.isEmpty) {
                    return const _EmptyView();
                  }
                  final sorted = _sortByPriority(cases);
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) => _CaseTile(caseModel: sorted[index]),
                  );
                },
              ),
            ),
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

/// A frosted, pill-shaped extended FAB matching the glass theme
/// (plain [FloatingActionButton.extended] can't blur its own
/// background, so this builds the same shape manually).
class _GlassFab extends StatelessWidget {
  const _GlassFab({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 28,
      opacity: 0.16,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: Colors.white),
                SizedBox(width: 8),
                Text('New Case', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaseTile extends ConsumerWidget {
  const _CaseTile({required this.caseModel});
  final CaseModel caseModel;

  Color _statusColor(CaseStatus status) {
    switch (status) {
      case CaseStatus.inTreatment:
        return const Color(0xFF6EE7A0);
      case CaseStatus.underEvaluation:
        return const Color(0xFFFFC46E);
      case CaseStatus.newCase:
        return const Color(0xFF7FB3FF);
      case CaseStatus.closed:
        return Colors.white54;
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(caseSessionsProvider(caseModel.id));
    final statusColor = _statusColor(caseModel.status);

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CaseDetailsScreen(caseModel: caseModel)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.18),
                  child: Icon(Icons.person, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caseModel.patientName.isNotEmpty
                            ? caseModel.patientName
                            : 'Patient #${caseModel.patientId}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(caseModel.diagnosisType.label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const Text(' • ', style: TextStyle(color: Colors.white38)),
                          sessionsAsync.when(
                            loading: () => const Text('...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            error: (_, __) => const Text('Sessions: —', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            data: (sessions) {
                              final completedToday = sessions.any((s) => _isToday(s.sessionDate));
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${sessions.length} sessions', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  if (completedToday) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.check_circle, size: 14, color: Color(0xFF6EE7A0)),
                                    const Text(' Today', style: TextStyle(color: Color(0xFF6EE7A0), fontSize: 12)),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    caseModel.status.label,
                    style: TextStyle(fontSize: 12, color: statusColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
              child: Text(
                'No cases yet — tap "New Case" to get started',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
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
                  const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
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
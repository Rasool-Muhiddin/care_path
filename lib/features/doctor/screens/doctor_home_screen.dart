import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/baghdad_time.dart';
import '../../../core/widgets/app_widgets.dart';
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
          title: _DrTitle(username: username),
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
                error: (error, _) => ErrorView(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(myCasesProvider),
                ),
                data: (cases) {
                  if (cases.isEmpty) {
                    return const EmptyView(icon: Icons.folder_off_outlined, color: AppAccent.caseC, message: 'No cases yet — tap "New Case" to get started');
                  }
                  final sorted = _sortByPriority(cases);
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
                    children: [
                      SectionHeader(
                        icon: Icons.folder_shared_outlined,
                        color: AppAccent.caseC,
                        title: 'My Cases',
                        subtitleSpans: [
                          TextSpan(
                            text: '${sorted.length}',
                            style: TextStyle(
                              color: AppAccent.caseC,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              shadows: [
                                Shadow(color: AppAccent.caseC.withValues(alpha: 0.55), blurRadius: 14),
                              ],
                            ),
                          ),
                          const TextSpan(text: ' active cases'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _CasesGroup(cases: sorted),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Display priority: in-treatment first (needs daily follow-up), closed
  /// last (no attention needed now)
  List<CaseModel> _sortByPriority(List<CaseModel> cases) {
    int priorityOf(CaseStatus status) {
      switch (status) {
        case CaseStatus.inTreatment:
          return 0;
        case CaseStatus.closed:
          return 1;
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

/// AppBar title: a small glass-style "Dr" badge followed by the doctor's
/// name — replaces the plain "Dr. name" text. Long names wrap to a second
/// line instead of being cut with "...".
class _DrTitle extends StatelessWidget {
  const _DrTitle({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    const accent = AppAccent.doctor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: const Text(
            'Dr.',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        if (username.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              username,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        ],
      ],
    );
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

/// All case rows grouped inside a single glass panel, separated by
/// thin translucent dividers instead of one card per item.
class _CasesGroup extends StatelessWidget {
  const _CasesGroup({required this.cases});
  final List<CaseModel> cases;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < cases.length; i++) ...[
            _CaseTile(caseModel: cases[i]),
            if (i != cases.length - 1)
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

class _CaseTile extends ConsumerWidget {
  const _CaseTile({required this.caseModel});
  final CaseModel caseModel;

  Color _statusColor(CaseStatus status) {
    switch (status) {
      case CaseStatus.inTreatment:
        return const Color(0xFF6EE7A0);
      case CaseStatus.closed:
        return Colors.white54;
    }
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(caseSessionsProvider(caseModel.id));
    final statusColor = _statusColor(caseModel.status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CaseDetailsScreen(caseModel: caseModel)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              IconBadge(icon: Icons.person, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caseModel.patientName.isNotEmpty
                          ? caseModel.patientName
                          : 'Patient #${caseModel.patientId}',
                      style: AppText.tileTitle,
                    ),
                    const SizedBox(height: 2),
                    // Wrap (not Row): diagnosis • sessions • Today moves to a new
                    // line on narrow phones / large fonts instead of overflowing.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(caseModel.diagnosisType.label, style: AppText.tileSubtitle),
                        const Text(' • ', style: TextStyle(color: Colors.white38)),
                        sessionsAsync.when(
                          loading: () => const Text('...', style: AppText.tileSubtitle),
                          error: (_, __) => const Text('Sessions: —', style: AppText.tileSubtitle),
                          data: (sessions) {
                            final completedToday = sessions.any((s) => isBaghdadToday(s.sessionDate));
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${sessions.length} sessions', style: AppText.tileSubtitle),
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
    );
  }
}


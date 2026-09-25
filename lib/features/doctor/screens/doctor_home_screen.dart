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
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
                    children: [
                      _SectionHeader(
                        icon: Icons.folder_shared_outlined,
                        color: _Accent.caseC,
                        title: 'My Cases',
                        subtitleSpans: [
                          TextSpan(
                            text: '${sorted.length}',
                            style: TextStyle(
                              color: _Accent.caseC,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              shadows: [
                                Shadow(color: _Accent.caseC.withValues(alpha: 0.55), blurRadius: 14),
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
              _IconBadge(icon: Icons.person, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caseModel.patientName.isNotEmpty
                          ? caseModel.patientName
                          : 'Patient #${caseModel.patientId}',
                      style: _Txt.tileTitle,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(caseModel.diagnosisType.label, style: _Txt.tileSubtitle),
                        const Text(' • ', style: TextStyle(color: Colors.white38)),
                        sessionsAsync.when(
                          loading: () => Text('...', style: _Txt.tileSubtitle),
                          error: (_, __) => Text('Sessions: —', style: _Txt.tileSubtitle),
                          data: (sessions) {
                            final completedToday = sessions.any((s) => _isToday(s.sessionDate));
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${sessions.length} sessions', style: _Txt.tileSubtitle),
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

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: GlassContainer(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBadge(icon: Icons.folder_off_outlined, color: _Accent.caseC, size: 48),
                    const SizedBox(height: 14),
                    const Text(
                      'No cases yet — tap "New Case" to get started',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
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
              padding: const EdgeInsets.all(20),
              child: GlassContainer(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBadge(icon: Icons.error_outline, color: _Accent.unlinked, size: 48),
                    const SizedBox(height: 14),
                    Text(message, textAlign: TextAlign.center, style: _Txt.error),
                    const SizedBox(height: 16),
                    _RetryButton(onPressed: onRetry),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass-styled retry button used by every empty/error state.
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
      label: const Text('Retry', style: TextStyle(color: Colors.white)),
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
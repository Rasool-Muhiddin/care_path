import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../engineer_providers.dart';
import '../models/clinic_model.dart';
import 'add_clinic_dialog.dart';

/// Clinics tab — list of clinics with a FAB to add a new one.
///
/// Hosted inside [EngineerHomeScreen]'s `TabBarView`, which already
/// wraps the whole engineer section in a single [AppGradientBackground] —
/// this tab stays transparent on purpose so that shared background shows
/// through instead of stacking a second one on top.
class ClinicsTab extends ConsumerWidget {
  const ClinicsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = ref.watch(isManagerProvider);
    final clinicsAsync = ref.watch(clinicsListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // الإضافة لمدير المهندسين فقط (السيرفر يرفضها لغيره)
      floatingActionButton: !isManager
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAddClinicDialog(context),
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New Clinic'),
            ),
      body: RefreshIndicator(
        color: AppGlassColors.baseDark,
        backgroundColor: Colors.white,
        onRefresh: () async => ref.invalidate(clinicsListProvider),
        child: clinicsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
          error: (error, _) => ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(clinicsListProvider),
          ),
          data: (clinics) {
            if (clinics.isEmpty) {
              return const EmptyView(icon: Icons.local_hospital_outlined, color: AppAccent.clinic, message: 'No clinics yet — tap "New Clinic" to get started');
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
              children: [
                SectionHeader(
                  icon: Icons.local_hospital_outlined,
                  color: AppAccent.clinic,
                  title: 'Clinics',
                  subtitleSpans: [
                    TextSpan(
                      text: '${clinics.length}',
                      style: TextStyle(
                        color: AppAccent.clinic,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        shadows: [
                          Shadow(color: AppAccent.clinic.withValues(alpha: 0.55), blurRadius: 14),
                        ],
                      ),
                    ),
                    const TextSpan(text: ' partner clinics'),
                  ],
                ),
                const SizedBox(height: 12),
                _ClinicsGroup(clinics: clinics),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// All clinic rows grouped inside a single glass panel, separated by
/// thin translucent dividers instead of one card per clinic.
class _ClinicsGroup extends StatelessWidget {
  const _ClinicsGroup({required this.clinics});
  final List<ClinicModel> clinics;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < clinics.length; i++) ...[
            _ClinicTile(clinic: clinics[i]),
            if (i != clinics.length - 1)
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

class _ClinicTile extends ConsumerWidget {
  const _ClinicTile({required this.clinic});
  final ClinicModel clinic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = ref.watch(isManagerProvider);
    final subtitleParts = [
      if (clinic.address.isNotEmpty) clinic.address,
      if (clinic.phoneNumber.isNotEmpty) clinic.phoneNumber,
    ];
    final engineerName = clinic.responsibleEngineerName?.trim() ?? '';
    final engineerLabel = engineerName.isNotEmpty ? engineerName : 'Not assigned';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const IconBadge(icon: Icons.local_hospital_outlined, color: AppAccent.clinic),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clinic.name, style: AppText.tileTitle),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitleParts.join(' • '), style: AppText.tileSubtitle),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.engineering_outlined, size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Supervising Engineer: $engineerLabel',
                        style: AppText.tileSubtitle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (clinic.contactPerson.isNotEmpty) ...[
            // Plain Container instead of Chip — Chip's built-in Material
            // surface/elevation can wash out a custom backgroundColor
            // depending on the app's theme, which is what made this
            // pill unreadable (white text on white) in testing.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppAccent.clinic.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppAccent.clinic.withValues(alpha: 0.4)),
              ),
              child: Text(
                clinic.contactPerson,
                style: const TextStyle(fontSize: 12, color: AppAccent.clinic),
              ),
            ),
            const SizedBox(width: 4),
          ],
          // التعديل لمدير المهندسين فقط
          if (isManager)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white70),
              tooltip: 'Edit',
              onPressed: () => showEditClinicDialog(context, clinic),
            ),
        ],
      ),
    );
  }
}


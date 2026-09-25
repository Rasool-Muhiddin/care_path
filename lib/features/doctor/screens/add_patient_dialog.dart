import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';

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

/// Generates a secure random password (letters + digits, 10 chars).
/// Shown once to the doctor after registration so they can hand it to
/// the patient for their first login.
String _generatePassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  final rand = Random.secure();
  return List.generate(10, (_) => chars[rand.nextInt(chars.length)]).join();
}

/// Dialog that lets the doctor register a brand-new patient (walk-in,
/// no existing account) directly from the "New Case" screen. On success
/// it shows the generated username/password once, and returns the new
/// patient's id + username to the caller so it can auto-select them.
class AddPatientDialogResult {
  final int id;
  final String username;
  const AddPatientDialogResult({required this.id, required this.username});
}

Future<AddPatientDialogResult?> showAddPatientDialog(
  BuildContext context,
  WidgetRef ref,
) {
  return showDialog<AddPatientDialogResult>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppGlassColors.baseDark.withValues(alpha: 0.55),
    builder: (context) => const _AddPatientDialog(),
  );
}

class _AddPatientDialogState extends ConsumerState<_AddPatientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  // Set once registration succeeds — switches the dialog to "success" view
  AddPatientDialogResult? _createdPatient;
  String? _generatedPassword;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final password = _generatePassword();

    try {
      final client = ref.read(apiClientProvider);
      final response = await client.raw.post(
        ApiEndpoints.register,
        data: {
          'username': _usernameController.text.trim(),
          'password': password,
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'email': _emailController.text.trim(),
          'role': 'patient',
          'phone_number': _phoneController.text.trim(),
        },
      );
      final data = response.data as Map<String, dynamic>;
      setState(() {
        _createdPatient = AddPatientDialogResult(
          id: data['id'] as int,
          username: data['username'] as String,
        );
        _generatedPassword = password;
      });
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_createdPatient != null) {
      return LtrScope(
        child: _SuccessView(
          username: _createdPatient!.username,
          password: _generatedPassword!,
          onDone: () => Navigator.of(context).pop(_createdPatient),
        ),
      );
    }

    return LtrScope(
      child: GlassDialog(
        title: 'Add New Patient',
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Row(
                    children: [
                      _IconBadge(icon: Icons.error_outline, color: _Accent.unlinked, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_errorMessage!, style: _Txt.error),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _SectionHeader(
                  icon: Icons.person_add_alt_1_outlined,
                  color: _Accent.patient,
                  title: 'Patient Details',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: glassInputDecoration('First Name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _lastNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: glassInputDecoration('Last Name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: glassInputDecoration(
                    'Username',
                    helperText: 'Used by the patient to log in later',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: glassInputDecoration('Phone Number'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: glassInputDecoration('Email (optional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: Colors.white,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _AddPatientDialog extends ConsumerStatefulWidget {
  const _AddPatientDialog();

  @override
  ConsumerState<_AddPatientDialog> createState() => _AddPatientDialogState();
}

/// Shown once after successful registration — the doctor must copy
/// these credentials down for the patient, as the password is never
/// retrievable again afterward.
class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.username,
    required this.password,
    required this.onDone,
  });

  final String username;
  final String password;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: 'Patient Added',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: Icons.check_circle_outline, color: _Accent.patient, size: 32),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Save these credentials — the password cannot be shown again.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GlassContainer(
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                _CredentialRow(icon: Icons.person_outline, label: 'Username', value: username),
                Divider(height: 18, thickness: 1, color: Colors.white.withValues(alpha: 0.08)),
                _CredentialRow(icon: Icons.lock_outline, label: 'Password', value: password),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Give these to the patient to log in once they install the app.',
            style: _Txt.body,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: 'Username: $username\nPassword: $password'));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')),
            );
          },
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('Copy'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onDone,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            foregroundColor: Colors.white,
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconBadge(icon: icon, color: _Accent.patient, size: 32),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(label, style: _Txt.tileTitle),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [Shadow(color: _Accent.patient.withValues(alpha: 0.55), blurRadius: 14)],
            ),
          ),
        ),
      ],
    );
  }
}
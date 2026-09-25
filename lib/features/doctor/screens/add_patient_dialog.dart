import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/ltr_scope.dart';

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
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 12),
                ],
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
          const Text(
            'Save these credentials — the password cannot be shown again.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          _CredentialRow(label: 'Username', value: username),
          const SizedBox(height: 8),
          _CredentialRow(label: 'Password', value: password),
          const SizedBox(height: 16),
          const Text(
            'Give these to the patient to log in once they install the app.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
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
  const _CredentialRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
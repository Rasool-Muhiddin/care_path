import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../auth/auth_state.dart';
import '../permissions/user_role.dart';
import 'glass_container.dart';

/// UI strings for [AccountMenuButton] and the delete-account flow —
/// English for doctor/engineer, Arabic for the patient.
class AccountMenuStrings {
  const AccountMenuStrings({
    required this.direction,
    required this.tooltip,
    required this.logout,
    required this.deleteAccount,
    required this.whatIsDeleted,
    required this.passwordTitle,
    required this.passwordHint,
    required this.finalTitle,
    required this.finalBody,
    required this.cancel,
    required this.next,
    required this.delete,
    required this.ok,
    required this.blockedTitle,
    required this.blockedMessage,
    required this.failedTitle,
  });

  final TextDirection direction;
  final String tooltip;
  final String logout;
  final String deleteAccount;
  final String Function(UserRole role) whatIsDeleted;
  final String passwordTitle;
  final String passwordHint;
  final String finalTitle;
  final String finalBody;
  final String cancel;
  final String next;
  final String delete;
  final String ok;
  final String blockedTitle;

  /// Text for a server block code; null = show the server's own message.
  final String? Function(String code) blockedMessage;
  final String failedTitle;

  static final en = AccountMenuStrings(
    direction: TextDirection.ltr,
    tooltip: 'Account',
    logout: 'Log out',
    deleteAccount: 'Delete account',
    whatIsDeleted: (role) => switch (role) {
      UserRole.doctor => 'Your account and sign-in will be deleted permanently.\n\n'
          'Records of your closed cases are kept without your name, so your patients\' history '
          'stays complete. Messages you sent stay in the conversations as "Deleted user".',
      UserRole.engineer => 'Your account and sign-in will be deleted permanently.\n\n'
          'Messages you sent stay in the patients\' conversations as "Deleted user", and clinics '
          'you are responsible for will have no responsible engineer until one is assigned.',
      UserRole.patient => 'Your account and all of your data will be deleted permanently.',
    },
    passwordTitle: 'Confirm your password',
    passwordHint: 'Current password',
    finalTitle: 'Delete your account?',
    finalBody: 'This can\'t be undone. You will be signed out on every device.',
    cancel: 'Cancel',
    next: 'Continue',
    delete: 'Delete account',
    ok: 'OK',
    blockedTitle: 'Account can\'t be deleted',
    blockedMessage: (code) => switch (code) {
      'doctor_has_active_cases' => 'You still have patients with open cases. Contact Tera so your '
          'patients can be reassigned to another doctor before you delete your account.',
      'manager_account' => 'The manager account can\'t be deleted from the app. '
          'It can only be removed from the Django admin.',
      _ => null,
    },
    failedTitle: 'Account not deleted',
  );

  static final ar = AccountMenuStrings(
    direction: TextDirection.rtl,
    tooltip: 'الحساب',
    logout: 'تسجيل الخروج',
    deleteAccount: 'حذف الحساب',
    whatIsDeleted: (_) => 'سيتم حذف حسابك وكل بياناتك نهائياً:\n'
        '• حالتك المرضية\n'
        '• الجلسات\n'
        '• النوبات المسجّلة وتأكيداتها\n'
        '• المحادثات مع الطبيب والمهندس\n\n'
        'ويصبح الجهاز المرتبط بحالتك متاحاً لمريض آخر.',
    passwordTitle: 'تأكيد كلمة المرور',
    passwordHint: 'كلمة المرور الحالية',
    finalTitle: 'حذف حسابك؟',
    finalBody: 'لا يمكن التراجع عن هذا الإجراء، وسيتم تسجيل خروجك من كل الأجهزة.',
    cancel: 'إلغاء',
    next: 'متابعة',
    delete: 'حذف الحساب',
    ok: 'حسناً',
    blockedTitle: 'لا يمكن حذف الحساب',
    blockedMessage: (_) => null,
    failedTitle: 'لم يتم حذف الحساب',
  );
}

enum _AccountAction { logout, deleteAccount }

/// AppBar account menu (log out / delete account), shared by every role's
/// home screen so account deletion is always in the same place.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key, required this.strings});
  final AccountMenuStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_AccountAction>(
      tooltip: strings.tooltip,
      icon: const Icon(Icons.account_circle_outlined, color: Colors.white),
      color: AppGlassColors.baseDark,
      onSelected: (action) => switch (action) {
        _AccountAction.logout => ref.read(authStateProvider.notifier).logout(),
        _AccountAction.deleteAccount => _deleteAccountFlow(context, ref, strings),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _AccountAction.logout,
          child: _MenuRow(icon: Icons.logout, text: strings.logout, direction: strings.direction),
        ),
        PopupMenuItem(
          value: _AccountAction.deleteAccount,
          child: _MenuRow(
            icon: Icons.delete_forever_outlined,
            text: strings.deleteAccount,
            direction: strings.direction,
            color: const Color(0xFFF87171),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.text, required this.direction, this.color = Colors.white});
  final IconData icon;
  final String text;
  final TextDirection direction;
  final Color color;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: direction,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Flexible(child: Text(text, style: TextStyle(color: color))),
          ],
        ),
      );
}

/// Explain → password → final confirmation → API. On success the auth state
/// becomes unauthenticated and the router goes to the login screen.
Future<void> _deleteAccountFlow(BuildContext context, WidgetRef ref, AccountMenuStrings s) async {
  final auth = ref.read(authStateProvider);
  if (auth is! AuthAuthenticated) return;

  // 0. Blocked (doctor with open cases, manager)? Say so before asking anything.
  try {
    await ref.read(authRepositoryProvider).checkAccountDeletion();
  } on AccountDeletionBlocked catch (e) {
    if (context.mounted) await _message(context, s, s.blockedTitle, s.blockedMessage(e.code) ?? e.message);
    return;
  } catch (e) {
    if (context.mounted) await _message(context, s, s.failedTitle, e.toString());
    return;
  }
  if (!context.mounted) return;

  // 1. What will be deleted
  final proceed = await _confirm(context, s, s.deleteAccount, s.whatIsDeleted(auth.user.role), s.next);
  if (proceed != true || !context.mounted) return;

  // 2. Current password
  final password = await showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(strings: s),
  );
  if (password == null || password.isEmpty || !context.mounted) return;

  // 3. Final confirmation
  final confirmed = await _confirm(context, s, s.finalTitle, s.finalBody, s.delete, destructive: true);
  if (confirmed != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
  );
  Object? error;
  try {
    await ref.read(authRepositoryProvider).deleteAccount(password);
  } on AccountDeletionBlocked catch (e) {
    error = s.blockedMessage(e.code) ?? e.message;
  } catch (e) {
    error = e;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (error != null) {
    if (context.mounted) await _message(context, s, s.failedTitle, error.toString());
    return;
  }
  // Signed out locally -> the router redirects to the login screen.
  await ref.read(authStateProvider.notifier).signOutAfterAccountDeletion();
}

Future<bool?> _confirm(
  BuildContext context,
  AccountMenuStrings s,
  String title,
  String body,
  String action, {
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _Dialog(
      strings: s,
      title: title,
      content: Text(body, style: const TextStyle(color: Colors.white70, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(s.cancel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)) : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(action),
        ),
      ],
    ),
  );
}

Future<void> _message(BuildContext context, AccountMenuStrings s, String title, String body) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _Dialog(
      strings: s,
      title: title,
      content: Text(body, style: const TextStyle(color: Colors.white70, height: 1.5)),
      actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.ok))],
    ),
  );
}

class _Dialog extends StatelessWidget {
  const _Dialog({required this.strings, required this.title, required this.content, required this.actions});
  final AccountMenuStrings strings;
  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: strings.direction,
        child: AlertDialog(
          backgroundColor: AppGlassColors.baseDark,
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(child: content),
          actions: actions,
        ),
      );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.strings});
  final AccountMenuStrings strings;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isNotEmpty) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return _Dialog(
      strings: s,
      title: s.passwordTitle,
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: _obscure,
        style: const TextStyle(color: Colors.white),
        cursorColor: Colors.white,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: s.passwordHint,
          hintStyle: const TextStyle(color: Colors.white54),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.white54),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        ListenableBuilder(
          listenable: _controller,
          builder: (_, __) => FilledButton(
            onPressed: _controller.text.isEmpty ? null : _submit,
            child: Text(s.next),
          ),
        ),
      ],
    );
  }
}

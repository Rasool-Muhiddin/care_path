import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_state.dart';

/// Login Screen
///
/// Visual redesign only. Authentication logic is untouched:
///   - `authStateProvider` is watched exactly as before.
///   - `AuthLoading` / `AuthUnauthenticated.errorMessage` drive the UI
///     exactly as before.
///   - `ref.read(authStateProvider.notifier).login(username:, password:)`
///     is called exactly as before.
///
/// IMAGE ASSET — action needed:
/// Save the provided ear/waveform image into your project at:
///     assets/images/login_background.jpg
/// and make sure your pubspec.yaml lists the assets folder, e.g.:
///     flutter:
///       assets:
///         - assets/images/
/// (If your project already declares `assets/images/` this needs no change.)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;

  late final AnimationController _panelController;
  late final Animation<double> _panelFade;
  late final Animation<Offset> _panelSlide;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _panelFade = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOut,
    );
    _panelSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _panelController.dispose();
    super.dispose();
  }

  void _submit(bool isLoading) {
    if (isLoading) return;
    ref.read(authStateProvider.notifier).login(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState is AuthLoading;
    final errorMessage =
        authState is AuthUnauthenticated ? authState.errorMessage : null;

    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 1024;
    final isTablet = size.width >= 600 && size.width < 1024;
    final isCompactPhone = size.width < 360;

    return Scaffold(
      backgroundColor: _AppPalette.navyDeep,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Background(isDesktop: isDesktop),
          SafeArea(
            child: isDesktop
                ? _DesktopLayout(
                    child: _buildFormPanel(
                      context: context,
                      isLoading: isLoading,
                      errorMessage: errorMessage,
                      maxWidth: 420,
                      compact: false,
                    ),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompactPhone ? 18 : 24,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 48,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildFormPanel(
                            context: context,
                            isLoading: isLoading,
                            errorMessage: errorMessage,
                            maxWidth: isTablet ? 440 : double.infinity,
                            compact: isCompactPhone,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormPanel({
    required BuildContext context,
    required bool isLoading,
    required String? errorMessage,
    required double maxWidth,
    required bool compact,
  }) {
    return FadeTransition(
      opacity: _panelFade,
      child: SlideTransition(
        position: _panelSlide,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: _GlassPanel(
            padding: EdgeInsets.all(compact ? 20 : 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand mark — replace with your existing logo if available:
                // Image.asset('assets/images/logo.png', width: 40, height: 40)
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.06),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.16),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: _AppPalette.iceBlue,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Welcome',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 22 : 25,
                    fontWeight: FontWeight.w600,
                    color: _AppPalette.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: _AppPalette.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                _FieldLabel('Username'),
                const SizedBox(height: 6),
                _GlassTextField(
                  controller: _usernameController,
                  focusNode: _usernameFocus,
                  hintText: 'Enter your username',
                  icon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_passwordFocus),
                ),
                const SizedBox(height: 16),

                _FieldLabel('Password'),
                const SizedBox(height: 6),
                _GlassTextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  hintText: 'Enter your password',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(isLoading),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: _AppPalette.textSecondary,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),

                if (errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: errorMessage),
                ],

                const SizedBox(height: 24),
                _SignInButton(
                  isLoading: isLoading,
                  onPressed: () => _submit(isLoading),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: visual area — the background image already fills the
        // whole screen behind this Row, so this side is intentionally
        // left mostly clear to let it show through.
        const Expanded(flex: 6, child: SizedBox.shrink()),
        // Right: floating glass panel with generous breathing room.
        Expanded(
          flex: 5,
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _Background extends StatelessWidget {
  const _Background({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/login_background.jpg',
          fit: BoxFit.cover,
          alignment: isDesktop
              ? const Alignment(-0.35, -0.1)
              : const Alignment(-0.15, -0.25),
          errorBuilder: (context, error, stackTrace) {
            // Keeps the screen usable even before the asset is added.
            return const DecoratedBox(
              decoration: BoxDecoration(color: _AppPalette.navyDeep),
            );
          },
        ),
        // Overall cohesion tint so the photo reads as part of the app,
        // not a raw photograph.
        Container(color: _AppPalette.navyDeep.withOpacity(0.35)),
        // Directional gradient concentrating darkness where the form
        // sits, keeping the ear/signal detail visible elsewhere.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDesktop
                ? const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      _AppPalette.navyDeep,
                    ],
                    stops: [0.35, 0.95],
                  )
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _AppPalette.navyDeep.withOpacity(0.15),
                      _AppPalette.navyDeep.withOpacity(0.55),
                      _AppPalette.navyDeep.withOpacity(0.96),
                    ],
                    stops: const [0.0, 0.5, 0.92],
                  ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Glass building blocks
// ---------------------------------------------------------------------------

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _AppPalette.navyMid.withOpacity(0.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: _AppPalette.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: _AppPalette.textPrimary,
        fontSize: 15,
      ),
      cursorColor: _AppPalette.cyan,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: _AppPalette.textSecondary.withOpacity(0.7),
          fontSize: 14.5,
        ),
        prefixIcon: Icon(icon, color: _AppPalette.textSecondary, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _AppPalette.cyan, width: 1.4),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _AppPalette.errorSoft.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AppPalette.errorSoft.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: _AppPalette.errorSoft,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _AppPalette.errorSoft,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _AppPalette.cyan,
          disabledBackgroundColor: _AppPalette.cyan.withOpacity(0.6),
          foregroundColor: _AppPalette.navyDeep,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(_AppPalette.navyDeep),
                ),
              )
            : const Text(
                'Sign in',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

/// Shared design tokens for the Splash + Login screens.
///
/// Duplicated intentionally (see note in splash_screen.dart) so nothing
/// outside these two files needs to change. Happy to extract this into a
/// single shared `app_palette.dart` as a small separate follow-up if useful.
class _AppPalette {
  static const Color navyDeep = Color(0xFF0A1628);
  static const Color navyMid = Color(0xFF122A44);
  static const Color cyan = Color(0xFF4FD8E8);
  static const Color teal = Color(0xFF2EC4B6);
  static const Color iceBlue = Color(0xFFBFE3F0);
  static const Color textPrimary = Color(0xFFF3F7FB);
  static const Color textSecondary = Color(0xFF8FA6BF);
  static const Color errorSoft = Color(0xFFE8847A);
}
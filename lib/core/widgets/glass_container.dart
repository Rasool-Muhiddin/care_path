import 'dart:ui';

import 'package:flutter/material.dart';

/// App-wide glassmorphism palette built around the brand navy (#132659).
class AppGlassColors {
  static const Color base = Color(0xFF3B8DAB);
  static const Color baseLight = Color(0xFF1E3A73);
  static const Color baseDark = Color(0xFF0A1638);

  static const List<Color> backgroundGradient = [baseDark, base, baseLight];
}

/// Wraps a screen in the app's background image (assets/images/wall.png)
/// with a translucent navy gradient overlay on top, so the existing
/// white text / glass panels keep enough contrast to stay readable.
/// Use as the `body:` of a [Scaffold] whose AppBar is transparent.
class AppGradientBackground extends StatelessWidget {
  const AppGradientBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/wall.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppGlassColors.baseDark.withValues(alpha: 0.78),
              AppGlassColors.base.withValues(alpha: 0.72),
              AppGlassColors.baseLight.withValues(alpha: 0.78),
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A frosted-glass panel: blurred, semi-transparent, softly bordered.
/// Use for cards, tiles, dialogs, app bars — anything that should read
/// as "glass" floating over the navy gradient background.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blurSigma = 16,
    this.opacity = 0.10,
    this.borderOpacity = 0.18,
    this.padding,
    this.margin,
  });

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final double opacity;
  final double borderOpacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: borderOpacity),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Text-field styling for glass surfaces: light text on a translucent
/// fill, thin white-ish borders instead of the default Material look.
InputDecoration glassInputDecoration(String label, {String? helperText}) {
  return InputDecoration(
    labelText: label,
    helperText: helperText,
    labelStyle: const TextStyle(color: Colors.white70),
    helperStyle: const TextStyle(color: Colors.white54, fontSize: 11),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.white, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  );
}

/// A dialog shell that mimics [AlertDialog]'s title/content/actions
/// layout but renders as a glass panel instead of a solid Material
/// surface. Pair with `Dialog(backgroundColor: Colors.transparent)`
/// semantics — this widget already wraps itself in a [Dialog].
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: GlassContainer(
        borderRadius: 24,
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              content,
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}
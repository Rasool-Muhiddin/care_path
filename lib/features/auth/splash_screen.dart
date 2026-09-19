import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/splash_gate.dart';

/// Splash Screen
///
/// No auto-navigation and no timer of its own. Tapping "Enter" sets
/// [splashEnteredProvider] to true; the actual navigation away from
/// `/splash` is decided entirely by app_router.dart's redirect (which
/// waits for both this flag AND authStateProvider to settle before
/// leaving splash). This screen never navigates directly — it only
/// flips the flag the router is watching.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // One-shot entrance animation (mark, title, subtitle).
  late final AnimationController _introController;
  // Slow, continuous, looping animation driving the subtle waveform + glow.
  late final AnimationController _ambientController;

  late final Animation<double> _markFade;
  late final Animation<double> _markScale;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _buttonFade;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15 ),
    )..repeat();

    _markFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _markScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
      ),
    );

    _titleFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.30, 0.75, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.30, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _subtitleFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );

    _buttonFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.75, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _introController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  void _enter() {
    // لا تنقّل مباشر هنا — فقط نرفع العلم، والـ router (app_router.dart)
    // هو من يقرر الوجهة الصحيحة بناءً على حالة الـ auth الحالية.
    ref.read(splashEnteredProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 420;

    return Scaffold(
      backgroundColor: _AppPalette.navyDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Base gradient — deep navy, very subtle vertical shift.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _AppPalette.navyDeep,
                  _AppPalette.navyMid,
                  _AppPalette.navyDeep,
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // Soft blurred glow shapes (glassmorphism accents, not photos).
          AnimatedBuilder(
            animation: _ambientController,
            builder: (context, _) {
              final t = _ambientController.value;
              return Stack(
                children: [
                  Positioned(
                    top: -size.width * 0.35,
                    right: -size.width * 0.25,
                    child: _GlowOrb(
                      diameter: size.width * 0.9,
                      color: _AppPalette.cyan,
                      opacity: 0.10 + 0.03 * math.sin(t * 2 * math.pi),
                    ),
                  ),
                  Positioned(
                    bottom: -size.width * 0.4,
                    left: -size.width * 0.3,
                    child: _GlowOrb(
                      diameter: size.width * 0.95,
                      color: _AppPalette.teal,
                      opacity: 0.08 + 0.02 * math.cos(t * 2 * math.pi),
                    ),
                  ),
                ],
              );
            },
          ),

          // Subtle neural / signal waveform, always animating gently.
          Align(
            alignment: const Alignment(0, 0.62),
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) {
                return Opacity(
                  opacity: 0.5,
                  child: CustomPaint(
                    size: Size(size.width * 0.8, 64),
                    painter: _NeuralWavePainter(
                      progress: _ambientController.value,
                    ),
                  ),
                );
              },
            ),
          ),

          // Center content: mark, title, supporting line.
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 32 : 48,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _markFade,
                    child: ScaleTransition(
                      scale: _markScale,
                      child: const _BrandMark(),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FadeTransition(
                    opacity: _titleFade,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: Text(
                        'Welcome',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isCompact ? 30 : 34,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: _AppPalette.textPrimary,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FadeTransition(
                    opacity: _subtitleFade,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Text(
                        "A healthier tomorrow begins with care today  "
                        "and we're always here with you.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          color: _AppPalette.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  FadeTransition(
                    opacity: _buttonFade,
                    child: _EnterButton(onPressed: _enter),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand mark placeholder.
///
/// NOTE: No logo asset was included with the files provided, so nothing is
/// invented here. This is a neutral glass mark sized and positioned exactly
/// where a real logo should go. To use your existing logo, replace the
/// `Icon(...)` below with:
///
///   Image.asset('assets/images/logo.png', width: 44, height: 44)
///
/// and keep the surrounding glass container as-is (or remove it if your
/// logo already reads well on its own).
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.06),
        border: Border.all(
          color: Colors.white.withOpacity(0.16),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _AppPalette.cyan.withOpacity(0.18),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      // TODO: replace with your existing app logo (see note above).
      child: const Icon(
        Icons.graphic_eq_rounded,
        size: 40,
        color: _AppPalette.iceBlue,
      ),
    );
  }
}

class _EnterButton extends StatelessWidget {
  const _EnterButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [_AppPalette.cyan, _AppPalette.teal],
            ),
            boxShadow: [
              BoxShadow(
                color: _AppPalette.cyan.withOpacity(0.35),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: _AppPalette.navyDeep,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 20, color: _AppPalette.navyDeep),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.diameter,
    required this.color,
    required this.opacity,
  });

  final double diameter;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(opacity.clamp(0.0, 1.0)),
              color.withOpacity(0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimal abstract signal line — deliberately calm, not an ECG trace.
class _NeuralWavePainter extends CustomPainter {
  _NeuralWavePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    void drawLine({
      required double amplitude,
      required double frequency,
      required double phase,
      required Color color,
    }) {
      final path = Path();
      final midY = size.height / 2;
      for (double x = 0; x <= size.width; x += 2) {
        final normalizedX = x / size.width;
        final y = midY +
            amplitude *
                math.sin(
                  (normalizedX * frequency * 2 * math.pi) +
                      phase +
                      (progress * 2 * math.pi),
                ) *
                _envelope(normalizedX);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, basePaint..color = color);
    }

    drawLine(
      amplitude: size.height * 0.28,
      frequency: 1.6,
      phase: 0,
      color: _AppPalette.cyan.withOpacity(0.55),
    );
    drawLine(
      amplitude: size.height * 0.16,
      frequency: 2.3,
      phase: math.pi / 3,
      color: _AppPalette.iceBlue.withOpacity(0.30),
    );
  }

  // Fades the wave out toward both edges so it reads as a soft signal
  // rather than a hard-edged strip.
  double _envelope(double normalizedX) {
    return math.sin(normalizedX * math.pi).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _NeuralWavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Shared design tokens for the Splash + Login screens.
///
/// Kept private to each file for now so nothing outside the two screens
/// you asked me to touch gets modified. If you'd like, this can be
/// extracted into a single `lib/core/theme/app_palette.dart` and imported
/// by both — happy to do that as a small separate follow-up.
class _AppPalette {
  static const Color navyDeep = Color(0xFF0A1628);
  static const Color navyMid = Color(0xFF122A44);
  static const Color cyan = Color(0xFF4FD8E8);
  static const Color teal = Color(0xFF2EC4B6);
  static const Color iceBlue = Color(0xFFBFE3F0);
  static const Color textPrimary = Color(0xFFF3F7FB);
  static const Color textSecondary = Color(0xFF8FA6BF);
}
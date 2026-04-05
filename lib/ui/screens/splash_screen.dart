import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import '../../neomage_routes.dart';
import 'package:neomage/data/auth/auth_service.dart';
import '../../utils/constants/neomage_assets.dart';
import '../../utils/constants/neomage_translation_constants.dart';
import '../controllers/chat_controller.dart';

/// Animated splash screen — 5-second intro with logo entrance, light particles,
/// tagline sequence, then auto-navigate to onboarding or chat.
///
/// Based on the Itzli splash pattern: master timeline drives phased animations,
/// particle system via CustomPainter, ambient glow pulse, expanding light rings.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _masterController;
  late AnimationController _particleController;
  late AnimationController _glowPulseController;

  // Phase animations derived from master (0→1 over 5 seconds)
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _lightBurst;
  late Animation<double> _tagline1Opacity;
  late Animation<double> _tagline2Opacity;
  late Animation<double> _tagline3Opacity;
  late Animation<double> _exitFade;

  bool _navigated = false;

  // Particle system
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();

    // Master timeline: 5 seconds
    _masterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );

    // Continuous particle animation
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // Glow pulse
    _glowPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    // ── Phase animations ──
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.35, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
      ),
    );
    _lightBurst = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.20, 0.50, curve: Curves.easeOut),
      ),
    );
    _tagline1Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.30, 0.45, curve: Curves.easeIn),
      ),
    );
    _tagline2Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.45, 0.60, curve: Curves.easeIn),
      ),
    );
    _tagline3Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.60, 0.75, curve: Curves.easeIn),
      ),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.85, 1.0, curve: Curves.easeIn),
      ),
    );

    // Generate particles
    final rng = math.Random(42);
    _particles = List.generate(
      24,
      (i) => _Particle(
        angle: rng.nextDouble() * 2 * math.pi,
        speed: 0.3 + rng.nextDouble() * 0.7,
        size: 1.5 + rng.nextDouble() * 3.0,
        delay: rng.nextDouble() * 0.4,
      ),
    );

    // Start animation and navigate when done
    _masterController.forward();
    _masterController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_navigated) {
        _navigate();
      }
    });
  }

  @override
  void dispose() {
    _masterController.dispose();
    _particleController.dispose();
    _glowPulseController.dispose();
    super.dispose();
  }

  /// Determine destination and navigate.
  Future<void> _navigate() async {
    if (_navigated) return;
    _navigated = true;

    final authService = Sint.find<AuthService>();
    final onboardingDone = await authService.isOnboardingComplete();

    if (!mounted) return;

    if (!onboardingDone) {
      Sint.offAllNamed(NeomageRouteConstants.onboarding);
      return;
    }

    final hasConfig = await authService.hasValidConfig();
    if (!mounted) return;

    if (hasConfig) {
      final chat = Sint.find<ChatController>();
      final initialized = await chat.initialize();
      if (mounted) {
        Sint.offAllNamed(
          initialized
              ? NeomageRouteConstants.chat
              : NeomageRouteConstants.onboarding,
        );
      }
    } else {
      Sint.offAllNamed(NeomageRouteConstants.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Neomage accent: purple/amber based on theme
    const accentDark = Color(0xFFD97706); // Amber
    const accentLight = Color(0xFF6C3FC5); // Purple
    final accent = isDark ? accentDark : accentLight;
    final bgColor = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF8F6F4);

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        // Tap to skip animation
        onTap: () {
          if (!_navigated) _navigate();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _masterController,
            _particleController,
            _glowPulseController,
          ]),
          builder: (context, _) {
            final masterVal = _masterController.value;

            return Opacity(
              opacity: _exitFade.value,
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ─── Logo with light burst & particles ───
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Light burst rings (3 expanding circles)
                          if (_lightBurst.value > 0)
                            ...List.generate(3, (i) {
                              final ringProgress =
                                  (_lightBurst.value - i * 0.1).clamp(0.0, 1.0);
                              final ringRadius =
                                  50 + ringProgress * 80 * (1 + i * 0.3);
                              final ringAlpha = (1.0 - ringProgress) * 0.15;
                              return Container(
                                width: ringRadius * 2,
                                height: ringRadius * 2,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color:
                                        accent.withValues(alpha: ringAlpha),
                                    width: 1.5 - i * 0.3,
                                  ),
                                ),
                              );
                            }),

                          // Ambient glow
                          Container(
                            width: 140 + _glowPulseController.value * 20,
                            height: 140 + _glowPulseController.value * 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(
                                    alpha: 0.18 * _logoOpacity.value,
                                  ),
                                  blurRadius:
                                      50 + _glowPulseController.value * 25,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),

                          // Floating particles
                          if (masterVal > 0.20)
                            CustomPaint(
                              size: const Size(240, 240),
                              painter: _ParticlePainter(
                                particles: _particles,
                                progress: _lightBurst.value,
                                particlePhase: _particleController.value,
                                color: accent,
                              ),
                            ),

                          // The logo (wizard icon)
                          Transform.scale(
                            scale: _logoScale.value,
                            child: Opacity(
                              opacity: _logoOpacity.value,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Image.asset(
                                  NeomageAssets.icon,
                                  package: 'neomage',
                                  width: 110,
                                  height: 110,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ─── NEOMAGE title ───
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Text(
                        NeomageTranslationConstants.appTitle.tr.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ─── Tagline sequence ───
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TaglineText(
                            opacity: _tagline1Opacity.value,
                            text: NeomageTranslationConstants
                                .appSubtitleDesktop.tr,
                            style: TextStyle(
                              color: (isDark ? Colors.white : Colors.black87)
                                  .withValues(alpha: 0.8),
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _TaglineText(
                            opacity: _tagline2Opacity.value,
                            text: NeomageTranslationConstants
                                .splashTagline2.tr,
                            style: TextStyle(
                              color: (isDark ? Colors.white : Colors.black87)
                                  .withValues(alpha: 0.55),
                              fontSize: 13,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _TaglineText(
                            opacity: _tagline3Opacity.value,
                            text: NeomageTranslationConstants
                                .splashTagline3.tr,
                            style: TextStyle(
                              color: accent.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ─── Tap to skip hint ───
                    if (masterVal > 0.50)
                      Opacity(
                        opacity:
                            ((masterVal - 0.50) / 0.15).clamp(0.0, 0.5),
                        child: Text(
                          'Tap to continue',
                          style: TextStyle(
                            color: (isDark ? Colors.white : Colors.black54)
                                .withValues(alpha: 0.35),
                            fontSize: 11,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                  ],
                ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Tagline with opacity + slide-up ───

class _TaglineText extends StatelessWidget {
  final double opacity;
  final String text;
  final TextStyle style;

  const _TaglineText({
    required this.opacity,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, (1 - opacity) * 10),
        child: Text(text, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}

// ─── Particle System ───

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final double delay;

  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.delay,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final double particlePhase;
  final Color color;

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.particlePhase,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();

    for (final p in particles) {
      final t = (progress - p.delay).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final dist = 30 + t * p.speed * 70;
      final wobble =
          math.sin(particlePhase * 2 * math.pi + p.angle * 3) * 4;
      final x = center.dx + math.cos(p.angle) * dist + wobble;
      final y = center.dy + math.sin(p.angle) * dist + wobble * 0.5;
      final alpha = (t < 0.3 ? t / 0.3 : 1.0 - (t - 0.3) / 0.7) * 0.6;

      paint.color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), p.size * t, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.progress != progress || old.particlePhase != particlePhase;
}

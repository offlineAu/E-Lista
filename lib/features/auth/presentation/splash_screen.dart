import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/app_logo.dart';
import '../../../widgets/state_views.dart';
import '../application/auth_controller.dart';
import 'widgets/role_splash_scene.dart';

/// The first screen, shown while the app works out who is using it.
///
/// It does one thing: make sure a session exists. Someone opening the app for the first
/// time is signed in anonymously here, which is what lets them go straight to the shelves
/// without a decision about accounts. The router moves them on as soon as the session
/// lands.
///
/// If sign-in fails — no signal, Firebase unreachable — this screen says so and offers
/// Retry rather than spinning forever.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the brand mark is on screen before any network work.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
  }

  Future<void> _startSession() async {
    await ref.read(authControllerProvider.notifier).ensureSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signIn = ref.watch(authControllerProvider);
    final session = ref.watch(authSessionProvider);
    final currentSession = ref.watch(currentSessionProvider);

    final failure = signIn.error ?? session.error;
    final hasFailed = signIn.hasError || session.hasError;

    // Nothing to show until the role claim resolves — before that this stays a neutral
    // shimmer, same brand mark for everyone.
    final scene = switch (currentSession) {
      null => null,
      final s when s.isOwner => SplashScene.owner,
      final s when s.isCashier => SplashScene.cashier,
      _ => SplashScene.customer,
    };

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.light
          ? AppColors.blush
          : AppColors.darkBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppLogo(size: 96),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: scene == null
                      ? const SizedBox(key: ValueKey('no-tag'), height: 24)
                      : Padding(
                          key: ValueKey('tag-${scene.name}'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _RoleTagPill(scene: scene),
                        ),
                ),
                _Wordmark(
                  text: 'E-Lista',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  scene?.tagline ?? 'Your store, organized',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (hasFailed && failure != null)
                  ErrorView.from(
                    failure,
                    signIn.stackTrace ?? session.stackTrace,
                    onRetry: _startSession,
                    compact: true,
                  )
                else ...[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: scene == null
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : RoleSplashScene(key: ValueKey(scene), scene: scene),
                  ),
                  const SizedBox(height: 20),
                  _ShimmerProgressBar(
                    colors: scene?.barColors ?? const [
                      AppColors.primaryRose,
                      AppColors.tertiaryPink,
                      AppColors.accentViolet,
                    ],
                    trackColor: scene?.barTrackColor ?? AppColors.outline,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small uppercase pill naming the role once it's known — "OWNER", "CASHIER",
/// "CUSTOMER" — the same cue the concept canvas shows above each role's icon.
class _RoleTagPill extends StatelessWidget {
  const _RoleTagPill({required this.scene});

  final SplashScene scene;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: scene.tagBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        scene.roleLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scene.tagForeground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// "E-Lista" fading and sliding in one letter at a time, played once on mount rather than
/// looping — this splash shows once per app launch, not on repeat like the design review.
class _Wordmark extends StatefulWidget {
  const _Wordmark({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_Wordmark> createState() => _WordmarkState();
}

class _WordmarkState extends State<_Wordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _letterDelay = 0.07;
  static const _letterDuration = 0.4;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: 300 + (widget.text.length * _letterDelay * 1000).round(),
      ),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _letterProgress(int index) {
    final start = index * _letterDelay;
    final end = (start + _letterDuration).clamp(0.0, 1.0);
    final value = _controller.value;
    if (value <= start) return 0;
    if (value >= end) return 1;
    return (value - start) / (end - start);
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.text.split('');
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < letters.length; i++)
              _AnimatedLetter(
                letter: letters[i],
                style: widget.style,
                progress: _letterProgress(i),
              ),
          ],
        );
      },
    );
  }
}

class _AnimatedLetter extends StatelessWidget {
  const _AnimatedLetter({
    required this.letter,
    required this.style,
    required this.progress,
  });

  final String letter;
  final TextStyle? style;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOut.transform(progress);
    return Opacity(
      opacity: eased,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - eased)),
        child: Text(letter, style: style),
      ),
    );
  }
}

/// A pill-shaped track with a small gradient bar shimmering inside it — the persistent
/// "still working on it" cue that stays visible for the whole splash, not just before the
/// role resolves.
class _ShimmerProgressBar extends StatefulWidget {
  const _ShimmerProgressBar({required this.colors, required this.trackColor});

  final List<Color> colors;
  final Color trackColor;

  @override
  State<_ShimmerProgressBar> createState() => _ShimmerProgressBarState();
}

class _ShimmerProgressBarState extends State<_ShimmerProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 6,
      decoration: BoxDecoration(
        color: widget.trackColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.4,
          heightFactor: 1,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    begin: Alignment(-2 + t * 4, 0),
                    end: Alignment(-1 + t * 4, 0),
                    colors: [...widget.colors, widget.colors.first],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemePrefKey = 'medcare_is_dark';

class _CircleRevealClipper extends CustomClipper<Path> {
  _CircleRevealClipper({required this.center, required this.radius});
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleRevealClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.center != center;
}

/// The Telegram-style "iris wipe" theme switch. Wraps a themed builder;
/// call `revealKey.currentState?.reveal(globalPosition)` from wherever
/// your theme-toggle button lives.
///
/// DIRECTIONAL BEHAVIOR: switching TO dark and switching BACK to light
/// are visually opposite, not mirror-identical animations of the same
/// "grow a circle" motion:
///   - Light → Dark: the NEW (dark) theme grows as an expanding circle
///     from the tap point, over the OLD (light) theme underneath.
///   - Dark → Light: the NEW (light) theme is committed as the base
///     IMMEDIATELY, and the OLD (dark) theme instead shrinks away as a
///     contracting circle, revealing the light base underneath as it
///     recedes. This is the true reverse of the expand — without this
///     branch, both directions look identical (always "spread out"),
///     which is the bug this fixes.
///
/// Persists the chosen theme to disk (SharedPreferences) so it survives
/// an app restart — `isDark` passed in is only the fallback used before
/// the saved value has loaded (or if this is the first-ever launch).
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({super.key, required this.isDark, required this.builder});
  final bool isDark;
  final Widget Function(BuildContext, bool isDark) builder;

  @override
  State<ThemeReveal> createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal> with SingleTickerProviderStateMixin {
  late bool _isDark = widget.isDark;
  Offset? _origin;
  double _maxRadius = 0;


  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _radius = CurvedAnimation(
    parent: _controller,
    // easeOutCubic: fast start, gentle settle — reads smoother than a
    // symmetric ease-in-out for an expanding/contracting circle like
    // this. Applies to both forward (grow) and reverse (shrink) since
    // no separate reverseCurve is set — Flutter runs the same curve
    // shape whichever direction the controller is moving.
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kThemePrefKey);
    if (saved != null && saved != _isDark && mounted) {
      setState(() => _isDark = saved);
    }
  }

  Future<void> _persistTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kThemePrefKey, isDark);
  }

  /// Call with the tap's *global* position (e.g. from a button's
  /// RenderBox center, or a GestureDetector's onTapUp details).
  void reveal(Offset globalPosition) {
    if (_controller.isAnimating) return;
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final size = box.size;
    final dx = math.max(local.dx, size.width - local.dx);
    final dy = math.max(local.dy, size.height - local.dy);
    final maxRadius = math.sqrt(dx * dx + dy * dy);

    final goingDark = !_isDark;

    if (goingDark) {
      // Light → Dark: unchanged from before — overlay is the NEW
      // (dark) theme, growing from 0 up to maxRadius over the OLD
      // (light) base underneath. The theme is only committed once the
      // animation finishes.
      setState(() {
        _origin = local;
        _maxRadius = maxRadius;
      });
      _controller.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _isDark = true; // commit the theme once the wipe finishes
          _controller.value = 0;
          _origin = null;
        });
        _persistTheme(true);
      });
    } else {
      // Dark → Light: commit the NEW (light) theme as the base RIGHT
      // NOW — no waiting for the animation — then animate the OLD
      // (dark) theme shrinking away on top of it. As the circle
      // contracts, more of the already-light base is revealed
      // underneath, which reads as the exact reverse of the expand
      // case above rather than another "spread out."
      setState(() {
        _origin = local;
        _maxRadius = maxRadius;
        _isDark = false; // base swaps to light immediately
      });
      _controller.reverse(from: 1).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _controller.value = 0;
          _origin = null;
        });
        _persistTheme(false);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_origin == null) {
      return widget.builder(context, _isDark);
    }

    // Forward (growing) case: base is the OLD theme (still !_isDark's
    // opposite committed value — i.e. _isDark hasn't flipped yet), and
    // the overlay is the NEW theme, clipped by a circle that grows
    // with the animation.
    //
    // Reverse (shrinking) case: _isDark was ALREADY flipped to the new
    // value the instant the gesture started (see reveal() above), so
    // widget.builder(context, _isDark) here is already the NEW (light)
    // theme — that's the base. The overlay is the OLD (dark) theme,
    // clipped by a circle that shrinks with the animation, revealing
    // more of the light base as it recedes.
    final base = widget.builder(context, _isDark);
    // In BOTH cases this correctly resolves to the theme that should
    // be the shrinking/growing overlay:
    //   - Forward (growing): _isDark hasn't flipped yet, so !_isDark
    //     is the NEW theme — correct, that's what should grow in.
    //   - Reverse (shrinking): _isDark was ALREADY flipped to the new
    //     value the instant the gesture started (see reveal() above),
    //     so !_isDark now resolves to the OLD theme — correct, that's
    //     what should shrink away.
    final overlayIsDark = !_isDark;

    return Stack(children: [
      base,
      AnimatedBuilder(
        animation: _radius,
        builder: (context, child) => ClipPath(
          clipper: _CircleRevealClipper(center: _origin!, radius: _radius.value * _maxRadius),
          child: child,
        ),
        // RepaintBoundary — the clip re-paints every animation tick,
        // but without this the whole overlay subtree (the entire
        // themed app: header, tab bar, PageView, etc.) can get pulled
        // into that same repaint, which is what actually reads as
        // janky/not-smooth on a heavier screen. This isolates the
        // clip's repaint cost from everything else.
        child: RepaintBoundary(
          child: IgnorePointer(child: widget.builder(context, overlayIsDark)),
        ),
      ),
    ]);
  }
}
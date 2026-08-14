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
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _radius = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
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
    setState(() {
      _origin = local;
      _maxRadius = math.sqrt(dx * dx + dy * dy);
    });
    _controller.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      final next = !_isDark;
      setState(() {
        _isDark = next; // commit the theme once the wipe finishes
        _controller.value = 0;
        _origin = null;
      });
      _persistTheme(next);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.builder(context, _isDark);
    if (_origin == null) return base;

    return Stack(children: [
      base,
      AnimatedBuilder(
        animation: _radius,
        builder: (context, child) => ClipPath(
          clipper: _CircleRevealClipper(center: _origin!, radius: _radius.value * _maxRadius),
          child: child,
        ),
        child: IgnorePointer(child: widget.builder(context, !_isDark)),
      ),
    ]);
  }
}
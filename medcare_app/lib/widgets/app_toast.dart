import 'dart:async';
import 'package:flutter/material.dart';

OverlayEntry? _currentToastEntry;

/// Floating, auto-dismissing pill-style toast — near-opaque, tinted by
/// state (success/error), subtle scale + fade entrance, soft shadow,
/// and a circular icon badge. Shows for [duration] (default 1.6s) then
/// disappears on its own; no user action needed to dismiss.
///
/// Note: uses a near-opaque tint rather than a real BackdropFilter blur
/// — animating blur alongside opacity/scale triggers a known Flutter
/// compositor flicker bug where content behind the toast can momentarily
/// vanish. This keeps the toast solid enough to hide screen content
/// underneath without that issue.
///
/// Usage:
///   showAppToast(context, 'Account created successfully!');
///   showAppToast(context, 'Please enter a valid email.', isError: true);
void showAppToast(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  // Remove any toast already showing so they don't queue up and overlap
  // in a stacked flow (e.g. an error toast immediately followed by a
  // success toast).
  _currentToastEntry?.remove();
  _currentToastEntry = null;

  final overlay = Overlay.of(context, rootOverlay: true);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastWidget(
      message: message,
      isError: isError,
      duration: duration,
      onDismissed: () {
        entry.remove();
        if (identical(_currentToastEntry, entry)) {
          _currentToastEntry = null;
        }
      },
    ),
  );

  _currentToastEntry = entry;
  overlay.insert(entry);
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    required this.isError,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final bool isError;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  static const _fadeDuration = Duration(milliseconds: 560);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _fadeDuration);

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  // Entrance overshoots slightly past 1.0 then settles — gives a soft
  // "pop" instead of a flat fade. Reverse (exit) just eases back down.
  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeIn,
  ).drive(Tween(begin: 0.85, end: 1.0));

  @override
  void initState() {
    super.initState();
    _controller.forward();

    final holdTime = widget.duration - _fadeDuration;
    Future.delayed(holdTime.isNegative ? Duration.zero : holdTime, () {
      if (!mounted) return;
      _controller.reverse().whenComplete(widget.onDismissed);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.isError ? const Color(0xFFE0453A) : const Color(0xFF1FA35A);

    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).viewInsets.bottom +
          MediaQuery.of(context).padding.bottom +
          32,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.82,
                  ),
                  padding: const EdgeInsets.only(
                    left: 8,
                    right: 8,
                    top: 4,
                    bottom: 4,
                  ),
                  decoration: BoxDecoration(
                    // Mostly-opaque white blended with a touch of the
                    // accent color — hides screen content underneath
                    // while still reading as tinted glass, without a
                    // live BackdropFilter (which caused the flicker).
                    color: Color.alphaBlend(
                      accent.withOpacity(0.14),
                      Colors.white,
                    ).withOpacity(0.96),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: accent.withOpacity(0.28),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isError
                              ? Icons.close_rounded
                              : Icons.check_rounded,
                          color: accent,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF1C1C1E),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            decoration: TextDecoration.none,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
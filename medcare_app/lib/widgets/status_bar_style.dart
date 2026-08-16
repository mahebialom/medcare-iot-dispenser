import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps [child] with a transparent, edge-to-edge status bar whose
/// icon color matches the screen's own background — white icons for
/// dark/gradient backgrounds, dark icons for light ones. Uses
/// AnnotatedRegion, which is Flutter's own mechanism for this: it
/// automatically restores the previous screen's status bar style when
/// navigating back, so it's the correct tool here, not a workaround.
class StatusBarStyle extends StatelessWidget {
  const StatusBarStyle({super.key, required this.brightness, required this.child});

  /// Brightness of the CONTENT behind the status bar — Brightness.dark
  /// for a dark/gradient header (→ white icons), Brightness.light for
  /// a light page background (→ dark icons).
  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent) // white icons
        : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent); // dark icons

    return AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: child);
  }
}
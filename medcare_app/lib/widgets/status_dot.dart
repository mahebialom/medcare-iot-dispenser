import 'package:flutter/material.dart';

/// Small glowing green/red dot for the Wi-Fi indicator.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.on, required this.onColor, required this.offColor});
  final bool on;
  final Color onColor;
  final Color offColor;

  @override
  Widget build(BuildContext context) {
    final color = on ? onColor : offColor;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 5, spreadRadius: 1)],
      ),
    );
  }
}

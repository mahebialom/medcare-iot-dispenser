import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/slot.dart';

Color hexToColor(String hex, [double opacity = 1]) {
  final v = int.parse(hex.replaceFirst('#', ''), radix: 16);
  return Color(0xFF000000 | v).withOpacity(opacity);
}

/// Draws the 5-compartment circular tray. Wedges stay in FIXED screen
/// positions — a sweeping pointer arm animates around the ring instead
/// to show the drum's rotational motion, plus a spinning dashed ring
/// while a rotation is in progress. This mirrors the real mechanism:
/// the drum rotates to bring a compartment under a fixed window: the
/// wedges here represent that fixed layout, the pointer is the moving
/// part.
class TrayPainter extends CustomPainter {
  TrayPainter({
    required this.slots,
    required this.activeSlot,
    required this.pointerAngle,
    required this.isRotating,
    required this.borderColor,
    required this.primaryColor,
    required this.textColor,
    required this.mutedColor,
  });

  final List<Slot> slots;
  final int activeSlot;
  final double pointerAngle; // radians, absolute — may exceed 2π mid-sweep
  final bool isRotating;
  final Color borderColor;
  final Color primaryColor;
  final Color textColor;
  final Color mutedColor;

  static const outerR = 95.0;
  static const innerR = 30.0;
  static const pointerR = 110.0;

  /// Tray-only accent palette — deliberately separate from
  /// slot.colorHex (which stays the original muted set used by
  /// Dashboard/Schedule). The compartment color here is purely a
  /// positional/visual accent for the physical drum, not tied to
  /// whatever color a medicine happens to be assigned elsewhere.
  static const trayColors = ['#10B981', '#3B82F6', '#F59E0B', '#8B5CF6', '#94A3B8'];

  /// Public so other Tray-tab widgets (e.g. the slot grid below the
  /// dial) can reuse the exact same per-slot color.
  static Color colorFor(int i, [double opacity = 1]) =>
      hexToColor(trayColors[i % trayColors.length], opacity);

  /// The angle (radians) at the center of a given slot's wedge — the
  /// same -90°-start, 72°-per-slot layout the app has used throughout.
  static double slotCenterAngle(int slot) => (slot * 72 + 36 - 90) * math.pi / 180;

  /// Builds the wedge path for slot [i]. Factored out so fills and
  /// strokes can be drawn in separate passes without rebuilding paths
  /// inline twice.
  Path _wedgePath(Offset center, int i) {
    final start = (i * 72 - 90) * math.pi / 180;
    const sweep = 72 * math.pi / 180;
    return Path()
      ..moveTo(center.dx + innerR * math.cos(start), center.dy + innerR * math.sin(start))
      ..lineTo(center.dx + outerR * math.cos(start), center.dy + outerR * math.sin(start))
      ..arcTo(Rect.fromCircle(center: center, radius: outerR), start, sweep, false)
      ..lineTo(center.dx + innerR * math.cos(start + sweep), center.dy + innerR * math.sin(start + sweep))
      ..arcTo(Rect.fromCircle(center: center, radius: innerR), start + sweep, -sweep, false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Pass 1: fills for ALL wedges first. Drawing fill+stroke per-wedge
    // in a single loop let a later wedge's fill paint over an earlier
    // wedge's stroke on their shared edge (painter's algorithm — later
    // draws win). Separating fills into their own first pass means no
    // fill can ever land on top of any stroke, regardless of order.
    for (var i = 0; i < slots.length; i++) {
      final path = _wedgePath(center, i);
      final fill = Paint()
        ..color = colorFor(i, i == activeSlot ? 0.4 : 0.22)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fill);
    }

    // Pass 2: strokes for all wedges, with the active slot's stroke
    // drawn LAST so it also sits on top of neighboring inactive
    // strokes at the shared edges (keeps the active border fully
    // visible and unclipped on both sides).
    final strokeOrder = [
      for (var i = 0; i < slots.length; i++)
        if (i != activeSlot) i,
      activeSlot,
    ];
    for (final i in strokeOrder) {
      final path = _wedgePath(center, i);
      final isActive = i == activeSlot;
      final stroke = Paint()
        ..color = isActive ? colorFor(i) : borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 2.5 : 1.5;
      canvas.drawPath(path, stroke);
    }

    // Pass 3: labels — placed at each wedge's mid-angle/mid-radius,
    // drawn upright (not rotated to the wedge angle) so they stay
    // readable. Drawn after all fills/strokes so nothing overlaps them.
    for (var i = 0; i < slots.length; i++) {
      final midAngle = (i * 72 + 36 - 90) * math.pi / 180;
      const labelR = (innerR + outerR) / 2;
      final lx = center.dx + labelR * math.cos(midAngle);
      final ly = center.dy + labelR * math.sin(midAngle);
      final labelColor = slots[i].enabled ? textColor : mutedColor;

      final slotLabel = TextPainter(
        text: TextSpan(
          text: 'Slot ${i + 1}',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      slotLabel.paint(canvas, Offset(lx - slotLabel.width / 2, ly - 13));

      final rawName = slots[i].medicineName;
      final shortName = rawName.length > 10 ? '${rawName.substring(0, 9)}…' : rawName;
      final nameLabel = TextPainter(
        text: TextSpan(
          text: shortName,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: colorFor(i)),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 60);
      nameLabel.paint(canvas, Offset(lx - nameLabel.width / 2, ly + 1));
    }

    // Spinning dashed ring while a rotation is in progress — a general
    // "the device is moving" cue, independent of exact position.
    if (isRotating) {
      final dashPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      const dashCount = 10;
      for (var i = 0; i < dashCount; i++) {
        final a0 = pointerAngle * 2 + i * (2 * math.pi / dashCount);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: outerR + 9),
          a0,
          (2 * math.pi / dashCount) * 0.55,
          false,
          dashPaint,
        );
      }
    }

    // Pointer arm — sweeps around to show exactly which slot the drum
    // is rotating toward / currently aligned with.
    final normalized = pointerAngle % (2 * math.pi);
    final tip = Offset(
      center.dx + pointerR * math.cos(normalized),
      center.dy + pointerR * math.sin(normalized),
    );
    final baseA = Offset(
      center.dx + (pointerR - 10) * math.cos(normalized - 0.11),
      center.dy + (pointerR - 10) * math.sin(normalized - 0.11),
    );
    final baseB = Offset(
      center.dx + (pointerR - 10) * math.cos(normalized + 0.11),
      center.dy + (pointerR - 10) * math.sin(normalized + 0.11),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(baseA.dx, baseA.dy)
        ..lineTo(baseB.dx, baseB.dy)
        ..close(),
      Paint()..color = primaryColor,
    );

    // Center hub
    canvas.drawCircle(center, 28, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      28,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final tp = TextPainter(
      text: TextSpan(text: 'MOTOR', style: TextStyle(color: primaryColor, fontSize: 8.5, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant TrayPainter old) =>
      old.activeSlot != activeSlot ||
      old.slots != slots ||
      old.borderColor != borderColor ||
      old.pointerAngle != pointerAngle ||
      old.isRotating != isRotating ||
      old.textColor != textColor ||
      old.mutedColor != mutedColor;
}

/// Given a tap position local to the painted CustomPaint box, returns
/// which of the 5 compartments (if any) was tapped.
int? slotAtPosition(Offset local, Size size) {
  final center = Offset(size.width / 2, size.height / 2);
  final d = local - center;
  final dist = d.distance;
  if (dist < TrayPainter.innerR || dist > TrayPainter.outerR) return null;
  var angleDeg = math.atan2(d.dy, d.dx) * 180 / math.pi + 90;
  if (angleDeg < 0) angleDeg += 360;
  return (angleDeg / 72).floor() % 5;
}
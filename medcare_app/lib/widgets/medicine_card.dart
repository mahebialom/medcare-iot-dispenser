import 'package:flutter/material.dart';
import '../models/slot.dart';
import '../theme/app_colors.dart';
import 'tray_painter.dart' show hexToColor;

class MedicineCard extends StatelessWidget {
  const MedicineCard({super.key, required this.slot, required this.c, required this.lowStockThreshold, this.onTap});
  final Slot slot;
  final AppColors c;
  final int lowStockThreshold;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = hexToColor(slot.colorHex);
    final low = slot.quantity <= lowStockThreshold;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(slot.medicineName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: c.ink)),
                const SizedBox(height: 2),
                Text('${slot.dose} · Slot ${slot.index + 1}',
                    style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: low ? c.amberBg : c.greenBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                low ? '⚠ ${slot.quantity} left' : '${slot.quantity} tablets',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: low ? c.amber : c.green),
              ),
            ),
          ]),
          if (slot.schedules.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: slot.schedules.map((s) {
                final taken = s.takenToday;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: taken ? c.greenBg : c.redBg,
                    border: Border.all(color: taken ? c.greenBorder : c.redBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${taken ? "✅" : "⏳"} ${s.label}',
                      style: TextStyle(fontSize: 12, color: c.text2)),
                );
              }).toList(),
            ),
          ],
        ]),
      ),
    );
  }
}

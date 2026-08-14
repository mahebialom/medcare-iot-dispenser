import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/tray_painter.dart' show hexToColor;
import 'slot_editor_screen.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key, required this.c});
  final AppColors c;

  static const _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.editingSlotIndex != null) {
      return SlotEditorScreen(c: c, slot: app.slots[app.editingSlotIndex!]);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('WEEKLY SCHEDULE',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 10),
        for (final slot in app.slots)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(left: BorderSide(color: hexToColor(slot.colorHex), width: 4)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${slot.medicineName} · ${slot.dose}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: hexToColor(slot.colorHex), fontSize: 14)),
                    Text('Slot ${slot.index + 1}${slot.enabled ? "" : " · Disabled"}',
                        style: TextStyle(fontSize: 10, color: c.muted)),
                  ]),
                ),
                TextButton(
                  onPressed: () => app.openSlotEditor(slot.index),
                  child: const Text('Edit'),
                ),
              ]),
              if (slot.schedules.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: slot.schedules
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.cardBg,
                                border: Border.all(color: c.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(s.label, style: TextStyle(fontSize: 12, color: c.text2)),
                            ))
                        .toList(),
                  ),
                ),
              if (slot.enabled)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: _weekDays.map((d) {
                      final weekend = d == 'Sat' || d == 'Sun';
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: weekend ? c.weekendBg : hexToColor(slot.colorHex),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: weekend ? c.weekendText : Colors.white,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ]),
          ),
      ],
    );
  }
}

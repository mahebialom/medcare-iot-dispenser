import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/medicine_card.dart';
import '../widgets/status_dot.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final enabledSlots = app.slots.where((s) => s.enabled).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("TODAY'S MEDICINES",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 10),
        for (final slot in enabledSlots)
          MedicineCard(slot: slot, c: c, lowStockThreshold: app.settings.lowStock),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: c.deviceGrad,
            border: Border.all(color: c.deviceBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('📡 Device Status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c.deviceHeading)),
            const SizedBox(height: 10),
            Row(children: [
              Text('Wi-Fi: ', style: TextStyle(color: c.muted, fontSize: 12)),
              StatusDot(on: app.status.online, onColor: c.green, offColor: c.red),
              const SizedBox(width: 6),
              Text(app.status.online ? 'Connected' : 'Offline',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.text2, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            Text('Tray: ⟳ Slot ${app.status.currentSlot + 1}',
                style: TextStyle(color: c.text2, fontSize: 12)),
            const SizedBox(height: 6),
            Text('Mode: ${app.status.mode.toUpperCase()}', style: TextStyle(fontWeight: FontWeight.w600, color: c.text2, fontSize: 12)),
            const SizedBox(height: 6),
            Text('Last sync: ${app.status.lastSeen}', style: TextStyle(color: c.text2, fontSize: 12)),
          ]),
        ),
      ],
    );
  }
}

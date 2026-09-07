import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/slot.dart';
import '../models/schedule_entry.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

class SlotEditorScreen extends StatefulWidget {
  const SlotEditorScreen({super.key, required this.c, required this.slot});
  final AppColors c;
  final Slot slot;

  @override
  State<SlotEditorScreen> createState() => _SlotEditorScreenState();
}

class _SlotEditorScreenState extends State<SlotEditorScreen> {
  late final _name = TextEditingController(text: widget.slot.medicineName);
  late final _dose = TextEditingController(text: widget.slot.dose);
  late final _qty = TextEditingController(text: widget.slot.quantity.toString());
  late bool _enabled = widget.slot.enabled;
  late List<ScheduleEntry> _schedules = List.of(widget.slot.schedules);

  static const _periodLabels = ['🌅 Morning', '🍽️ Lunch', '🌙 Night', '⏰ Exact time'];

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _addSchedule() {
    if (_schedules.length >= 3) return; // matches MAX_SCHEDULES_PER_SLOT on the device
    setState(() => _schedules = [..._schedules, const ScheduleEntry(period: 0)]);
  }

  void _removeSchedule(int i) => setState(() => _schedules = List.of(_schedules)..removeAt(i));

  void _setSchedule(int i, ScheduleEntry updated) =>
      setState(() => _schedules = List.of(_schedules)..[i] = updated);

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = context.read<AppState>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('SLOT ${widget.slot.index + 1} CONFIGURATION',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: c.muted)),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Medicine Name')),
        const SizedBox(height: 8),
        TextField(controller: _dose, decoration: const InputDecoration(labelText: 'Dose / Strength')),
        const SizedBox(height: 8),
        TextField(
          controller: _qty,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Tablets Remaining'),
        ),
        const SizedBox(height: 14),
        Text('SCHEDULED TIMES (${_schedules.length}/3)',
            style: TextStyle(fontSize: 9, letterSpacing: 1, color: c.muted)),
        const SizedBox(height: 6),
        for (var i = 0; i < _schedules.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.inputBg,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var p = 0; p < 4; p++)
                    ChoiceChip(
                      label: Text(_periodLabels[p], style: const TextStyle(fontSize: 11)),
                      selected: _schedules[i].period == p,
                      onSelected: (_) => _setSchedule(i, _schedules[i].copyWith(period: p)),
                    ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: c.red),
                    onPressed: () => _removeSchedule(i),
                  ),
                ],
              ),
              if (_schedules[i].period == 3)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _schedules[i].hour.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Hour (0-23)', isDense: true),
                        onChanged: (v) =>
                            _setSchedule(i, _schedules[i].copyWith(hour: int.tryParse(v) ?? 8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: _schedules[i].minute.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Minute (0-59)', isDense: true),
                        onChanged: (v) =>
                            _setSchedule(i, _schedules[i].copyWith(minute: int.tryParse(v) ?? 0)),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        if (_schedules.length < 3)
          OutlinedButton(onPressed: _addSchedule, child: const Text('+ Add scheduled time')),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable Schedule'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton.icon(
            onPressed: () => app.closeSlotEditor(),
            icon: Icon(Icons.close, size: 16, color: c.primary),
            label: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            style: ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(c.primary),
              // Outlined buttons have no solid background to darken
              // like Save's ElevatedButton does — the Material-
              // standard hover feedback here is a light tint over the
              // otherwise-transparent background instead, using the
              // same color the button's own border/text already use.
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered) ? c.primary.withOpacity(0.08) : Colors.transparent,
              ),
              side: WidgetStatePropertyAll(BorderSide(color: c.primary.withOpacity(0.4))),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              final updated = widget.slot.copyWith(
                medicineName: _name.text,
                dose: _dose.text,
                quantity: int.tryParse(_qty.text) ?? widget.slot.quantity,
                enabled: _enabled,
                schedules: _schedules,
              );
              app.saveSlot(updated); // writes ONLY this slot — see AppState.saveSlot
            },
            icon: const Icon(Icons.check, size: 16, color: Colors.white),
            label: const Text('Save → Push to Device',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered) ? c.primary.withOpacity(0.82) : c.primary,
              ),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
              elevation: const WidgetStatePropertyAll(0),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
          ),
        ]),
      ],
    );
  }
}
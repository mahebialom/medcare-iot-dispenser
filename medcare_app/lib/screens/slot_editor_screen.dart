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
        Text('✎ Slot ${widget.slot.index + 1} Configuration',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.ink)),
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
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => app.closeSlotEditor(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.muted,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Save → Push to Device',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}
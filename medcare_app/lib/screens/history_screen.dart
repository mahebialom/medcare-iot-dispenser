import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../models/device_event.dart';
import '../models/slot.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.c});
  final AppColors c;

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${d.day}/${d.month}/${d.year}';
  }

  static String _timeLabel(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${h12.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  // Best-effort ONLY — the firmware's pushEvent() doesn't record which
  // schedule/period a dose belonged to, so this guesses by comparing the
  // event's actual clock hour against that slot's configured schedules'
  // expected time-of-day, picking the closest. If you want this to be
  // exact instead of inferred, the real fix is logging `period` in
  // pushEvent() on the firmware side.
  static String? _inferPeriodLabel(DeviceEvent e, List<Slot> slots) {
    if (e.slot < 0 || e.slot >= slots.length || e.timestamp == null) return null;
    final schedules = slots[e.slot].schedules;
    if (schedules.isEmpty) return null;

    double repHour(int period, int hour, int minute) {
      switch (period) {
        case 0: return 9.0;  // Morning
        case 1: return 13.0; // Lunch
        case 2: return 20.0; // Night
        default: return hour + minute / 60.0; // Exact
      }
    }

    final eventHour = e.timestamp!.hour + e.timestamp!.minute / 60.0;
    String? bestLabel;
    var bestDiff = double.infinity;
    for (final s in schedules) {
      var diff = (repHour(s.period, s.hour, s.minute) - eventHour).abs();
      diff = diff > 12 ? 24 - diff : diff; // wrap around midnight
      if (diff < bestDiff) {
        bestDiff = diff;
        bestLabel = s.label;
      }
    }
    return bestLabel;
  }

  Widget _sectionLabel(String text) => Text(text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // Today's LIVE schedule status — includes items still pending, with
    // their Morning/Lunch/Night/Exact label. An event only exists once
    // something has actually happened (taken or missed), so pending
    // items never show up in the event log below — this section is the
    // only place "still pending, due at Lunch" kind of info lives.
    final scheduleRows = <(String, String, bool)>[];
    for (final slot in app.slots.where((s) => s.enabled)) {
      for (final s in slot.schedules) {
        scheduleRows.add((slot.medicineName, s.label, s.takenToday));
      }
    }

    // Real dispense history from the firmware's /events log — only
    // medicine_taken / medicine_missed, with actual timestamps.
    final doseEvents = app.events.where((e) => e.isDoseEvent && e.timestamp != null).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionLabel("TODAY'S SCHEDULE"),
        const SizedBox(height: 10),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: c.panel, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("Today's adherence", style: TextStyle(fontWeight: FontWeight.w600, color: c.text2)),
              Text('${app.pctToday}%', style: TextStyle(fontWeight: FontWeight.bold, color: c.green)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: app.pctToday / 100,
                minHeight: 8,
                backgroundColor: c.border,
                valueColor: AlwaysStoppedAnimation(c.green),
              ),
            ),
          ]),
        ),
        for (final r in scheduleRows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: c.panel, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration:
                    BoxDecoration(color: r.$3 ? c.greenBg : c.redBg, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(r.$3 ? '✅' : '⏳'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.$1, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.ink)),
                  Text(r.$2, style: TextStyle(fontSize: 11, color: c.muted)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration:
                    BoxDecoration(color: r.$3 ? c.greenBg : c.redBg, borderRadius: BorderRadius.circular(8)),
                child: Text(r.$3 ? 'Taken' : 'Pending',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: r.$3 ? c.green : c.red)),
              ),
            ]),
          ),

        const SizedBox(height: 20),
        _sectionLabel('RECENT ACTIVITY'),
        const SizedBox(height: 10),
        if (doseEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No dispense events logged yet — this fills in once a dose is actually taken or a period ends.',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
        for (final e in doseEvents)
          Builder(builder: (context) {
            final period = _inferPeriodLabel(e, app.slots);
            final subtitle = period == null
                ? '${_dayLabel(e.timestamp!)} · ${_timeLabel(e.timestamp!)}'
                : '${_dayLabel(e.timestamp!)} · ${_timeLabel(e.timestamp!)} · $period';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: c.panel, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: e.isTaken ? c.greenBg : c.redBg, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: Text(e.isTaken ? '✅' : '❌'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.ink)),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: c.muted)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: e.isTaken ? c.greenBg : c.redBg, borderRadius: BorderRadius.circular(8)),
                  child: Text(e.isTaken ? 'Taken' : 'Missed',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: e.isTaken ? c.green : c.red)),
                ),
              ]),
            );
          }),
      ],
    );
  }
}
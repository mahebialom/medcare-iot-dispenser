import 'schedule_entry.dart';

/// Mirrors the firmware's SlotConfig struct / the JSON at
/// /dispensers/{id}/slots/{index}. `index` and `colorHex` are app-side
/// only conveniences and are never written back to Firebase.
class Slot {
  const Slot({
    required this.index,
    required this.medicineName,
    required this.dose,
    required this.quantity,
    required this.enabled,
    required this.schedules,
    required this.colorHex,
  });

  final int index;
  final String medicineName;
  final String dose;
  final int quantity;
  final bool enabled;
  final List<ScheduleEntry> schedules;
  final String colorHex;

  factory Slot.empty(int index, {String color = '#8f97a3'}) => Slot(
        index: index,
        medicineName: index == 4 ? 'Empty' : 'Slot ${index + 1}',
        dose: '—',
        quantity: 0,
        enabled: false,
        schedules: const [],
        colorHex: color,
      );

  factory Slot.fromJson(Map<dynamic, dynamic> j, int index, {String color = '#1a6b4a'}) {
    final rawSchedules = (j['schedules'] as List?) ?? const [];
    return Slot(
      index: index,
      medicineName: (j['medicineName'] as String?) ?? 'Slot ${index + 1}',
      dose: (j['dose'] as String?) ?? '—',
      quantity: (j['quantity'] as num?)?.toInt() ?? 0,
      enabled: j['enabled'] as bool? ?? false,
      schedules: rawSchedules
          .whereType<Map>()
          .map((s) => ScheduleEntry.fromJson(s))
          .toList(),
      colorHex: color,
    );
  }

  /// Only the fields the firmware actually stores — index/colorHex are
  /// app-side and intentionally excluded.
  Map<String, dynamic> toJson() => {
        'medicineName': medicineName,
        'dose': dose,
        'quantity': quantity,
        'enabled': enabled,
        'numSchedules': schedules.length,
        'schedules': schedules.map((s) => s.toJson()).toList(),
      };

  Slot copyWith({
    String? medicineName,
    String? dose,
    int? quantity,
    bool? enabled,
    List<ScheduleEntry>? schedules,
  }) =>
      Slot(
        index: index,
        medicineName: medicineName ?? this.medicineName,
        dose: dose ?? this.dose,
        quantity: quantity ?? this.quantity,
        enabled: enabled ?? this.enabled,
        schedules: schedules ?? this.schedules,
        colorHex: colorHex,
      );
}
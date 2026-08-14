/// Mirrors the firmware's ScheduleEntry struct exactly:
/// period: 0=Morning, 1=Lunch, 2=Night, 3=Exact.
class ScheduleEntry {
  const ScheduleEntry({
    required this.period,
    this.hour = 8,
    this.minute = 0,
    this.takenToday = false,
  });

  final int period;
  final int hour;
  final int minute;
  final bool takenToday;

  static const periodLabels = ['Morning', 'Lunch', 'Night', 'Exact'];
  static const periodIcons = ['🌅', '🍽️', '🌙', '⏰'];

  /// "🌅 Morning" for period-based entries, "⏰ 08:00 AM" for Exact.
  String get label {
    if (period == 3) {
      final h12 = hour % 12 == 0 ? 12 : hour % 12;
      final ampm = hour < 12 ? 'AM' : 'PM';
      return '${periodIcons[3]} ${h12.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')} $ampm';
    }
    final p = period.clamp(0, 2);
    return '${periodIcons[p]} ${periodLabels[p]}';
  }

  factory ScheduleEntry.fromJson(Map<dynamic, dynamic> j) => ScheduleEntry(
        period: (j['period'] as num?)?.toInt() ?? 3,
        hour: (j['hour'] as num?)?.toInt() ?? 8,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        takenToday: j['takenToday'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'period': period,
        'hour': hour,
        'minute': minute,
        'takenToday': takenToday,
      };

  ScheduleEntry copyWith({int? period, int? hour, int? minute, bool? takenToday}) =>
      ScheduleEntry(
        period: period ?? this.period,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        takenToday: takenToday ?? this.takenToday,
      );
}

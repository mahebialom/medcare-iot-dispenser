/// Mirrors one entry from /dispensers/{id}/events, written by the
/// firmware's pushEvent(). Only "medicine_taken" / "medicine_missed"
/// are dose events shown in the History tab — other types
/// (medicine_not_taken nags, refill_mode, stock_*) are logged too but
/// filtered out of the intake list.
class DeviceEvent {
  const DeviceEvent({
    required this.key,
    required this.type,
    required this.slot,
    required this.name,
    required this.status,
    required this.timestamp,
  });

  final String key; // Firebase push key — stable unique id for this event
  final String type;
  final int slot;
  final String name;
  final String status;
  final DateTime? timestamp;

  bool get isTaken => type == 'medicine_taken';
  bool get isMissed => type == 'medicine_missed';
  bool get isDoseEvent => isTaken || isMissed;

  factory DeviceEvent.fromJson(String key, Map<dynamic, dynamic> j) => DeviceEvent(
        key: key,
        type: (j['type'] as String?) ?? '',
        slot: (j['slot'] as num?)?.toInt() ?? -1,
        name: (j['name'] as String?) ?? '—',
        status: (j['status'] as String?) ?? '',
        timestamp: _parseTimestamp(j['timestamp'] as String?),
      );

  // Firmware writes timestamps as "YYYY-MM-DD HH:MM" (see pushEvent()
  // in the firmware — snprintf with %04d-%02d-%02d %02d:%02d).
  static DateTime? _parseTimestamp(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$').firstMatch(raw);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
  }
}
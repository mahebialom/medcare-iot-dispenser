/// Mirrors /dispensers/{id}/status, written by the firmware's
/// pushHeartbeat() every ~2 minutes.
class DeviceStatus {
  const DeviceStatus({
    this.online = false,
    this.lastSeen = '—',
    this.wifiRssi = 0,
    this.currentSlot = 0,
    this.mode = 'idle',
  });

  final bool online;
  final String lastSeen;
  final int wifiRssi;
  final int currentSlot;
  final String mode; // "idle" | "refill" | "active"

  factory DeviceStatus.fromJson(Map<dynamic, dynamic> j) => DeviceStatus(
        online: j['online'] as bool? ?? false,
        lastSeen: (j['lastSeen'] as String?) ?? '—',
        wifiRssi: (j['wifi_rssi'] as num?)?.toInt() ?? 0,
        currentSlot: (j['currentSlot'] as num?)?.toInt() ?? 0,
        mode: (j['mode'] as String?) ?? 'idle',
      );

  /// Parses "yyyy-MM-dd HH:mm" (firmware's format) as a LOCAL DateTime.
  /// Dart's DateTime.parse treats a string with no timezone/offset
  /// suffix as local time, which matches the RTC's local (Dhaka) clock.
  DateTime? get _lastSeenDateTime {
    try {
      return DateTime.parse(lastSeen);
    } catch (_) {
      return null; // covers the '—' placeholder and any malformed value
    }
  }

  /// Heartbeats fire every ~2 min. If more than 5 min (2.5 missed
  /// beats) have passed since the last one, treat it as offline —
  /// regardless of what the (never-updated-to-false) `online` field
  /// still says.
  bool get isActuallyOnline {
    final ts = _lastSeenDateTime;
    if (ts == null) return false;
    return DateTime.now().difference(ts) < const Duration(minutes: 5);
  }

  /// e.g. "2 min ago", "3 h ago", "5 d ago"
  String get _relativeLastSeen {
    final ts = _lastSeenDateTime;
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  /// "2026-08-29 14:32 · 2 min ago" — always keeps the raw timestamp;
  /// only appends the relative part if it could be computed.
  String get lastSeenDisplay {
    final rel = _relativeLastSeen;
    return rel.isEmpty ? lastSeen : '$lastSeen · $rel';
  }
}
/// One entry from /dispensers/{id}/activity_log, written by the APP
/// (see FirebaseService.logActivity) whenever a caregiver performs a
/// meaningful action — manual dispense, refill start/exit, Wi-Fi/stock
/// settings saved, a restart request, or a schedule edit. Parallel to
/// DeviceEvent, which instead covers events the FIRMWARE reports
/// (doses taken/missed, stock alerts).
///
/// Stores `uid` as the authoritative field, plus a `fullNameSnapshot`
/// purely for convenience (see that field's own doc comment for why).
/// For actual in-app DISPLAY, prefer resolving the name against the
/// live `caregivers` list (AppState.caregivers) by `uid` — that
/// reflects a rename; `fullNameSnapshot` never does.
class ActivityLogEntry {
  const ActivityLogEntry({
    required this.key,
    required this.uid,
    this.fullNameSnapshot,
    required this.action,
    this.detail,
    required this.timestamp,
    this.clientTimeLabel,
  });

  final String key; // Firebase push key
  final String uid;
  // The caregiver's displayName AT THE TIME this entry was written —
  // purely a convenience so this entry is readable at a glance in the
  // Firebase console, or if this caregiver's uid is ever missing from
  // /caregivers entirely (shouldn't normally happen — deletion
  // preserves fullName there too — but this is a second, independent
  // copy in case that ever changes). For actual DISPLAY in the app,
  // still prefer joining against the live `caregivers` list by `uid`
  // (see the class doc comment) — that reflects a rename; this field
  // never does. Stored under the Firebase key `user` (renamed from
  // `fullNameSnapshot` for console readability) — the Dart field name
  // is kept as-is so nothing else in the codebase needs touching.
  final String? fullNameSnapshot;
  final String action;
  final String? detail;
  final DateTime? timestamp;
  // Human-readable "YYYY-MM-DD h:mm AM/PM", computed from the WRITING
  // caregiver's own device clock (see FirebaseService.logActivity) —
  // purely so a Firebase console glance shows something readable
  // without needing DevTools or an epoch converter. NEVER use this
  // for sorting, filtering, or anything logic-bearing — `timestamp`
  // above is server-side and immune to a wrong device clock; this
  // isn't. Stored under the Firebase key `time` (renamed from
  // `clientTimeLabel`) — Dart field name kept as-is.
  final String? clientTimeLabel;

  factory ActivityLogEntry.fromJson(String key, Map<dynamic, dynamic> j) =>
      ActivityLogEntry(
        key: key,
        uid: (j['uid'] as String?) ?? '',
        fullNameSnapshot: j['user'] as String?,
        action: (j['action'] as String?) ?? '',
        detail: j['detail'] as String?,
        timestamp: _parseTimestamp(j['timestamp']),
        clientTimeLabel: j['time'] as String?,
      );

  // Written via ServerValue.timestamp (see FirebaseService.logActivity),
  // which comes back as an epoch-milliseconds number — NOT the
  // firmware-formatted "YYYY-MM-DD HH:MM" string DeviceEvent parses.
  // Using the server's clock instead of the caregiver's own device
  // clock is deliberate: a wrong local clock would otherwise misorder
  // or misdate entries that OTHER caregivers rely on to know who did
  // what, and when.
  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is double) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    return null;
  }

  // Human-readable label per action code — kept here (like DeviceEvent's
  // isTaken/isMissed) so every screen that ever displays this log
  // formats it identically, instead of each one reinventing its own
  // switch statement.
  String get label {
    switch (action) {
      case 'manual_dispense':
        return 'Manually dispensed';
      case 'refill_start':
        return 'Started refill mode';
      case 'refill_exit':
        return 'Exited refill mode';
      case 'refill_advance':
        return 'Advanced to next refill slot';
      case 'settings_saved':
        return 'Saved Wi-Fi/stock settings';
      case 'restart_requested':
        return 'Requested a restart';
      case 'schedule_edit':
        return 'Edited a dose schedule';
      case 'quantity_updated':
        return 'Updated stock quantity';
      case 'medicine_renamed':
        return 'Renamed a medicine';
      case 'dose_updated':
        return 'Updated a dose amount';
      case 'slot_enabled':
        return 'Enabled a slot';
      case 'slot_disabled':
        return 'Disabled a slot';
      case 'wifi_credentials_changed':
        return 'Changed Wi-Fi credentials';
      case 'low_stock_threshold_changed':
        return 'Changed low-stock threshold';
      case 'push_notifications_toggled':
        return 'Changed push notifications';
      case 'profile_renamed':
        return 'Changed their name';
      case 'password_changed':
        return 'Changed their password';
      case 'pdf_exported':
        return 'Exported a PDF report';
      default:
        return action;
    }
  }
}
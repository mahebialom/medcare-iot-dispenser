import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/slot.dart';
import '../models/schedule_entry.dart';
import '../models/device_status.dart';
import '../models/device_event.dart';
import '../models/caregiver.dart';
import '../models/activity_log_entry.dart';
import '../models/device_settings.dart';
import '../models/app_notification.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';

/// Single source of truth for the app. Screens read from this via
/// `context.watch<AppState>()` (Provider) and never talk to Firebase
/// directly.
///
/// IMPORTANT: this is created once, at app launch (see main.dart) —
/// BEFORE the user has necessarily signed in. Its Realtime Database
/// reads (watchSlots/watchStatus/watchEvents/watchCaregivers) hit paths
/// that require `auth != null` under the database rules, so it can't
/// just start those subscriptions in the constructor — doing that
/// caused every read to be denied while signed out, the streams to
/// error out silently (no onError handler), and never recover even
/// after logging in (Dart streams don't auto-retry post-error). This
/// class instead listens to authStateChanges() itself and only starts
/// (or restarts, on a sign-out/sign-in cycle) the data subscriptions
/// once a user is actually signed in — tearing them down and resetting
/// to empty placeholders on sign-out.
class AppState extends ChangeNotifier {
  AppState(this.firebase) {
    notifications.initPlatform();
    // Bridges NotificationService's own ChangeNotifier into this one,
    // so `context.watch<AppState>()` (already used everywhere) picks
    // up badge-count changes too, without needing a second Provider.
    notifications.addListener(notifyListeners);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_handleAuthChange);
  }

  final FirebaseService firebase;
  final NotificationService notifications = NotificationService();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<Slot>>? _slotsSub;
  StreamSubscription<DeviceStatus>? _statusSub;
  StreamSubscription<List<DeviceEvent>>? _eventsSub;
  StreamSubscription<bool>? _connectedSub;
  StreamSubscription<List<Caregiver>>? _caregiversSub;
  StreamSubscription<List<ActivityLogEntry>>? _activityLogSub;
  Timer? _reminderTimer;

  List<Slot> slots = List.generate(5, (i) => Slot.empty(i));
  DeviceStatus status = const DeviceStatus();
  List<DeviceEvent> events = [];
  DeviceSettings settings = const DeviceSettings();
  // Optimistic true at startup — flips to false the moment Firebase's
  // own .info/connected signal says otherwise. With persistence enabled
  // (see main.dart), `slots`/`status`/`events` above still hold the last
  // synced values even while this is false.
  bool isOnline = true;

  int activeTab = 0;
  int? editingSlotIndex;
  bool settingsOpen = false;

  // Every caregiver who's signed up for this dispenser — live from
  // /dispensers/{id}/caregivers, populated by saveCaregiverProfile()
  // at registration (see login_screen.dart).
  List<Caregiver> caregivers = [];

  // Live from /dispensers/{id}/activity_log — see ActivityLogEntry's
  // doc comment for the uid vs fullNameSnapshot distinction.
  List<ActivityLogEntry> activityLog = [];

  // Baselines "events that already existed before this subscription
  // started watching" — see _checkEventNotifications()'s doc comment.
  bool _eventsBaselined = false;
  Set<String> _priorEventKeys = {};

  void _handleAuthChange(User? user) {
    notifications.loadForUser(user?.uid);
    if (user != null) {
      _startDataSubscriptions();
    } else {
      _cancelDataSubscriptions();
      _resetToEmpty();
    }
  }

  void _startDataSubscriptions() {
    if (_slotsSub != null) return; // already running — avoid double-subscribing
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      PushNotificationService().init(uid: uid, notifications: notifications);
    }
    _slotsSub = firebase.watchSlots().listen((updated) {
      slots = updated;
      notifyListeners();
    });
    _statusSub = firebase.watchStatus().listen((updated) {
      status = updated;
      notifyListeners();
    });
    _eventsSub = firebase.watchEvents().listen((updated) {
      events = updated;
      _checkEventNotifications(updated);
      notifyListeners();
    });
    _connectedSub = firebase.watchConnected().listen((connected) {
      isOnline = connected;
      notifyListeners();
    });
    _caregiversSub = firebase.watchCaregivers().listen((updated) {
      caregivers = updated;
      notifyListeners();
    });
    _activityLogSub = firebase.watchActivityLog().listen((updated) {
      activityLog = updated;
      notifyListeners();
    });
    // Checked once immediately, then every minute — the "medicine due
    // within 20 minutes" reminder isn't a device event at all, it's
    // purely a client-side clock check against each schedule's window.
    _checkUpcomingReminders();
    _reminderTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkUpcomingReminders());
  }

  void _cancelDataSubscriptions() {
    _slotsSub?.cancel();
    _statusSub?.cancel();
    _eventsSub?.cancel();
    _connectedSub?.cancel();
    _caregiversSub?.cancel();
    _activityLogSub?.cancel();
    _reminderTimer?.cancel();
    _slotsSub = null;
    _statusSub = null;
    _eventsSub = null;
    _connectedSub = null;
    _caregiversSub = null;
    _activityLogSub = null;
    _reminderTimer = null;
    _eventsBaselined = false;
    _priorEventKeys = {};
  }

  void _resetToEmpty() {
    slots = List.generate(5, (i) => Slot.empty(i));
    status = const DeviceStatus();
    events = [];
    caregivers = [];
    activityLog = [];
    isOnline = true;
    notifyListeners();
  }

  /// Turns new medicine_missed / stock_low / stock_critical events into
  /// notifications.
  ///
  /// THE FIRST snapshot after (re)subscribing contains EVERY event that
  /// already existed — not just ones that just happened. Without this
  /// baselining step, every fresh subscribe (app restart, or a
  /// different user signing in) would replay the entire historical
  /// event log as if all of it were brand new, flooding whoever
  /// happens to be signed in at that moment. Only events that appear
  /// in a LATER snapshot, that weren't in the prior one, count as
  /// genuinely new and get a notification.
  void _checkEventNotifications(List<DeviceEvent> updatedEvents) {
    final currentKeys = updatedEvents.map((e) => e.key).toSet();

    if (!_eventsBaselined) {
      _eventsBaselined = true;
      _priorEventKeys = currentKeys;
      return;
    }

    final newKeys = currentKeys.difference(_priorEventKeys);
    _priorEventKeys = currentKeys;
    if (newKeys.isEmpty) return;

    for (final e in updatedEvents) {
      if (!newKeys.contains(e.key)) continue;
      switch (e.type) {
        case 'medicine_missed':
          notifications.addIfNew(
            id: 'event_${e.key}',
            type: AppNotificationType.missed,
            title: 'Medicine Missed',
            body: '${e.name} was not taken in time.',
          );
        case 'stock_low':
          notifications.addIfNew(
            id: 'event_${e.key}',
            type: AppNotificationType.stockLow,
            title: 'Stock Running Low',
            body: '${e.name} is running low — consider a refill soon.',
          );
        case 'stock_critical':
          notifications.addIfNew(
            id: 'event_${e.key}',
            type: AppNotificationType.stockCritical,
            title: 'Stock Critical',
            body: '${e.name} is critically low — refill needed now.',
          );
      }
    }
  }

  /// The intended period windows per the firmware's own documentation
  /// (Morning 8:00-11:59, Lunch 12:00-15:59, Night 18:00-22:59) — a
  /// CLIENT-SIDE approximation. If your firmware's actual period timing
  /// differs from this (see the period-window bug flagged earlier in
  /// this project), this reminder's timing will be off to match — it
  /// has no way to know the device's real behavior, only what the
  /// documented intent is. Exact-time schedules use their own
  /// configured hour/minute directly instead, which is always accurate.
  int? _boundaryMinuteOfDay(ScheduleEntry s) {
    switch (s.period) {
      case 0:
        return 11 * 60 + 59; // Morning ends 11:59
      case 1:
        return 15 * 60 + 59; // Lunch ends 15:59
      case 2:
        return 22 * 60 + 59; // Night ends 22:59
      case 3:
        return s.hour * 60 + s.minute; // Exact — the moment itself is the deadline
      default:
        return null;
    }
  }

  void _checkUpcomingReminders() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final today = '${now.year}-${now.month}-${now.day}';

    for (final slot in slots) {
      if (!slot.enabled) continue;
      for (var i = 0; i < slot.schedules.length; i++) {
        final s = slot.schedules[i];
        if (s.takenToday) continue;
        final boundary = _boundaryMinuteOfDay(s);
        if (boundary == null) continue;
        final minutesLeft = boundary - nowMinutes;
        if (minutesLeft <= 20 && minutesLeft >= 0) {
          notifications.addIfNew(
            id: 'reminder_${slot.index}_${i}_$today',
            type: AppNotificationType.upcomingReminder,
            title: 'Dose Due Soon',
            body: '${slot.medicineName} is due within 20 minutes.',
          );
        }
      }
    }
  }

  int get totalToday =>
      slots.where((s) => s.enabled).fold(0, (sum, s) => sum + s.schedules.length);

  int get takenToday => slots
      .where((s) => s.enabled)
      .fold(0, (sum, s) => sum + s.schedules.where((sc) => sc.takenToday).length);

  int get pctToday => totalToday == 0 ? 0 : ((takenToday / totalToday) * 100).round();

  void setTab(int i) {
    activeTab = i;
    settingsOpen = false;
    notifyListeners();
  }

  void openSlotEditor(int index) {
    editingSlotIndex = index;
    notifyListeners();
  }

  void closeSlotEditor() {
    editingSlotIndex = null;
    notifyListeners();
  }

  /// Fire-and-forget on purpose — a logging failure (e.g. a brief
  /// offline blip) should never block or delay the actual action the
  /// caregiver is waiting on. No-ops silently if somehow called with
  /// nobody signed in, which shouldn't happen since every caller here
  /// only runs once _startDataSubscriptions has already confirmed a
  /// signed-in user.
  void _logActivity(String action, {String? detail}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = user.displayName?.trim();
    unawaited(firebase
        .logActivity(
          uid: user.uid,
          fullNameSnapshot: (name != null && name.isNotEmpty) ? name : null,
          action: action,
          detail: detail,
        )
        .catchError((_) {})); // best-effort — a logging failure must never surface anywhere
  }

  /// Public entry point for logging — use this from any screen that
  /// performs a loggable action WITHOUT going through one of AppState's
  /// own methods above (edit profile, the push-notification toggle,
  /// PDF export). Those bypass AppState entirely today (talking to
  /// FirebaseAuth/NotificationService/Printing directly), so nothing
  /// hooked into saveSlot/saveSettings/etc. above ever sees them.
  void logAction(String action, {String? detail}) => _logActivity(action, detail: detail);

  /// Updates ONE slot — locally and on Firebase.
  ///
  /// This is the other half of the single-slot-update fix (see
  /// FirebaseService.pushSlot): we replace exactly one index in the
  /// list via a new list (`List.of(slots)` then `next[i] = updated`)
  /// instead of resetting/rebuilding the whole `slots` list from
  /// scratch. Never do `slots = [updated, updated, updated, ...]` or
  /// reconstruct all 5 from a stale local copy — that silently
  /// overwrites siblings with old data the next time this fires.
  Future<void> saveSlot(Slot updated) async {
    final old = slots[updated.index];
    final next = List<Slot>.of(slots);
    next[updated.index] = updated;
    slots = next;
    editingSlotIndex = null;
    notifyListeners();
    await firebase.pushSlot(updated);
    _logSlotChanges(old, updated);
  }

  /// Compares the slot BEFORE and AFTER a save and logs one entry PER
  /// distinct kind of change, instead of one generic 'schedule_edit'
  /// for every possible edit — a quantity bump after a refill and an
  /// actual dose-time change used to be logged identically, with no
  /// way to tell them apart later. A single Save tap can touch more
  /// than one of these at once (e.g. renaming a medicine AND bumping
  /// its quantity in the same form submit) — each changed aspect gets
  /// its own log entry rather than picking one and losing the rest.
  void _logSlotChanges(Slot old, Slot updated) {
    if (old.quantity != updated.quantity) {
      _logActivity('quantity_updated',
          detail: '${updated.medicineName} (${old.quantity}\u2192${updated.quantity})');
    }
    if (old.medicineName != updated.medicineName) {
      _logActivity('medicine_renamed', detail: '${old.medicineName}\u2192${updated.medicineName}');
    }
    if (old.dose != updated.dose) {
      _logActivity('dose_updated', detail: '${updated.medicineName}: ${old.dose}\u2192${updated.dose}');
    }
    if (old.enabled != updated.enabled) {
      _logActivity(updated.enabled ? 'slot_enabled' : 'slot_disabled', detail: updated.medicineName);
    }
    _logScheduleChange(old, updated);
  }

  /// Describes what actually changed about the dose-time schedules,
  /// not just "something changed" — a night\u2192morning period switch
  /// used to be indistinguishable in the log from adding a slot or
  /// touching nothing schedule-related at all; this reuses
  /// ScheduleEntry.label (already used on-screen for the same
  /// "Night" / "Morning" style text) so the log entry reads the exact
  /// same way the UI itself would describe it.
  void _logScheduleChange(Slot old, Slot updated) {
    final oldList = old.schedules;
    final newList = updated.schedules;

    if (oldList.length != newList.length) {
      _logActivity('schedule_edit',
          detail: '${updated.medicineName}: ${oldList.length}\u2192${newList.length} dose${newList.length == 1 ? '' : 's'}');
      return;
    }

    final changes = <String>[];
    for (var i = 0; i < newList.length; i++) {
      if (!mapEquals(oldList[i].toJson(), newList[i].toJson())) {
        changes.add('${oldList[i].label}\u2192${newList[i].label}');
      }
    }
    if (changes.isNotEmpty) {
      _logActivity('schedule_edit', detail: '${updated.medicineName}: ${changes.join(', ')}');
    }
  }

  void toggleSettings(bool open) {
    settingsOpen = open;
    notifyListeners();
  }

  void saveSettings(DeviceSettings updated) {
    final old = settings;
    settings = updated;
    settingsOpen = false;
    notifyListeners();
    _logSettingsChanges(old, updated);
    // TODO: firmware doesn't yet handle a config command — local only.
  }

  /// Same discipline as _logSlotChanges: only log something that
  /// actually changed. Tapping Save with the form untouched used to
  /// unconditionally write a 'settings_saved' entry every single
  /// time — this compares against the PREVIOUS settings first.
  ///
  /// SSID and password are logged as ONE 'wifi_credentials_changed'
  /// entry (not two) if either changes — these fields are still local
  /// UI-only placeholders (firmware doesn't read them, nothing pushes
  /// them to Firebase yet), so there's no real "which one changed"
  /// distinction worth making yet either. Revisit once that's an
  /// actual feature. The password's own VALUE is never logged, in
  /// either field or detail — this log is visible to every caregiver
  /// on the dispenser.
  void _logSettingsChanges(DeviceSettings old, DeviceSettings updated) {
    if (old.ssid != updated.ssid || old.password != updated.password) {
      _logActivity('wifi_credentials_changed');
    }
    if (old.lowStock != updated.lowStock) {
      _logActivity('low_stock_threshold_changed', detail: '${old.lowStock}\u2192${updated.lowStock}');
    }
  }

  Future<void> requestSync() => firebase.sendCommand('get_status');

  Future<void> startRefill() {
    _logActivity('refill_start');
    return firebase.sendCommand('start_refill');
  }

  Future<void> exitRefill() {
    _logActivity('refill_exit');
    return firebase.sendCommand('exit_refill');
  }

  Future<void> dispenseSlot(int index) {
    final name = (index >= 0 && index < slots.length) ? slots[index].medicineName : 'slot_$index';
    _logActivity('manual_dispense', detail: name);
    return firebase.dispenseSlot(index);
  }

  /// Firmware only actually reboots while its state machine is
  /// STATE_IDLE (see the .ino's command handler) — never mid-dispense
  /// or mid-refill, so this can't strand the lid open or leave a
  /// half-finished stepper move. There's no ack channel back from the
  /// firmware, so the app has no way to confirm the restart happened;
  /// the UI leans on `status.isActuallyOnline` and `status.mode`
  /// instead of a request/response result here.
  Future<void> restartDevice() {
    _logActivity('restart_requested');
    return firebase.sendCommand('restart');
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cancelDataSubscriptions();
    notifications.removeListener(notifyListeners);
    notifications.dispose();
    super.dispose();
  }
}
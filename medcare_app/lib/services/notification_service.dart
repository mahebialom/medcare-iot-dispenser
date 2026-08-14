import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_notification.dart';

/// Owns notification HISTORY (persisted locally on this device, PER
/// SIGNED-IN USER — see loadForUser()) and shows the actual OS-level
/// notification banner while the app process is alive.
///
/// LIMITATION: this only fires while some part of the app is running
/// (foreground, or briefly backgrounded). It CANNOT deliver a
/// notification once the app has been fully killed on its own — that
/// needs Firebase Cloud Messaging pushed from the Cloud Function (see
/// /functions/index.js), which routes through the same addIfNew() here
/// via PushNotificationService.
///
/// Also not supported on Flutter Web at all — flutter_local_notifications
/// has no web implementation. Calls here are guarded with kIsWeb so the
/// rest of the app still works fine when run in Chrome for testing
/// other features.
class NotificationService extends ChangeNotifier {
  static const _prefsKeyPrefix = 'medcare_notifications_v1_';
  // Read by firebaseMessagingBackgroundHandler (a separate, fresh Dart
  // isolate with no access to this running instance) so it can figure
  // out which user's history to write to. Kept in sync on every
  // loadForUser() call.
  static const _currentUidKey = 'medcare_current_uid';
  static const _maxHistory = 100;
  static const _channelId = 'medcare_alerts';

  final _plugin = FlutterLocalNotificationsPlugin();
  List<AppNotification> _notifications = [];
  final Set<String> _seenIds = {};
  bool _platformInitialized = false;
  String? _uid;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.read).length;

  /// Reads the last-known signed-in uid — used by
  /// firebaseMessagingBackgroundHandler, a separate isolate with no
  /// access to a running NotificationService instance's in-memory state.
  static Future<String?> readCurrentUid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentUidKey);
  }

  /// Persists a notification to history from the BACKGROUND isolate —
  /// a separate, fresh Dart environment with no access to a running
  /// NotificationService instance (no _uid, no _seenIds, no
  /// notifyListeners()). This re-implements just the storage side of
  /// addIfNew() as a standalone static call: load this uid's saved
  /// list fresh, dedupe against IT (not in-memory _seenIds, which
  /// doesn't exist here), cap, and save back. The OS-level banner
  /// itself is shown separately by firebaseMessagingBackgroundHandler
  /// using its own FlutterLocalNotificationsPlugin instance — this
  /// method only handles history persistence.
  static Future<void> addIfNewBackground({
    required String uid,
    required String id,
    required AppNotificationType type,
    required String title,
    required String body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsKeyPrefix$uid';

    List<AppNotification> list = [];
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        list = (jsonDecode(raw) as List)
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        list = []; // corrupted cache — start fresh rather than crash
      }
    }

    if (list.any((n) => n.id == id)) return; // already recorded — de-dup

    list.insert(
        0,
        AppNotification(
            id: id,
            type: type,
            title: title,
            body: body,
            timestamp: DateTime.now()));
    if (list.length > _maxHistory) {
      list = list.sublist(0, _maxHistory);
    }

    await prefs.setString(
        key, jsonEncode(list.map((n) => n.toJson()).toList()));
  }

  /// One-time OS-level setup (permission request, notification
  /// channel) — this is device/platform config, NOT user-specific, so
  /// call it once ever, regardless of who signs in. Safe to call
  /// multiple times; only does real work the first time.
  Future<void> initPlatform() async {
    if (_platformInitialized) return;
    _platformInitialized = true;

    if (kIsWeb) return; // no local-notifications support on web

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl
        ?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      'MedCare Alerts',
      description: 'Missed doses, low stock, and upcoming dose reminders',
      importance: Importance.high,
    ));
  }

  /// Switches which user's notification history is active — call this
  /// on every sign-in AND sign-out (with uid == null on sign-out).
  ///
  /// THIS IS THE FIX for "read one user's notifications, then a
  /// different user logs in and inherits that read state / missing
  /// badge count": storage was previously a single device-wide key, so
  /// whichever user was signed in last effectively owned everyone's
  /// read/unread state on that device. Each uid now gets its own
  /// persisted history, loaded fresh whenever the signed-in user
  /// changes.
  Future<void> loadForUser(String? uid) async {
    if (uid == _uid) return; // no actual change — avoid redundant reloads
    _uid = uid;
    _notifications = [];
    _seenIds.clear();

    final prefs = await SharedPreferences.getInstance();
    if (uid == null) {
      await prefs.remove(_currentUidKey);
      notifyListeners();
      return;
    }
    await prefs.setString(_currentUidKey, uid);

    await _migrateLegacyHistoryIfPresent(uid);
    await _load();
    notifyListeners();
  }

  /// One-time recovery for history saved before per-user storage
  /// existed (a single global key, 'medcare_notifications_v1' — no
  /// suffix). If found, whichever user signs in FIRST after this
  /// update adopts it as their own history, then the old key is
  /// deleted so this only ever runs once. There's no way to know which
  /// user actually "owned" those old entries (the old scheme never
  /// tracked that), so first-to-sign-in is the best available heuristic.
  Future<void> _migrateLegacyHistoryIfPresent(String uid) async {
    const legacyKey = 'medcare_notifications_v1';
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyKey);
    if (legacy == null) return;

    final newKey = '$_prefsKeyPrefix$uid';
    if (!prefs.containsKey(newKey)) {
      await prefs.setString(newKey, legacy);
    }
    await prefs.remove(legacyKey);
  }

  String get _prefsKey => '$_prefsKeyPrefix${_uid ?? 'anonymous'}';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      _notifications = list;
      _seenIds.addAll(list.map((n) => n.id));
    } catch (_) {
      // Corrupted or old-format cache — start fresh rather than crash.
      _notifications = [];
    }
  }

  Future<void> _persist() async {
    if (_uid == null) return; // nothing to persist to while signed out
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_notifications.map((n) => n.toJson()).toList()));
  }

  /// Adds a notification if [id] hasn't been seen before — de-dup is
  /// essential here, since the same underlying Firebase event can
  /// otherwise re-trigger this every time the stream re-emits (which
  /// happens more often than "this is genuinely new").
  Future<void> addIfNew({
    required String id,
    required AppNotificationType type,
    required String title,
    required String body,
  }) async {
    if (_uid == null) return; // no signed-in user to own this notification
    if (_seenIds.contains(id)) return;
    _seenIds.add(id);

    final notification = AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        timestamp: DateTime.now());
    _notifications.insert(0, notification);
    if (_notifications.length > _maxHistory) {
      _notifications = _notifications.sublist(0, _maxHistory);
    }
    notifyListeners();
    await _persist();

    if (!kIsWeb) {
      await _plugin.show(
        id.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'MedCare Alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }
  }

  /// Marks a set of ids as already-seen WITHOUT generating a
  /// notification or banner — used to baseline "events that already
  /// existed before we started watching" so a fresh subscribe doesn't
  /// replay the entire historical backlog as if it were all brand new.
  void markSeenSilently(Iterable<String> ids) {
    _seenIds.addAll(ids);
  }

  void markAllRead() {
    for (final n in _notifications) {
      n.read = true;
    }
    notifyListeners();
    _persist();
  }
}

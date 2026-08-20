import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config.dart';
import '../models/app_notification.dart';
import 'notification_service.dart';

/// Registers this device with Firebase Cloud Messaging (so the Cloud
/// Function — see /functions/index.js — can push to it) and routes
/// incoming messages through the same NotificationService used for
/// in-app events.
///
/// Foreground messages call NotificationService.addIfNew() directly —
/// that method ALWAYS records history and gates only the OS banner
/// internally via its own pushEnabled flag (see notification_service.dart).
///
/// Background/killed-app messages are handled by the TOP-LEVEL
/// firebaseMessagingBackgroundHandler below instead — FCM spins up a
/// separate, fresh Dart isolate for those, which has no access to the
/// running app's state (there may be no running app at all), so it
/// re-initializes Firebase and shows the OS notification directly.
/// Since it has no access to a running NotificationService instance's
/// in-memory pushEnabled flag, it reads the persisted preference via
/// NotificationService.readPushEnabledForUid() instead — same
/// "history always saved, banner conditionally shown" split as the
/// foreground path, just implemented via a fresh read instead of an
/// in-memory field.
///
/// Both paths use the SAME `id` the client-side event/reminder logic
/// already generates (see AppState), so whichever path processes a
/// given event first "wins" and the other is a safe no-op — no
/// duplicate notifications regardless of foreground/background timing.
///
/// This device is shared by multiple caregivers. unregisterToken()
/// below is called from AuthGate.signOut() so that once a caregiver
/// signs out, this device stops receiving pushes meant for a signed-in
/// user — AuthGate guarantees signOut() only runs while online, so
/// this always has a real chance to reach the database. There is
/// deliberately NO automatic (onDisconnect-based) removal — the token
/// must persist across the app being closed or force-killed while
/// still signed in, and is only ever cleared by an explicit,
/// successful, online sign-out.
///
/// NOTE: FCM push PERMISSION is requested once, at app launch, inside
/// NotificationService.initPlatform() — NOT here. See that method's
/// doc comment for why (a first-registration-only token-failure bug
/// traced to permission-request timing).
class PushNotificationService {
  final _messaging = FirebaseMessaging.instance;

  Future<void> init({required String uid, required NotificationService notifications}) async {
    if (kIsWeb) return; // this targets mobile; web push needs separate VAPID key setup

    // Permission is already requested in NotificationService.initPlatform()
    // at app launch, well before this ever runs.
    var token = await _messaging.getToken();
    if (token == null) {
      // Rare fallback — brief retry in case the token genuinely wasn't
      // ready yet for some other transient reason.
      await Future.delayed(const Duration(seconds: 2));
      token = await _messaging.getToken();
    }
    if (token != null) await _saveToken(uid, token);
    _messaging.onTokenRefresh.listen((newToken) => _saveToken(uid, newToken));

    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      final idRaw = data['id'];
      final typeRaw = data['type'];
      if (idRaw == null || typeRaw == null) return;
      notifications.addIfNew(
        id: idRaw,
        type: AppNotificationType.values.firstWhere(
          (t) => t.name == typeRaw,
          orElse: () => AppNotificationType.missed,
        ),
        title: data['title'] ?? 'MedCare Alert',
        body: data['body'] ?? '',
      );
    });
  }

  Future<void> _saveToken(String uid, String token) async {
    // Keyed by TOKEN (not uid) so multiple devices per caregiver, and
    // multiple caregivers, all just accumulate as separate entries the
    // Cloud Function iterates over — see functions/index.js's
    // getTokens(). No extra database rule needed: the existing
    // "auth != null" write rule on /dispensers/{deviceId} already
    // covers this child path.
    //
    // Deliberately NO onDisconnect() hook here — see the class-level
    // note above. The token is only ever removed by unregisterToken().
    await FirebaseDatabase.instance.ref('dispensers/$kDeviceId/fcmTokens/$token').set(uid);
  }

  /// Removes this device's token from the database AND deletes it
  /// locally, so FCM issues a fresh token next time someone signs in
  /// rather than silently reusing one that's already been
  /// unregistered. Called from AuthGate.signOut(), which guarantees
  /// this only runs while a network connection is present.
  Future<void> unregisterToken() async {
    if (kIsWeb) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await FirebaseDatabase.instance.ref('dispensers/$kDeviceId/fcmTokens/$token').remove();
      }
      await _messaging.deleteToken();
    } catch (e) {
      // Non-fatal — AuthGate already confirmed connectivity before
      // calling this, so failures here should be rare, but don't
      // block sign-out over it either way.
      debugPrint('[PushNotificationService] unregisterToken failed (ignored): $e');
    }
  }
}

/// MUST be a top-level (or static) function — this is a hard FCM/Dart
/// requirement, not a style choice. Register it in main.dart via
/// `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)`
/// BEFORE runApp() — see the setup notes for the exact snippet, since
/// main.dart isn't being edited directly here.
///
/// Persists to history via NotificationService.addIfNewBackground() —
/// a standalone static method safe to call from this isolated context
/// (see its docs for why a live NotificationService instance can't be
/// used here). Reads the last-known signed-in uid via
/// NotificationService.readCurrentUid(); if that comes back null (no
/// one signed in / device shared and nobody currently logged in), we
/// still show the OS banner but skip history persistence, since there's
/// no per-user history to own it.
///
/// PUSH ENABLE/DISABLE: history persistence above ALWAYS happens
/// (unconditional on the toggle) — but showing the actual OS banner
/// below is gated by NotificationService.readPushEnabledForUid(uid),
/// so a caregiver who's turned push off still gets everything recorded
/// in their history without seeing/hearing the banner. If uid is null
/// (no signed-in owner for this device right now), the banner still
/// shows by default — there's no per-user preference to consult in
/// that case, and the previous default behavior was to always show it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final data = message.data;
  final title = data['title'] ?? 'MedCare Alert';
  final body = data['body'] ?? '';
  final id = data['id'] ?? title;
  final typeRaw = data['type'];

  final uid = await NotificationService.readCurrentUid();
  var pushEnabled = true;

  if (uid != null) {
    if (typeRaw != null) {
      await NotificationService.addIfNewBackground(
        uid: uid,
        id: id,
        type: AppNotificationType.values.firstWhere(
          (t) => t.name == typeRaw,
          orElse: () => AppNotificationType.missed,
        ),
        title: title,
        body: body,
      );
    }
    pushEnabled = await NotificationService.readPushEnabledForUid(uid);
  }

  if (!pushEnabled) return; // history already saved above — banner skipped

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));
  await plugin.show(
    id.hashCode,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'medcare_alerts',
        'MedCare Alerts',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}
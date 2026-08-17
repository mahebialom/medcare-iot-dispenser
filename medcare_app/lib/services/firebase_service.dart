import 'package:firebase_database/firebase_database.dart';
import '../models/slot.dart';
import '../models/device_status.dart';
import '../models/device_event.dart';
import '../models/caregiver.dart';

/// All Firebase Realtime Database reads/writes for one dispenser device.
/// Paths here match your firmware's fetchSlotsFromFirebase() /
/// pushSlotToFirebase() / pushHeartbeat() / streamCallback() exactly.
class FirebaseService {
  FirebaseService(this.deviceId);
  final String deviceId;

  DatabaseReference get _root =>
      FirebaseDatabase.instance.ref('dispensers/$deviceId');

  /// Firebase's own connectivity signal — reflects whether the SDK's
  /// socket is actually connected to the Firebase backend, which is a
  /// more accurate "are we really online" check than just asking the
  /// OS whether Wi-Fi/mobile data is on (you can have a radio connection
  /// with no real backend reachability). This is a special top-level
  /// path, NOT under /dispensers/{id} — must come from the database
  /// root, not `_root`.
  Stream<bool> watchConnected() {
    return FirebaseDatabase.instance.ref('.info/connected').onValue.map((event) {
      return (event.snapshot.value as bool?) ?? false;
    });
  }

  // App-side accent colors per slot — the device doesn't store these.
  // Used by Dashboard/Schedule. The Tray tab intentionally uses its own
  // separate, more vibrant palette (see tray_painter.dart) — the two
  // are decoupled on purpose.
  static const _slotColors = ['#1a6b4a', '#1a4e8a', '#8a5a00', '#6e40c9', '#8f97a3'];

  Stream<List<Slot>> watchSlots() {
    return _root.child('slots').onValue.map((event) {
      final raw = event.snapshot.value;
      // Firebase RTDB serializes a node as a JSON ARRAY (not a map) when
      // its children are dense integer keys — which /slots/0../slots/4
      // always are. Handle both shapes, or every slot silently reads as
      // Slot.empty() whenever Firebase happens to hand back a List.
      return List.generate(5, (i) {
        dynamic entry;
        if (raw is List) {
          entry = i < raw.length ? raw[i] : null;
        } else if (raw is Map) {
          entry = raw['$i'];
        }
        if (entry is Map) {
          return Slot.fromJson(entry, i, color: _slotColors[i]);
        }
        return Slot.empty(i, color: _slotColors[i]);
      });
    });
  }

  Stream<DeviceStatus> watchStatus() {
    return _root.child('status').onValue.map((event) {
      final raw = event.snapshot.value;
      return raw is Map ? DeviceStatus.fromJson(raw) : const DeviceStatus();
    });
  }

  /// /events keys are push()-generated (not dense integers like /slots),
  /// so this always comes back as a Map — no array-vs-map gotcha here.
  /// `limitToLast` caps how much history loads at once; raise it if you
  /// want a longer scroll-back. Firebase may log a missing-index warning
  /// for `orderByChild('timestamp')` in the console — add
  /// `.indexOn: ["timestamp"]` under this device's rules if you want to
  /// clear that (works fine without it at this data size either way).
  Stream<List<DeviceEvent>> watchEvents({int limit = 100}) {
    return _root
        .child('events')
        .orderByChild('timestamp')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      final events = <DeviceEvent>[];
      if (raw is Map) {
        for (final entry in raw.entries) {
          if (entry.value is Map) {
            events.add(DeviceEvent.fromJson(entry.key.toString(), entry.value as Map));
          }
        }
      }
      events.sort((a, b) {
        if (a.timestamp == null || b.timestamp == null) return 0;
        return b.timestamp!.compareTo(a.timestamp!); // newest first
      });
      return events;
    });
  }

  /// Writes ONLY this one slot's node — /dispensers/{id}/slots/{index} —
  /// never the whole /slots tree.
  ///
  /// THIS IS THE FIX for "editing one slot updates all of them": every
  /// slot write must be scoped to slots/{index} like this. If you ever
  /// see that bug again, check that nothing elsewhere calls
  /// `_root.child('slots').set(...)` with the *entire* slots list —
  /// that would overwrite every slot's data with whatever local copy
  /// triggered it, which is almost certainly what your current code
  /// was doing.
  Future<void> pushSlot(Slot slot) =>
      _root.child('slots/${slot.index}').update(slot.toJson());

  Future<void> sendCommand(String cmd) => _root.child('command').set(cmd);

  /// Checks a device-independent username index before registration,
  /// so two caregivers can't claim the same username. Not airtight on
  /// its own (a race between two simultaneous signups is possible) —
  /// paired with a Realtime Database rule that also rejects overwriting
  /// an already-claimed username (".write": "!data.exists()") for the
  /// actual guarantee. This client-side check just gives a fast, clear
  /// error message before that.
  ///
  /// TIMEOUT: .get() has no built-in timeout and can hang indefinitely
  /// while offline (with persistence enabled, it waits for a real
  /// server round-trip rather than failing fast) — without this, the
  /// register flow's loading spinner would never resolve at all while
  /// offline. Throws a TimeoutException after 8s, which the caller
  /// catches and turns into a clear "no connection" message.
  Future<bool> isUsernameTaken(String username) async {
    final snap = await FirebaseDatabase.instance
        .ref('usernames/${username.toLowerCase()}')
        .get()
        .timeout(const Duration(seconds: 8));
    return snap.exists;
  }

  /// Checks whether a caregiver profile already exists in the database
  /// for this uid. Used by AuthGate right after ANY sign-in (email or
  /// Google) to decide whether to show the app or a one-time username
  /// setup step. Email/password registration always calls
  /// saveCaregiverProfile() itself before this is ever checked for
  /// that user, so this only ever comes back false for a genuinely
  /// first-time Google sign-in.
  Future<bool> caregiverProfileExists(String uid) async {
    final snap = await _root.child('caregivers/$uid').get().timeout(const Duration(seconds: 8));
    return snap.exists;
  }

  /// Writes the caregiver's profile AND claims their username in one
  /// atomic multi-path update — either both succeed or neither does,
  /// so you can never end up with a claimed username pointing at a
  /// profile that was never actually written.
  Future<void> saveCaregiverProfile({
    required String uid,
    required String fullName,
    required String username,
    required String email,
  }) {
    final updates = <String, dynamic>{
      'dispensers/$deviceId/caregivers/$uid': {
        'fullName': fullName,
        'username': username,
        'email': email,
        'createdAt': ServerValue.timestamp,
      },
      'usernames/${username.toLowerCase()}': uid,
    };
    return FirebaseDatabase.instance.ref().update(updates);
  }

  /// Updates ONLY the fullName field for one caregiver — same
  /// single-field-write discipline as pushSlot(): never overwrite the
  /// whole caregiver record, just the field that changed. Needed
  /// because Firebase Auth's displayName update (done separately, in
  /// the UI layer) only updates that user's OWN Auth record — other
  /// caregivers only ever see the copy stored here.
  Future<void> updateCaregiverFullName({required String uid, required String fullName}) =>
      _root.child('caregivers/$uid/fullName').set(fullName);

  /// Marks this caregiver's record as deleted rather than removing it
  /// outright — preserves ONLY fullName plus a `deleted: true` flag,
  /// visible in the Firebase console for reference, but filtered out
  /// of watchCaregivers() below so it never appears in the app's UI.
  /// Also removes their username claim (so it becomes available again)
  /// and every FCM token entry registered under their uid on this
  /// device (covers every device they were ever signed in on).
  ///
  /// DESIGN NOTE — changing retention policy later: this is the ONLY
  /// place that decides what to keep. To switch to full removal
  /// instead of preservation, change just the caregivers/$uid write
  /// below from set({'fullName': ..., 'deleted': true}) to
  /// _root.child('caregivers/$uid').remove() — nothing else in the
  /// codebase (Caregiver model, caregiver_screen.dart, the
  /// watchCaregivers() filter, this method's caller) needs to change.
  ///
  /// Deliberately does NOT touch Firebase Auth — call
  /// FirebaseAuth.instance.currentUser?.delete() separately, AFTER
  /// this completes. Keeping this idempotent (safe to call again) is
  /// what makes that ordering safe: if the Auth deletion step fails
  /// (e.g. requires-recent-login), nothing here needs undoing before
  /// a retry.
  Future<void> deleteCaregiverAccount(String uid) async {
    final caregiverSnap = await _root
        .child('caregivers/$uid')
        .get()
        .timeout(const Duration(seconds: 8));

    final data = caregiverSnap.value;
    final fullName =
        (data is Map && data['fullName'] != null) ? data['fullName'].toString() : '';
    final username =
        (data is Map && data['username'] != null) ? data['username'].toString() : null;

    if (username != null) {
      await FirebaseDatabase.instance
          .ref('usernames/${username.toLowerCase()}')
          .remove();
    }

    // See DESIGN NOTE above — this line is the single point of control
    // for the preserve-vs-remove decision.
    await _root.child('caregivers/$uid').set({
      'fullName': fullName,
      'deleted': true,
    });

    final tokensSnap = await _root
        .child('fcmTokens')
        .get()
        .timeout(const Duration(seconds: 8));
    if (tokensSnap.exists && tokensSnap.value is Map) {
      final tokens = tokensSnap.value as Map;
      final tokenUpdates = <String, dynamic>{};
      tokens.forEach((token, ownerUid) {
        if (ownerUid == uid) {
          tokenUpdates['fcmTokens/$token'] = null;
        }
      });
      if (tokenUpdates.isNotEmpty) {
        await _root.update(tokenUpdates);
      }
    }
  }

  /// The shared caregiver contact list — every caregiver who's signed
  /// up sees every other caregiver's name/email here. This is the
  /// reason saveCaregiverProfile() above writes fullName to the
  /// database at all: Firebase Auth's own displayName field is only
  /// readable by that user themselves via the client SDK, never by
  /// other users looking them up.
  ///
  /// Filters out any record with `deleted: true` (see
  /// deleteCaregiverAccount() above) — those remain visible in the
  /// Firebase console for reference, but never reach the app's UI.
  Stream<List<Caregiver>> watchCaregivers() {
    return _root.child('caregivers').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <Caregiver>[];
      return raw.entries
          .where((e) => e.value is Map && (e.value as Map)['deleted'] != true)
          .map((e) => Caregiver.fromJson(e.key.toString(), e.value as Map))
          .toList();
    });
  }

  /// NOTE: your firmware's streamCallback() currently only understands
  /// "start_refill" / "exit_refill" on /command. Dispensing a single
  /// slot on demand from the app needs a small firmware addition —
  /// see the guide for the exact snippet to add to streamCallback().
  Future<void> dispenseSlot(int index) => sendCommand('dispense_slot_$index');
}
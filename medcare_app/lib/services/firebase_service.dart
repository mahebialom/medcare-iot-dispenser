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
  Future<bool> isUsernameTaken(String username) async {
    final snap = await FirebaseDatabase.instance.ref('usernames/${username.toLowerCase()}').get();
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

  /// The shared caregiver contact list — every caregiver who's signed
  /// up sees every other caregiver's name/email here. This is the
  /// reason saveCaregiverProfile() above writes fullName to the
  /// database at all: Firebase Auth's own displayName field is only
  /// readable by that user themselves via the client SDK, never by
  /// other users looking them up.
  Stream<List<Caregiver>> watchCaregivers() {
    return _root.child('caregivers').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <Caregiver>[];
      return raw.entries
          .where((e) => e.value is Map)
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
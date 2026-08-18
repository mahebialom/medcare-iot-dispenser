import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/username_setup_screen.dart';
import 'app_root.dart';
import 'services/firebase_service.dart';
import 'services/push_notification_service.dart';

const _kWasSignedInKey = 'auth_was_signed_in';

/// Root-level router: Splash while Firebase resolves the current auth
/// state, then LoginScreen (signed out), UsernameSetupScreen (signed
/// in but no caregiver profile yet — a first-time Google sign-in), or
/// AppRoot (signed in with a profile).
///
/// Handles three distinct "signed out" scenarios differently:
///
/// 1. COLD-START RESTORE RACE: authStateChanges() can emit an initial
///    `null` before it finishes restoring a persisted session from
///    disk. If our own local flag says the user was previously signed
///    in, we poll currentUser directly for up to ~10s before giving
///    up, instead of committing to the login screen immediately.
///
/// 2. EXPLICIT SIGN-OUT: when the user taps "log out" (via signOut()
///    below), or when we detect a remote disable/delete, we already
///    know the resulting null event is real — so we skip the poll
///    entirely and go straight to the login screen with no delay.
///
/// 3. REMOTE INVALIDATION: authStateChanges() alone does not detect a
///    user being disabled/deleted remotely — it only reacts to local
///    SDK-initiated events. We actively force a validity check
///    (getAccountInfo via reload()) periodically and on app resume, so
///    a remote disable/delete kicks the user out promptly.
///
/// PROFILE CHECK: any time we land on a genuinely signed-in user (from
/// any of the paths above), we check whether a caregiver profile
/// exists for them in the database. Both the email/password and
/// Google sign-in paths can race this check against their own profile
/// write (see login_screen.dart and username_setup_screen.dart) —
/// both call markProfileComplete() once their save finishes, so a
/// stale "not found" result from this check can never leave the user
/// stuck on UsernameSetupScreen after they've already supplied one.
///
/// SPLASH-FLASH FIX: that profile check is a database round-trip, so
/// there's a brief gap between "signed in" and "know where to route."
/// For a COLD START (app launch, restoring a saved session), Splash is
/// already on screen during that gap — fine, no visible change. But
/// for an INTERACTIVE sign-in (LoginScreen was just on screen and the
/// user tapped Sign In), swapping to Splash for that gap and then
/// immediately swapping again to AppRoot produced a visible one-frame
/// "flash" of a second splash screen. Fixed by keeping LoginScreen
/// mounted during the check in that specific case instead of swapping
/// to Splash — see _handleAuthEvent's `cameFromLogin` check below.
///
/// This device is shared by multiple caregivers, so signOut() also
/// unregisters this device's FCM token so whoever's no longer signed
/// in stops receiving push alerts. That cleanup requires reaching
/// Firebase, so signOut() checks for a network connection FIRST and
/// refuses to sign out at all while offline — nothing changes locally
/// or in Firebase in that case, and the caller shows a warning.
/// Deliberately: nothing removes the token just because the app was
/// closed or killed while still signed in — only an explicit,
/// successful, online sign-out does.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  static final GlobalKey<_AuthGateState> authGateKey =
      GlobalKey<_AuthGateState>();

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  Timer? _validityTimer;
  StreamSubscription<User?>? _authStateSub;
  final _firebaseService = FirebaseService(kDeviceId);

  User? _currentUser;
  bool _authResolved = false;
  bool _firstResumeSkipped = false;
  bool _minSplashElapsed = false;
  int _pollGeneration = 0;
  bool _explicitSignOutInProgress = false;

  // Profile-existence check — separate from auth resolution above.
  // Reset to unchecked whenever the signed-in user changes or signs
  // out; re-run every time we land on a genuinely signed-in user.
  bool _profileChecked = false;
  bool _hasProfile = false;
  int _profileCheckGeneration = 0;

// add alongside the other profile-check state
  bool _emailRegistrationInProgress = false;

  void beginEmailRegistration() {
    _emailRegistrationInProgress = true;
  }

  void endEmailRegistration() {
    _emailRegistrationInProgress = false;
  }

    // One-shot message handed off by another screen just before it
  // signs the user out — e.g. AccountManagementScreen after a
  // successful account deletion — so LoginScreen can show a toast
  // once it mounts. Consumed and cleared by LoginScreen's initState().
  String? pendingLoginMessage;

  void setPendingLoginMessage(String message) {
    pendingLoginMessage = message;
  }

  // Same idea, but for messages meant to show once the user LANDS ON
  // THE DASHBOARD instead — sign-in (either method), signup, and
  // username creation all set this right before AuthGate swaps away
  // from whatever screen collected the action. Consumed and cleared
  // by AppRoot's _ShellState.initState().
  //
  // A first-time Google sign-in sets this to a "signed in" message,
  // then routes to UsernameSetupScreen (not AppRoot) — that message
  // sits unconsumed until UsernameSetupScreen overwrites it with its
  // own "username created" message right before AppRoot finally
  // mounts. Net effect: exactly one toast for the one real completed
  // action, never a leftover "signed in" toast for a user who hasn't
  // finished setup yet.
  String? pendingDashboardMessage;

  void setPendingDashboardMessage(String message) {
    pendingDashboardMessage = message;
  }

  // True while the profile check is pending AND we should keep
  // showing LoginScreen (not Splash) during that gap — see the
  // SPLASH-FLASH FIX note above.
  bool _keepShowingLoginDuringProfileCheck = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _validityTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _checkStillValid());
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _minSplashElapsed = true);
    });

    // Seed synchronously if a session is already available — covers
    // the case where restoration finished before we even started
    // listening. This is a cold-start path — Splash is already on
    // screen, so the default (don't keep LoginScreen) is correct.
    final initial = FirebaseAuth.instance.currentUser;
    if (initial != null) {
      _currentUser = initial;
      _authResolved = true;
      _markWasSignedIn(true);
      _checkProfile(initial.uid);
    }

    _authStateSub =
        FirebaseAuth.instance.authStateChanges().listen(_handleAuthEvent);
  }

  Future<void> _markWasSignedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWasSignedInKey, value);
  }

  Future<bool> _getWasSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kWasSignedInKey) ?? false;
  }

  /// Kicks off (or restarts, if the signed-in user changed) the
  /// profile-existence check. Safe to call multiple times — a
  /// generation counter ensures only the LATEST check's result is ever
  /// applied, so a fast sign-out/sign-in cycle can't have a stale
  /// check overwrite newer state.
  ///
  /// [keepShowingLogin]: if true, build() keeps rendering LoginScreen
  /// (rather than Splash) while this check is pending — see the
  /// SPLASH-FLASH FIX note on the class.
  void _checkProfile(String uid, {bool keepShowingLogin = false}) {
    _profileCheckGeneration++;
    final myGeneration = _profileCheckGeneration;
    _profileChecked = false;
    _keepShowingLoginDuringProfileCheck = keepShowingLogin;

    _firebaseService.caregiverProfileExists(uid).then((exists) {
      if (!mounted || myGeneration != _profileCheckGeneration) return;
      setState(() {
        _hasProfile = exists;
        _profileChecked = true;
      });
    }).catchError((_) {
      if (!mounted || myGeneration != _profileCheckGeneration) return;
      // On error (e.g. offline right at this moment) assume a profile
      // exists rather than blocking a normal returning user from
      // reaching the app — this only matters for the rare case of a
      // first-time Google user who is ALSO offline at this exact
      // instant, and they'll simply be asked for a username the next
      // time this check runs successfully.
      setState(() {
        _hasProfile = true;
        _profileChecked = true;
      });
    });
  }

  /// Called once a caregiver profile has just been saved by whoever
  /// is signing the user up — UsernameSetupScreen (after Google
  /// sign-in) or LoginScreen (right after email/password
  /// registration) — so AuthGate can move straight to AppRoot without
  /// waiting for another database round-trip.
  ///
  /// Also bumps the generation counter so that a profile-existence
  /// check already in flight (started the instant the signed-in event
  /// fired, which can be BEFORE the caller's own save finishes — see
  /// login_screen.dart) can't later resolve with a stale "not found"
  /// result and overwrite this.
  void markProfileComplete() {
    _profileCheckGeneration++;
    _emailRegistrationInProgress = false; // <-- add this
    setState(() {
      _hasProfile = true;
      _profileChecked = true;
    });
  }

  /// Plain device-level connectivity check (WiFi or mobile data
  /// present) — NOT a Firebase-reachability check. Intentionally
  /// simple and fast so it can't get "stuck": it just asks the OS
  /// whether a network interface is currently up.
  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// Call this for user-initiated logout (e.g. a "Log out" button),
  /// instead of calling FirebaseAuth.instance.signOut() directly
  /// elsewhere in the app.
  ///
  /// Returns `false` and makes NO changes at all — local or in
  /// Firebase — if there's no network connection right now. The
  /// caregiver remains fully signed in; the caller should show a
  /// warning message. Returns `true` once the token is unregistered
  /// from Firebase and the Firebase sign-out has completed.
  Future<bool> signOut() async {
    final online = await _isOnline();
    if (!online) return false;

    _explicitSignOutInProgress = true;
    _pollGeneration++; // cancel any poll that might currently be running
    await _markWasSignedIn(false);
    await PushNotificationService().unregisterToken();
    await FirebaseAuth.instance.signOut();
    return true;
  }

  /// Call this ONLY after the Firebase Auth account has already been
  /// permanently deleted (user.delete() succeeded) — NOT for a normal
  /// sign-out (use signOut() for that).
  ///
  /// WHY THIS EXISTS: user.delete() itself triggers authStateChanges()
  /// to fire null, immediately — often before the caller's next line
  /// even runs. If that null event arrives before _explicitSignOutInProgress
  /// is set, AuthGate treats it as an AMBIGUOUS null (the cold-start
  /// restore-race case) and starts polling for up to 10s instead of
  /// clearing state right away. Then, since the account is already
  /// gone, a follow-up FirebaseAuth.instance.signOut() call has no
  /// actual state change to report — Firebase does NOT re-fire the
  /// stream for a no-op sign-out — so _currentUser never gets cleared
  /// at all, and the UI gets stuck showing stale data forever.
  ///
  /// This method sidesteps all of that: it doesn't wait for or depend
  /// on any stream event. It directly clears local state and cancels
  /// any in-flight poll via the generation counter, so it's correct
  /// regardless of whether the SDK's own null event already fired,
  /// is about to fire, or never fires again.
  void forceSignedOutAfterDeletion() {
    _explicitSignOutInProgress = false; // no further event expected to matter
    _pollGeneration++; // cancels any in-flight restore-poll from the race above
    _profileCheckGeneration++;
    _profileChecked = false;
    _hasProfile = false;
    _markWasSignedIn(false);
    setState(() {
      _currentUser = null;
      _authResolved = true;
    });
  }

  void _handleAuthEvent(User? user) {
    _pollGeneration++;

    if (user != null) {
      debugPrint('[AuthGate] authStateChanges: signed in (${user.uid})');
      // If we were already signed out (LoginScreen was on screen)
      // right before this event, this is an interactive sign-in —
      // keep LoginScreen mounted during the profile check instead of
      // flashing Splash. Otherwise (e.g. a genuine cold-start restore
      // completing) Splash is already showing, so the default is fine.
      final cameFromLogin = _currentUser == null;
      _explicitSignOutInProgress = false;
      _markWasSignedIn(true);
      _checkProfile(user.uid, keepShowingLogin: cameFromLogin);
      setState(() {
        _currentUser = user;
        _authResolved = true;
      });
      return;
    }

    _profileCheckGeneration++; // cancel any in-flight profile check
    _profileChecked = false;
    _hasProfile = false;
    _keepShowingLoginDuringProfileCheck = false;

    if (_explicitSignOutInProgress) {
      debugPrint(
          '[AuthGate] explicit sign-out — skipping poll, going to login immediately');
      _explicitSignOutInProgress = false;
      setState(() {
        _currentUser = null;
        _authResolved = true;
      });
      return;
    }

    debugPrint(
        '[AuthGate] authStateChanges: null — checking if a session should restore');
    _resolveNullEvent();
  }

  Future<void> _resolveNullEvent() async {
    final myGeneration = _pollGeneration;
    final wasSignedIn = await _getWasSignedIn();

    if (!wasSignedIn) {
      debugPrint(
          '[AuthGate] no prior session on record — going to login immediately');
      if (!mounted || myGeneration != _pollGeneration) return;
      setState(() {
        _currentUser = null;
        _authResolved = true;
      });
      return;
    }

    debugPrint(
        '[AuthGate] prior session on record — polling for restore (up to ~10s)');
    const interval = Duration(milliseconds: 400);
    const maxAttempts = 25; // ~10s total

    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(interval);
      if (!mounted || myGeneration != _pollGeneration)
        return; // superseded by a newer event

      final resolvedUser = FirebaseAuth.instance.currentUser;
      if (resolvedUser != null) {
        debugPrint('[AuthGate] session restored on attempt $i — race avoided');
        // Splash has been showing throughout this poll — default
        // (don't keep LoginScreen) is correct here.
        _checkProfile(resolvedUser.uid);
        setState(() {
          _currentUser = resolvedUser;
          _authResolved = true;
        });
        return;
      }
    }

    debugPrint(
        '[AuthGate] gave up after ${maxAttempts * interval.inMilliseconds}ms — genuinely signed out');
    _markWasSignedIn(false);
    if (!mounted || myGeneration != _pollGeneration) return;
    setState(() {
      _currentUser = null;
      _authResolved = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _validityTimer?.cancel();
    _authStateSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_firstResumeSkipped) {
        _firstResumeSkipped = true;
        return;
      }
      _checkStillValid();
    }
  }

  Future<void> _checkStillValid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // reload() forces a real server round-trip (getAccountInfo) —
      // this is what actually surfaces "this account no longer exists
      // or is disabled," which a purely local check can never catch.
      await user.reload();
    } on FirebaseAuthException catch (e) {
      // ONLY these two codes are unambiguous "the account no longer
      // exists or was disabled" signals. Token-expiry-type codes are
      // usually transient — Firebase's SDK refreshes tokens on its own.
      const kickOutCodes = {'user-disabled', 'user-not-found'};
      debugPrint('[AuthGate] _checkStillValid() error: ${e.code}'
          '${kickOutCodes.contains(e.code) ? " — signing out" : " — ignoring (not a kick-out code)"}');
      if (kickOutCodes.contains(e.code)) {
        // reload() only succeeds if we were online, so no connectivity
        // gate is needed here — reaching this point already proves
        // Firebase was reachable.
        _explicitSignOutInProgress = true;
        _pollGeneration++;
        await _markWasSignedIn(false);
        await PushNotificationService().unregisterToken();
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      debugPrint('[AuthGate] _checkStillValid() non-auth error (ignored): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_authResolved || !_minSplashElapsed) {
      return const SplashScreen();
    }
    if (_currentUser == null) {
      return const LoginScreen();
    }
    if (!_profileChecked) {
      // See SPLASH-FLASH FIX note on the class — keep LoginScreen
      // mounted (no visible change) for an interactive sign-in;
      // Splash for a cold-start restore, where it's already showing.
      return _keepShowingLoginDuringProfileCheck
          ? const LoginScreen()
          : const SplashScreen();
    }
    if (!_hasProfile) {
      if (_emailRegistrationInProgress) {
        // A saveCaregiverProfile() write is in flight for an email/password
        // registration — this "no profile yet" result is just the save
        // racing ahead of us, not a real first-time-Google case. Keep
        // showing what we were already showing instead of flashing
        // UsernameSetupScreen.
        return _keepShowingLoginDuringProfileCheck
            ? const LoginScreen()
            : const SplashScreen();
      }
      return const UsernameSetupScreen();
    }
    return const AppRoot();
  }
}
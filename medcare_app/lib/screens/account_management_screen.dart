import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../auth_gate.dart';
import '../config.dart';
import '../services/firebase_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';

/// "Account Management" — shown inside the side-menu's Account
/// Management destination. Same "Your Account" card layout as
/// CaregiverScreen's account section, but with a single destructive
/// "Delete Account" action instead of Edit Profile / Sign Out.
///
/// Deletion order matters: database cleanup (FirebaseService.
/// deleteCaregiverAccount) and FCM token cleanup happen FIRST, since
/// both are idempotent/safe to retry — only once those succeed do we
/// delete the Firebase AUTHENTICATION account itself
/// (user.delete()), which is the step that can't be retried after
/// partial failure. If auth deletion fails (e.g. requires-recent-
/// login), the database is already in its final state either way, so
/// nothing is left inconsistent.
///
/// Network-gated the same way AuthGate.signOut() is — blocked
/// entirely while offline, since every step here needs to reach
/// Firebase reliably.
class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key, required this.c});
  final AppColors c;

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final _firebase = FirebaseService(kDeviceId);
  bool _deleting = false;

  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account permanently?'),
        content: const Text(
          'This will permanently delete your sign-in access, username and email. This cannot be undone.'
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    final online = await _isOnline();
    if (!online) {
      if (!mounted) return;
      showAppToast(
        context,
        "Can’t delete account while offline. Connect to the internet and try again",
        isError: true,
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _deleting = true);

    try {
      // Database + FCM cleanup FIRST — both idempotent, safe to retry
      // if the auth deletion step below fails.
      await _firebase.deleteCaregiverAccount(user.uid);
      await PushNotificationService().unregisterToken();

      // Deletes the Firebase AUTHENTICATION account itself — the
      // sign-in credentials (email/password or Google link) are gone
      // after this; the uid can never sign in again.
      await user.delete();

      if (!mounted) return;
      AuthGate.authGateKey.currentState
          ?.setPendingLoginMessage('Account deleted successfully');
      AuthGate.authGateKey.currentState?.forceSignedOutAfterDeletion();
      // Both the side-menu overlay and this Account Management page were
      // pushed on the ROOT Navigator (see side_menu.dart's _openFullScreen)
      // — forceSignedOutAfterDeletion() only swaps what the BASE route
      // renders (AppRoot -> LoginScreen), it doesn't touch anything pushed
      // on top of it. Without this, LoginScreen renders correctly underneath
      // but stays hidden behind the still-open menu/this still-open screen.
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'requires-recent-login'
          ? 'For security reason, sign in again before deleting your account'
          : 'Unable to delete account. Try again';
      showAppToast(context, msg, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Something went wrong. Please try again',
          isError: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    final email = user?.email ?? '';
    final shownName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : 'Caregiver';
    final initial = shownName.isNotEmpty ? shownName[0].toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('YOUR ACCOUNT',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: c.muted)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: const Color.fromARGB(255, 239, 3, 3).withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8)),
            ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: c.primary.withOpacity(0.15),
                backgroundImage: user?.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
                child: user?.photoURL == null
                    ? Text(initial,
                        style: TextStyle(
                            color: c.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shownName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: c.ink)),
                      if (email.isNotEmpty)
                        Text(email,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ElevatedButton.icon(
                onPressed: _deleting ? null : _confirmDelete,
                icon: _deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.delete_forever,
                        size: 15, color: Colors.white),
                label: Text(_deleting ? 'Deleting…' : 'Delete My Account',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? c.red.withOpacity(0.6)
                        : c.red,
                  ),
                  elevation: const WidgetStatePropertyAll(0),
                  shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
                  padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                ),
              ),
            ]),
          ]),
        ),
      ],
    );
  }
}
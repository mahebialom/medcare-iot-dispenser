import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../auth_gate.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';

class CaregiverScreen extends StatefulWidget {
  const CaregiverScreen({super.key, required this.c});
  final AppColors c;

  @override
  State<CaregiverScreen> createState() => _CaregiverScreenState();
}

class _CaregiverScreenState extends State<CaregiverScreen> {
  bool _editingProfile = false;

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to access this dispenser.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed != true) return;

    // Set BEFORE calling signOut() — signOut() triggers Firebase's
    // authStateChanges() practically immediately once it completes,
    // which is what swaps AuthGate away from this screen to
    // LoginScreen. Setting the message first guarantees it's already
    // in place by the time LoginScreen's initState() checks for it.
    AuthGate.authGateKey.currentState
        ?.setPendingLoginMessage('Signed out successfully');

    final success = await AuthGate.authGateKey.currentState?.signOut() ?? false;
    if (!success) {
      // Sign-out didn't actually happen (e.g. offline) — clear the
      // message we just set so it doesn't wrongly show up on some
      // later, unrelated visit to LoginScreen.
      AuthGate.authGateKey.currentState?.pendingLoginMessage = null;
      if (context.mounted) {
        showAppToast(
          context,
          "Can't sign out while offline. Connect to the internet and try again",
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = context.watch<AppState>();
    final user = FirebaseAuth.instance.currentUser;

    if (_editingProfile) {
      return _EditProfileForm(c: c, onDone: () => setState(() => _editingProfile = false));
    }

    final displayName = user?.displayName?.trim();
    final email = user?.email ?? '';
    final shownName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (email.isNotEmpty ? email.split('@').first : 'Caregiver');
    final initial = shownName.isNotEmpty ? shownName[0].toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('YOUR ACCOUNT',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: c.primary.withOpacity(0.15),
                backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                child: user?.photoURL == null
                    ? Text(initial, style: TextStyle(color: c.primary, fontWeight: FontWeight.bold, fontSize: 16))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shownName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.ink)),
                  if (email.isNotEmpty)
                    Text(email, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _editingProfile = true),
                icon: Icon(Icons.edit_outlined, size: 15, color: c.primary),
                label: Text('Edit Profile',
                    style: TextStyle(color: c.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.primary.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _confirmSignOut(context),
                icon: const Icon(Icons.logout, size: 15, color: Colors.white),
                label: const Text('Sign Out',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.hovered) ? c.red.withOpacity(0.82) : c.red,
                  ),
                  elevation: const WidgetStatePropertyAll(0),
                  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                ),
              ),
            ]),
          ]),
        ),

        const SizedBox(height: 24),
        Text('CAREGIVER CONTACTS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 10),
        if (app.caregivers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No other caregivers have signed up yet.', style: TextStyle(fontSize: 12, color: c.muted)),
          ),
        for (final cg in app.caregivers)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: c.panel, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: c.deviceBorder,
                child: Text(
                  cg.fullName.isNotEmpty ? cg.fullName[0].toUpperCase() : '?',
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(cg.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.bold, color: c.ink)),
                    ),
                    if (cg.uid == user?.uid) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: c.greenBg, borderRadius: BorderRadius.circular(6)),
                        child:
                            Text('You', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c.green)),
                      ),
                    ],
                  ]),
                  Text('@${cg.username} · ${cg.email}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

/// Full Name and Password are editable; Email and Username are shown
/// grayed-out (never editable) — Email because changing it is a
/// separate Firebase Auth flow with its own verification step (out of
/// scope here), Username because it's the key of the uniqueness index
/// in the database (see FirebaseService.saveCaregiverProfile) and
/// isn't meant to change after signup.
class _EditProfileForm extends StatefulWidget {
  const _EditProfileForm({required this.c, required this.onDone});
  final AppColors c;
  final VoidCallback onDone;

  @override
  State<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<_EditProfileForm> {
  late final TextEditingController _fullName;
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _saving = false;
  bool _obscure = true;
  String? _message;
  bool _messageIsError = true;

  @override
  void initState() {
    super.initState();
    _fullName = TextEditingController(text: FirebaseAuth.instance.currentUser?.displayName ?? '');
  }

  @override
  void dispose() {
    _fullName.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_fullName.text.trim().isEmpty) {
      setState(() {
        _message = 'Full name is required';
        _messageIsError = true;
      });
      return;
    }
    if (_newPassword.text.isNotEmpty) {
      if (_newPassword.text != _confirmPassword.text) {
        setState(() {
          _message = 'Passwords do not match';
          _messageIsError = true;
        });
        return;
      }
      if (_newPassword.text.length < 6) {
        setState(() {
          _message = 'Password must be at least 6 characters';
          _messageIsError = true;
        });
        return;
      }
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      final newName = _fullName.text.trim();
      if (newName != (user.displayName ?? '')) {
        await user.updateDisplayName(newName);
        if (mounted) {
          await context.read<AppState>().firebase.updateCaregiverFullName(uid: user.uid, fullName: newName);
        }
      }

      if (_newPassword.text.isNotEmpty) {
        await user.updatePassword(_newPassword.text);
      }

      if (!mounted) return;
       showAppToast(context, 'Profile updated successfully');
      widget.onDone();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'requires-recent-login'
          ? 'For security reason, sign in again before changing your password'
          : 'Could not save changes. Please try again';
      setState(() {
        _message = msg;
        _messageIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Something went wrong. Please try again';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final user = FirebaseAuth.instance.currentUser;
    final app = context.read<AppState>();
    final matches = app.caregivers.where((cg) => cg.uid == user?.uid);
    final username = matches.isEmpty ? null : matches.first.username;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('✎ Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.ink)),
        const SizedBox(height: 12),
        TextField(
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.badge_outlined)),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: false,
          controller: TextEditingController(text: user?.email ?? ''),
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            filled: true,
            fillColor: c.inputBg,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: false,
          controller: TextEditingController(text: username != null ? '@$username' : ''),
          decoration: InputDecoration(
            labelText: 'Username',
            prefixIcon: const Icon(Icons.alternate_email),
            filled: true,
            fillColor: c.inputBg,
          ),
        ),
        const SizedBox(height: 6),
        Text("Email and username can't be changed", style: TextStyle(fontSize: 11, color: c.muted)),
        const SizedBox(height: 18),
        TextField(
          controller: _newPassword,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'New Password (optional)',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPassword,
          obscureText: _obscure,
          decoration: const InputDecoration(labelText: 'Confirm New Password', prefixIcon: Icon(Icons.lock_outline)),
        ),
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(_message!, style: TextStyle(fontSize: 12, color: _messageIsError ? c.red : c.green)),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: OutlinedButton(
                onPressed: _saving ? null : widget.onDone,
                style: OutlinedButton.styleFrom(
                  backgroundColor: c.red.withOpacity(0.19),
                  foregroundColor: c.red,
                  side: BorderSide(color: c.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}
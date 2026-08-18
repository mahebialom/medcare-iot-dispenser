import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../auth_gate.dart';
import '../config.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../widgets/status_bar_style.dart';

/// Shown ONCE, right after a first-time Google sign-in — Google gives
/// us fullName and email automatically, but has no concept of the
/// app-specific username your caregiver records use. Email/password
/// registration collects this in its own form up front, so this
/// screen is skipped entirely for that path (AuthGate never routes
/// here for a user who already has a saved profile).
///
/// Reuses the exact same username validation, availability check
/// (isUsernameTaken), and save call (saveCaregiverProfile) as the
/// email/password registration flow in login_screen.dart, so both
/// paths end up with an identically-shaped caregiver record.
class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  static const c = AppColors.light;
  final _firebase = FirebaseService(kDeviceId);
  final _username = TextEditingController();

  bool _saving = false;
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // shouldn't happen — AuthGate only shows this screen when signed in

    final username = _username.text.trim();
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
      setState(() {
        _message = 'Username must be 3-20 characters — letters, numbers, underscore only.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      final taken = await _firebase.isUsernameTaken(username);
      if (taken) {
        setState(() {
          _message = 'That username is already taken — try another.';
          _messageIsError = true;
        });
        return;
      }

      await _firebase.saveCaregiverProfile(
        uid: user.uid,
        fullName: user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : 'Caregiver',
        username: username,
        email: user.email ?? '',
      );

      if (!mounted) return;
      // Shown once AppRoot mounts, not here — this screen is about to
      // be swapped away by AuthGate. See the doc comment on
      // pendingDashboardMessage in auth_gate.dart: this overwrites the
      // "Signed in successfully!" message the Google sign-in step set
      // earlier (still unconsumed, since AppRoot never mounted for a
      // first-time user until now), so exactly one toast shows for the
      // one real completed action.
      AuthGate.authGateKey.currentState
          ?.setPendingDashboardMessage('Profile created successfully!');
      AuthGate.authGateKey.currentState?.markProfileComplete();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Something went wrong. Please try again.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

@override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    final email = user?.email ?? '';

    return StatusBarStyle(
      brightness: Brightness.light,
      child: Scaffold(
        backgroundColor: c.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: 360,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(gradient: c.headerGrad, borderRadius: BorderRadius.circular(16)),
                      alignment: Alignment.center,
                      child: const Text('👋', style: TextStyle(fontSize: 30)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName != null && displayName.isNotEmpty ? 'Welcome, $displayName!' : 'Almost there!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pick a username to finish setting up your caregiver account',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  const SizedBox(height: 24),
                  if (email.isNotEmpty) ...[
                    TextField(
                      enabled: false,
                      controller: TextEditingController(text: email),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: true,
                        fillColor: c.inputBg,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.alternate_email),
                      helperText: 'Letters, numbers, underscore — 3 to 20 characters',
                      helperMaxLines: 2,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _message!,
                      style: TextStyle(fontSize: 12, color: _messageIsError ? c.red : c.green),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
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
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Text('Continue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
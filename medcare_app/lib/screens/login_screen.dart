import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';


/// Fixed-light for the same reason as SplashScreen — see that file's
/// comment. AuthGate swaps this out for AppRoot automatically once
/// FirebaseAuth's authStateChanges() emits a signed-in user, so there's
/// no manual navigation call needed after a successful sign-in here.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const c = AppColors.light;
  static const _kButtonRadius = 14.0;
  final _auth = AuthService();
  // LoginScreen renders BEFORE AppState exists (see auth_gate.dart) —
  // it can't reach one via Provider, so it talks to Firebase directly
  // for the two calls it needs (username check + profile save).
  // FirebaseService itself is cheap to construct — it doesn't start any
  // subscriptions until a watch* method is actually called.
  final _firebase = FirebaseService(kDeviceId);

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _isRegister = false;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    setState(() {
      _message = msg;
      _messageIsError = true;
    });
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      _showError('Enter both email and password.');
      return;
    }

    if (_isRegister) {
      if (_fullName.text.trim().isEmpty) {
        _showError('Enter your full name.');
        return;
      }
      final username = _username.text.trim();
      if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
        _showError('Username must be 3-20 characters — letters, numbers, underscore only.');
        return;
      }
      if (_password.text != _confirmPassword.text) {
        _showError('Passwords do not match.');
        return;
      }
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      if (_isRegister) {
        final username = _username.text.trim();

        final taken = await _firebase.isUsernameTaken(username);
        if (taken) {
          _showError('That username is already taken.');
          return;
        }

        final err = await _auth.register(_email.text, _password.text, displayName: _fullName.text.trim());
        if (err != null) {
          _showError(err);
          return;
        }

        // Registration succeeded — now save the extra profile fields
        // Firebase Auth itself doesn't store (username) alongside what
        // it does (email, displayName already set via register() above).
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await _firebase.saveCaregiverProfile(
            uid: uid,
            fullName: _fullName.text.trim(),
            username: username,
            email: _email.text.trim(),
          );
        }
        // AuthGate's authStateChanges() stream swaps to AppRoot automatically.
      } else {
        final err = await _auth.signIn(_email.text, _password.text);
        if (err != null) _showError(err);
      }
    } catch (e) {
      // Anything unexpected (permission-denied from a rules mismatch,
      // a network hiccup, etc.) lands here instead of leaving the
      // button stuck spinning forever with no feedback.
      if (e is TimeoutException) {
        _showError('No internet connection. Please check your connection and try again later.');
      } else {
        _showError('Something went wrong. Please try again later.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (_email.text.trim().isEmpty) {
      _showError('Enter your email above first, then tap "Forgot password".');
      return;
    }
    setState(() => _loading = true);
    final err = await _auth.resetPassword(_email.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = err ?? 'Password reset email sent — check your inbox.';
      _messageIsError = err != null;
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final err = await _auth.signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = err;
      _messageIsError = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      child: const Text('💊', style: TextStyle(fontSize: 30)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isRegister ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isRegister
                        ? 'Set up caregiver access to MedCare IoT'
                        : 'Sign in to your MedCare IoT dispenser',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  const SizedBox(height: 24),
                  if (_isRegister) ...[
                    TextField(
                      controller: _fullName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  if (_isRegister) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _username,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.alternate_email),
                        helperText: 'Letters, numbers, underscore — 3 to 20 characters',
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                      ),
                    ),
                    onSubmitted: (_) => _isRegister ? null : _submit(),
                  ),
                  if (_isRegister) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPassword,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          tooltip: _obscureConfirmPassword ? 'Show password' : 'Hide password',
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
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
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_kButtonRadius)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : Text(_isRegister ? 'Create Account' : 'Sign In',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_isRegister)
                    TextButton(
                      onPressed: _loading ? null : _forgotPassword,
                      style: TextButton.styleFrom(foregroundColor: c.red),
                      child: const Text('Forgot password?'),
                    ),
                  Row(children: [
                    Expanded(child: Divider(color: c.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('or', style: TextStyle(fontSize: 11, color: c.muted)),
                    ),
                    Expanded(child: Divider(color: c.border)),
                  ]),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signInWithGoogle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF7F8FA),
                        foregroundColor: c.ink,
                        elevation: 0,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: const StadiumBorder(),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Image.asset('assets/icons/google.png', width: 35, height: 35),

                        const SizedBox(width: 4),
                        Text('Continue with Google',
                            style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  const Divider(height: 20),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _isRegister = !_isRegister;
                              _message = null;
                            }),
                    child: Text(
                      _isRegister ? 'Already have an account? Sign in' : "New caregiver? Create an account",
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
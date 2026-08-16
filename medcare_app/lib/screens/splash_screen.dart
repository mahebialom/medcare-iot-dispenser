import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Shown while AuthGate waits for FirebaseAuth's first authStateChanges()
/// event. Deliberately fixed-light (not theme-aware) since it's a
/// pre-app transitional screen shown before we've loaded the saved
/// theme preference — see ThemeReveal for where that loads.
///
/// Does its own fade+scale entrance animation on mount, so it reads as
/// an actual splash screen rather than a static frame — this matters
/// because AuthGate enforces a minimum visible duration (see
/// auth_gate.dart), so this screen is guaranteed enough time on-screen
/// for the animation to actually be seen, even when Firebase resolves
/// the auth state almost instantly (common on web/cached sessions).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  late final Animation<double> _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: AppColors.light.headerGrad),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: const Text('💊', style: TextStyle(fontSize: 44)),
                ),
                const SizedBox(height: 20),
                const Text('MedCare IoT',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Smart medicine dispenser',
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.75))),

              ]),
            ),
          ),
        ),
      ),
    );
  }
}
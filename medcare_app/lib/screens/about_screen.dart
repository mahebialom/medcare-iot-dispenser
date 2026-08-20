import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../main.dart';

/// Real About content — replaces the "Coming soon" placeholder
/// previously shown for this menu destination (see side_menu.dart).
///
/// Kept self-contained (no cross-navigation into Privacy Policy or
/// elsewhere) so it doesn't need to duplicate side_menu.dart's
/// root-Navigator push pattern — just a static info screen.
///
/// The version number is read from appPackageInfo (see main.dart),
/// which is itself sourced from pubspec.yaml's `version:` field —
/// nothing to update here when you bump the app version, aside from
/// the side menu footer (side_menu.dart), which reads the same source.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
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
        const SizedBox(height: 14),
        Text(
          'MedCare IoT',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'Version ${appPackageInfo.version}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
        const SizedBox(height: 28),
        _AboutSection(
          c: c,
          title: 'About',
          body: 'MedCare IoT helps families and caregivers manage a shared '
              'medicine dispenser together. Track dose schedules, get '
              'notified about missed doses or low stock, and keep every '
              'caregiver on the same device in sync in real time.',
        ),
        _AboutSection(
          c: c,
          title: 'Developed By',
          body: 'Unplugged Brain',
        ),
        _AboutSection(
          c: c,
          title: 'Support',
          body: 'Questions, feedback, or an issue to report? Reach us at '
              'md.mahebialom@gmail.com.',
        ),
        _AboutSection(
          c: c,
          title: 'Acknowledgments',
          body: 'MedCare IoT is built with Flutter, and relies on Firebase '
              '(Authentication, Realtime Database, Cloud Messaging) and '
              'Google Sign-In to operate.',
        ),
        const SizedBox(height: 12),
        Text(
          '© ${DateTime.now().year} Md. Mahebi Alom Dipu | All rights reserved.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.c, required this.title, required this.body});
  final AppColors c;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(fontSize: 13, color: c.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}
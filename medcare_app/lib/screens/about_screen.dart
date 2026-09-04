import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
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

  static const _supportEmail = 'md.mahebialom@gmail.com';
  static const _repoUrl = 'https://github.com/mahebialom/medcare-iot-dispenser';

  /// Calls launchUrl() directly instead of gating on canLaunchUrl()
  /// first. canLaunchUrl() relies on the SAME package-visibility check
  /// (AndroidManifest.xml's <queries>) that launchUrl() itself needs —
  /// so on some OEM Android builds it can still return false even once
  /// <queries> is declared correctly, silently skipping the launch
  /// with zero feedback. launchUrl() throws instead of silently
  /// failing when nothing can handle the link, so a real failure
  /// surfaces as a toast rather than a link that just does nothing.
  Future<void> _launch(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) showAppToast(context, "Couldn't open that link");
    } catch (_) {
      if (context.mounted) showAppToast(context, "Couldn't open that link");
    }
  }

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
            clipBehavior: Clip.antiAlias,
            // Falls back to the emoji glyph if the launcher icon asset
            // is ever missing from the bundle, so this never crashes.
            child: Image.asset(
              'assets/icons/icon.png',
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Text('💊', style: TextStyle(fontSize: 30)),
            ),
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
          'Version ${appPackageInfo.version} (${appPackageInfo.buildNumber})',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
        const SizedBox(height: 28),
        _AboutSection(
          c: c,
          title: 'About',
          body: 'MedCare IoT is a smart automatic medicine dispenser built '
              'for visually impaired and elderly patients. An ESP32-powered '
              'dispenser rotates through medicine slots, dispenses the right '
              'dose on schedule and guides the patient through every step '
              'with spoken audio, no reading required. Caregivers use this '
              'app to set up schedules, track adherence and get notified '
              'the moment a dose is missed or stock runs low, all synced to '
              'the dispenser in real time through Firebase.',
        ),
        Divider(color: c.borderSoft, height: 1),
        const SizedBox(height: 22),
        _AboutSection(
          c: c,
          title: 'Key Features',
          body: '• Audio-guided dispensing with RFID medicine verification\n'
              '• Morning, lunch, night and exact-time scheduling per slot\n'
              '• Missed-dose, low-stock and upcoming-dose push notifications\n'
              '• Multiple caregivers, one dispenser, kept in sync live\n'
              '• Offline-aware: the dispenser keeps working without Wi-Fi',
        ),
        Divider(color: c.borderSoft, height: 1),
        const SizedBox(height: 22),
        _AboutSection(
          c: c,
          title: 'Developed By',
          body: 'Unplugged Brain',
        ),
        _AboutSection(
          c: c,
          title: 'Support',
          body: 'Questions, feedback, or an issue to report? Reach us at $_supportEmail.',
          onTap: () => _launch(context, Uri(scheme: 'mailto', path: _supportEmail, query: 'subject=MedCare IoT Support')),
        ),
        _AboutSection(
          c: c,
          title: 'Open Source',
          body: 'The full project (Flutter app, ESP32 firmware and hardware '
              'wiring) is open source on GitHub.',
          onTap: () => _launch(context, Uri.parse(_repoUrl)),
        ),
        _AboutSection(
          c: c,
          title: 'Acknowledgments',
          body: 'MedCare IoT is built with Flutter and relies on Firebase '
              '(Authentication, Realtime Database, Cloud Messaging) and '
              'Google Sign-In to operate.',
        ),
        const SizedBox(height: 12),
        Text(
          '© $_copyrightYears Md. Mahebi Alom Dipu | All rights reserved.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
      ],
    );
  }

  // Update _firstReleaseYear once, when the app first ships — everything
  // else (the "current" side of the range) stays correct on its own.
  static const _firstReleaseYear = 2026;
  String get _copyrightYears {
    final now = DateTime.now().year;
    return now > _firstReleaseYear ? '$_firstReleaseYear–$now' : '$_firstReleaseYear';
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.c, required this.title, required this.body, this.onTap});
  final AppColors c;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: TextStyle(
            fontSize: 13,
            color: onTap != null ? c.primary : c.text2,
            height: 1.5,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: content,
            ),
    );
  }
}
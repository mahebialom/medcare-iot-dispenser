import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Real Privacy Policy content — replaces the "Coming soon" placeholder
/// previously shown for this menu destination (see side_menu.dart).
///
/// Content reflects what this app ACTUALLY does per the codebase:
///   - Account creation via email/password OR Google Sign-In
///     (login_screen.dart) — collects full name, email, username.
///   - Caregiver records (fullName, username, email) are visible to
///     EVERY other caregiver signed up on the same shared dispenser
///     device (FirebaseService.watchCaregivers/saveCaregiverProfile) —
///     this is a real, notable disclosure, not boilerplate.
///   - Push notification tokens (FCM) registered per device
///     (push_notification_service.dart) to alert caregivers of missed
///     doses / low stock.
///   - Dispenser telemetry (slots, schedules, dose-taken events, stock
///     levels) stored in Firebase Realtime Database, shared across
///     caregivers on that device.
///   - Account deletion (AccountManagementScreen) preserves only
///     fullName (tagged `deleted: true`) and removes username, email,
///     and FCM tokens — worth stating plainly here.
///
/// This is a solid draft, not legal advice — have it reviewed by a
/// legal professional before publishing the app.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key, required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          'Effective date: August 19, 2026',
          style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 20),
        _Section(
          c: c,
          title: 'Introduction',
          body: 'MedCare IoT ("the app") is provided by Unplugged Brain '
              '("we", "us"). This policy explains what information the app '
              'collects, how it is used, and who it is shared with when you '
              'use MedCare IoT to manage a shared medicine dispenser with '
              'other caregivers.',
        ),
        _Section(
          c: c,
          title: 'Information We Collect',
          body: 'When you create an account either with email and '
              'password or by continuing with Google, we collect:\n\n'
              '• Full name\n'
              '• Email address\n'
              '• A username you choose\n'
              '• Your Google profile photo if you sign in with Google\n\n'
              'We do not receive or store your password directly that is '
              'handled by Firebase Authentication (see "Third Party '
              'Services" below).',
        ),
        _Section(
          c: c,
          title: 'Dispenser & Device Data',
          body: 'The app also stores data related to the medicine '
              'dispenser device itself, including dose schedules, which '
              'doses have been marked as taken, stock levels, and device '
              'connectivity status. This data is shared among every '
              'caregiver connected to that same dispenser, so the whole '
              'care team can stay informed.',
        ),
        _Section(
          c: c,
          title: 'Push Notifications',
          body: 'If you enable notifications, we register a device token '
              '(via Firebase Cloud Messaging) so the app can alert you '
              'about missed doses or low stock. Signing out or deleting '
              'your account removes this device\'s token and you will '
              'stop receiving alerts.',
        ),
        _Section(
          c: c,
          title: 'Information Sharing Among Caregivers',
          body: 'This app is built for shared caregiving. Because of that, '
              'your full name, username, and email address are visible to '
              'every other caregiver registered on the same dispenser '
              'device this is a core part of how the app works not an '
              'optional feature. If you are not comfortable with other '
              'caregivers on your device seeing this information, please '
              'do not use the app for a shared device with people you do '
              'not want to share it with.\n\nWe do not sell your '
              'information, and we do not share it with advertisers or '
              'unrelated third parties.',
        ),
        _Section(
          c: c,
          title: 'Third-Party Services',
          body: 'The app relies on the following Google/Firebase services '
              'to operate:\n\n'
              '• Firebase Authentication — handles sign-in and password '
              'storage\n'
              '• Firebase Realtime Database — stores caregiver, schedule, '
              'and device data\n'
              '• Firebase Cloud Messaging — delivers push notifications\n'
              '• Google Sign-In — an optional way to create your account\n\n'
              'These services have their own privacy policies governing '
              'how they handle data on their infrastructure.',
        ),
        _Section(
          c: c,
          title: 'Data Retention & Deletion',
          body: 'You can permanently delete your account at any time from '
              'Account Management. Doing so removes your sign-in '
              'credentials, username, email, and push-notification '
              'tokens. Your full name is retained in a de-identified '
              'form (with no way to sign back in or be contacted) so '
              'that historical dispenser records remain accurate for the '
              'rest of the care team . It is not displayed as an active '
              'caregiver going forward.',
        ),
        _Section(
          c: c,
          title: 'Security',
          body: 'We use Firebase\'s security infrastructure, including '
              'authenticated access rules, to protect your data. No '
              'method of storage or transmission is 100% secure, but we '
              'work to use commercially reasonable means to protect your '
              'information.',
        ),
        _Section(
          c: c,
          title: "Children's Privacy",
          body: 'MedCare IoT is not directed at children under 13, and we '
              'do not knowingly collect personal information from '
              'children under 13.',
        ),
        _Section(
          c: c,
          title: 'Changes to This Policy',
          body: 'We may update this policy from time to time. If we make '
              'material changes, we will update the effective date above.',
        ),
        _Section(
          c: c,
          title: 'Contact Us',
          body: 'Questions about this policy or your data? Contact us at '
              'md.mahebialom@gmail.com.',
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.c, required this.title, required this.body});
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
            title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.ink),
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
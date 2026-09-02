import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
///   - A signed-in caregiver's Google profile photo (when they use
///     Google Sign-In) is read live from FirebaseAuth.currentUser and
///     shown ONLY to that caregiver as their own avatar
///     (caregiver_screen.dart) — it is never written to the
///     caregivers/ record, so it is not one of the fields other
///     caregivers can see. Kept as a separate callout below rather
///     than lumped in with fullName/username/email, which ARE shared.
///   - Push notification tokens (FCM) registered per device
///     (push_notification_service.dart) to alert caregivers of missed
///     doses / low stock. The push on/off toggle (app_settings_screen.dart)
///     only affects the OS banner — history is always saved regardless.
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

  // Single point of control for the effective date shown in the header
  // AND referenced by the "Changes to This Policy" section — bump this
  // whenever the body copy actually changes, and both places update.
  static const _effectiveDate = 'August 19, 2026';

  // TODO(dev): confirm this against the actual Realtime Database URL in
  // the Firebase Console (Project Settings → General) before publishing —
  // the README's setup guide only ever suggested asia-southeast1 as an
  // EXAMPLE for a Bangladesh-based project, it isn't guaranteed to be
  // what got provisioned. Getting this wrong is a real data-residency
  // misstatement, not a typo.
  static const _dataRegion = 'asia-southeast1';

  static const _supportEmail = 'md.mahebialom@gmail.com';

  Future<void> _launchEmail() async {
    final uri = Uri(scheme: 'mailto', path: _supportEmail, query: 'subject=MedCare IoT Privacy Question');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        // Header — mirrors the icon-tile treatment on the About screen
        // so the two info screens read as one consistent "family"
        // rather than two differently-styled documents bolted together.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: c.headerGrad, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Privacy Policy',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c.ink)),
                  const SizedBox(height: 2),
                  Text('Effective $_effectiveDate',
                      style: TextStyle(fontSize: 12, color: c.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _Section(
          c: c,
          number: 1,
          title: 'Introduction',
          body: 'MedCare IoT ("the app") is provided by Unplugged Brain '
              '("we", "us"). This policy explains what information the app '
              'collects, how it is used and who it is shared with when you '
              'use MedCare IoT to manage a shared medicine dispenser with '
              'other caregivers. By creating an account, you agree to the '
              'practices described in this policy.',
        ),
        _BulletSection(
          c: c,
          number: 2,
          title: 'Information We Collect',
          intro: 'When you create an account, either with email and '
              'password or by continuing with Google, we collect:',
          bullets: const [
            'Full name',
            'Email address',
            'A username you choose (or, for Google sign-in, set up on your first login)',
          ],
          outro: 'We do not receive or store your password directly. That '
              'is handled by Firebase Authentication (see "Third-Party '
              'Services" below).\n\nIf you sign in with Google, the app also '
              'reads your Google profile photo to show as your own avatar '
              'inside the app. This photo is never saved to our database and '
              'is never visible to other caregivers. It is shown only to '
              'you, on your own device.',
        ),
        _Section(
          c: c,
          number: 3,
          title: 'Dispenser & Device Data',
          body: 'The app also stores data related to the medicine '
              'dispenser device itself, including dose schedules, which '
              'doses have been marked as taken, stock levels and device '
              'connectivity status. This data is shared among every '
              'caregiver connected to that same dispenser, so the whole '
              'care team can stay informed.',
        ),
        _Section(
          c: c,
          number: 4,
          title: 'Push Notifications',
          body: 'If you enable notifications, we register a device token '
              '(via Firebase Cloud Messaging) so the app can alert you '
              'about missed doses or low stock. You can turn push banners '
              'off at any time from Settings. This stops the alert sound '
              'and banner, but every notification is still recorded in '
              'your in-app History. Signing out, or deleting your account, '
              'removes this device\'s token entirely and you will stop '
              'receiving alerts altogether.',
        ),
        _Section(
          c: c,
          number: 5,
          title: 'Information Sharing Among Caregivers',
          highlight: true,
          body: 'This app is built for shared caregiving. Because of that, '
              'your full name, username and email address are visible to '
              'every other caregiver registered on the same dispenser '
              'device. This is a core part of how the app works, not an '
              'optional feature. If you are not comfortable with other '
              'caregivers on your device seeing this information, please '
              'do not use the app for a shared device with people you do '
              'not want to share it with.\n\nWe do not sell your '
              'information and we do not share it with advertisers or '
              'unrelated third parties.',
        ),
        _BulletSection(
          c: c,
          number: 6,
          title: 'Third-Party Services',
          intro: 'The app relies on the following Google/Firebase services '
              'to operate:',
          bullets: const [
            'Firebase Authentication: handles sign-in and password storage',
            'Firebase Realtime Database: stores caregiver, schedule and device data',
            'Firebase Cloud Messaging: delivers push notifications',
            'Google Sign-In: an optional way to create your account',
          ],
          outro: 'These services have their own privacy policies governing '
              'how they handle data on their infrastructure.',
        ),
        _Section(
          c: c,
          number: 7,
          title: 'Data Retention & Deletion',
          body: 'You can permanently delete your account at any time from '
              'Account Management. Doing so removes your sign-in '
              'credentials, username, email and push-notification '
              'tokens. Your full name is retained in a de-identified '
              'form (with no way to sign back in or be contacted) so '
              'that historical dispenser records remain accurate for the '
              'rest of the care team. It is not displayed as an active '
              'caregiver going forward.\n\nDispenser and schedule data '
              'shared across the care team is not automatically deleted '
              'when one caregiver leaves, since it belongs to the '
              'dispenser as a whole, not to any single caregiver.',
        ),
        _Section(
          c: c,
          number: 8,
          title: 'Your Rights',
          body: 'You can review the information tied to your account at '
              'any time from your Caregiver profile screen. You can '
              'correct your full name from Edit Profile. You can delete '
              'your account entirely, as described above. If you would '
              'like a copy of your data, or have a request this app '
              'doesn\'t support directly, contact us using the details '
              'below.',
        ),
        _Section(
          c: c,
          number: 9,
          title: 'Data Storage & Security',
          body: 'Your data is stored on Google Firebase infrastructure, in '
              'the $_dataRegion region. We use Firebase\'s security '
              'infrastructure, including authenticated access rules, to '
              'protect your data. Only signed-in caregivers on your '
              'specific dispenser can read or write its data. No method '
              'of storage or transmission is 100% secure, but we work to '
              'use commercially reasonable means to protect your '
              'information.',
        ),
        _Section(
          c: c,
          number: 10,
          title: 'Cookies & Tracking',
          body: 'MedCare IoT does not use cookies, third-party analytics, '
              'or advertising trackers. We do not track your activity '
              'across other apps or websites.',
        ),
        _Section(
          c: c,
          number: 11,
          title: "Children's Privacy",
          body: 'MedCare IoT is not directed at children under 13 and we '
              'do not knowingly collect personal information from '
              'children under 13.',
        ),
        _Section(
          c: c,
          number: 12,
          title: 'Changes to This Policy',
          body: 'We may update this policy from time to time. If we make '
              'material changes, we will update the effective date above.',
        ),
        _Section(
          c: c,
          number: 13,
          title: 'Governing Law',
          body: 'This policy is governed by the laws of Bangladesh, '
              'without regard to conflict-of-law principles.',
        ),
        Divider(color: c.borderSoft, height: 1),
        const SizedBox(height: 20),
        Text('CONTACT US',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 8),
        Text('Questions about this policy or your data? Reach us at:',
            style: TextStyle(fontSize: 13, color: c.text2, height: 1.4)),
        const SizedBox(height: 6),
        InkWell(
          onTap: _launchEmail,
          borderRadius: BorderRadius.circular(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline, size: 15, color: c.primary),
              const SizedBox(width: 6),
              Text(_supportEmail, style: TextStyle(fontSize: 13, color: c.primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Numbered circle used to the left of every section title — gives the
/// document the "table of clauses" look of a proper legal/professional
/// document instead of a flat wall of bolded headings.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.c, required this.number});
  final AppColors c;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.panel, shape: BoxShape.circle, border: Border.all(color: c.border)),
      child: Text('$number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.muted)),
    );
  }
}

/// Plain prose section — numbered title + one flowing paragraph. Kept
/// at a moderate 1.4 line-height (not 1.5) so wrapped lines within a
/// paragraph read as one connected block rather than looking overly
/// airy.
///
/// [highlight] wraps the body in a tinted callout (reusing the app's
/// existing amber token set) for the one disclosure users are most
/// likely to actually care about — otherwise it's visually identical
/// to sections like "Cookies & Tracking" that nobody needs to notice.
class _Section extends StatelessWidget {
  const _Section({required this.c, required this.number, required this.title, required this.body, this.highlight = false});
  final AppColors c;
  final int number;
  final String title;
  final String body;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final bodyText = Text(body, style: TextStyle(fontSize: 13, color: c.text2, height: 1.4));
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _NumberBadge(c: c, number: number),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.ink)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!highlight)
            Padding(padding: const EdgeInsets.only(left: 32), child: bodyText)
          else
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.amberBg,
                  border: Border.all(color: c.amberBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: c.amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text(body, style: TextStyle(fontSize: 13, color: c.amber, height: 1.4))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Section with a numbered title plus a bulleted list — deliberately
/// NOT built by cramming "\n• item" lines into one Text widget. Doing
/// that forced every blank/bullet line to inherit the same height:1.5
/// line-height multiplier as normal prose, which is what made bullet
/// lists look like they had an oversized gap between every single
/// line. Each bullet here is its own Row with a small, FIXED SizedBox
/// gap between items instead, giving direct control over the spacing
/// rather than leaving it to text-layout side effects.
class _BulletSection extends StatelessWidget {
  const _BulletSection({
    required this.c,
    required this.number,
    required this.title,
    required this.intro,
    required this.bullets,
    this.outro,
  });

  final AppColors c;
  final int number;
  final String title;
  final String intro;
  final List<String> bullets;
  final String? outro;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = TextStyle(fontSize: 13, color: c.text2, height: 1.4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _NumberBadge(c: c, number: number),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.ink)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(intro, style: bodyStyle),
                const SizedBox(height: 8),
                for (final item in bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 16, child: Text('•', style: bodyStyle)),
                        Expanded(child: Text(item, style: bodyStyle)),
                      ],
                    ),
                  ),
                if (outro != null) ...[
                  const SizedBox(height: 6),
                  Text(outro!, style: bodyStyle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
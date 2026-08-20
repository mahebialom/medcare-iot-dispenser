import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// App-level Settings — shown from the side menu's "Settings" tile.
/// NOT the same as SettingsScreen (settings_screen.dart), which is
/// actually wired to the side menu's "Device Settings" tile and
/// configures the dispenser hardware itself.
///
/// Currently holds a single control: whether PUSH notification
/// banners/sound show for this signed-in caregiver. Turning this off
/// does NOT stop notifications from being recorded — every
/// notification is still saved to History regardless of this setting;
/// it only stops the OS-level banner/sound from firing. See
/// NotificationService.pushEnabled / setPushEnabled() for where this
/// is actually enforced (notification_service.dart), and the matching
/// background-isolate gate in push_notification_service.dart's
/// firebaseMessagingBackgroundHandler.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key, required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final enabled = app.notifications.pushEnabled;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('NOTIFICATIONS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon badge — same visual language as the notification
              // list items in app_root.dart's _showNotifications and
              // the avatar circles in CaregiverScreen: a soft tinted
              // circle behind the icon rather than a bare glyph.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  enabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                  color: c.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Push Notifications',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.ink)),
                    const SizedBox(height: 3),
                    Text(
                      "When disabled you won't receive banners or sounds. "
                      "Notifications will still be saved to your History.",
                      style: TextStyle(fontSize: 12, color: c.muted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Material 3 switch — thumbIcon draws a check/x glyph
              // inside the thumb itself, and the slightly larger scale
              // gives it a chunkier, more deliberate feel than the
              // bare default size.
              Transform.scale(
                scale: 1.05,
                child: Switch(
                  value: enabled,
                  onChanged: (value) => app.notifications.setPushEnabled(value),
                  activeThumbColor: Colors.white,
                  activeTrackColor: c.primary,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: c.muted.withOpacity(0.35),
                  trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                  thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Icon(Icons.check, size: 14, color: c.primary);
                    }
                    return Icon(Icons.close, size: 14, color: c.muted);
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
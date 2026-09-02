import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/device_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';

/// Device Settings — configures the dispenser hardware (Wi-Fi, low
/// stock threshold), triggers a manual sync, and can request a
/// restart. Wired to the side menu's "Device Settings" tile — NOT the
/// same as the app-level Settings screen (app_settings_screen.dart),
/// which holds app preferences like the push-notification toggle.
///
/// Wi-Fi/stock fields and "Sync Now" are NOT read/acted on by firmware
/// yet (see the banner at the top of the screen and
/// DeviceSettings.saveSettings()'s TODO) — those are local-only today.
/// "Restart Device" IS real: it writes a `restart` command the
/// firmware DOES handle (medcare_dispenser.ino), gated so it only
/// actually reboots once the dispenser's state machine is idle.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.c});
  final AppColors c;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _ssid;
  late final TextEditingController _password;
  late final TextEditingController _lowStock;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _ssid = TextEditingController(text: s.ssid);
    _password = TextEditingController(text: s.password);
    _lowStock = TextEditingController(text: s.lowStock.toString());
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    _lowStock.dispose();
    super.dispose();
  }

  /// Same confirm-then-act shape as the account-deletion dialog in
  /// account_management_screen.dart, for a consistent "destructive
  /// action" feel across the app. There's no ack from the firmware
  /// once the command is sent (see AppState.restartDevice), so the
  /// toast here confirms the REQUEST was sent, not that the dispenser
  /// actually rebooted.
  Future<void> _confirmRestart(AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart dispenser?'),
        content: const Text(
          'The dispenser will reboot and be briefly unreachable for about '
          '10\u201315 seconds. It only restarts once it is idle, so this '
          'will not interrupt an active dispense or refill.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restart', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await app.restartDevice();
      if (mounted) showAppToast(context, 'Restart requested');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = context.read<AppState>();
    // watch(), not read() — this section shows live online/mode state,
    // so it needs to rebuild when a status heartbeat comes in while
    // this screen is open.
    final status = context.watch<AppState>().status;

    return ListView(
      padding: const EdgeInsets.only(
        left: 46,
        right: 46,
        bottom: 46,
      ),
      children: [
        // ── Not-yet-active notice ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: c.amberBg,
            border: Border.all(color: c.amberBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: c.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Wi-Fi and stock settings are saved in the app only for "
                  "now — the dispenser's firmware doesn't read this config "
                  "yet. \"Sync Now\" below is the same: it sends a request "
                  "the firmware doesn't currently act on either.",
                  style: TextStyle(fontSize: 11, color: c.amber, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Wi-Fi Connection ──
        Text('WI-FI CONNECTION',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: c.muted)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: c.deviceGrad,
            border: Border.all(color: c.deviceBorder),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: c.deviceBorder.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(children: [
            TextField(
              controller: _ssid,
              decoration: const InputDecoration(
                labelText: 'Network Name (SSID)',
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 20),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Stock Alerts ──
        Text('STOCK ALERTS',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: c.muted)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: c.deviceGrad,
            border: Border.all(color: c.deviceBorder),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: c.deviceBorder.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: TextField(
            controller: _lowStock,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Low Stock Threshold',
              prefixIcon: Icon(Icons.inventory_2_outlined),
              suffixText: 'tablets',
              helperText:
                  "You'll get an alert once a slot drops to or below this count.",
              helperMaxLines: 2,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Device Sync ──
        Text('DEVICE SYNC',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: c.muted)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: c.deviceGrad,
            border: Border.all(color: c.deviceBorder),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: c.deviceBorder.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.sync, size: 18, color: c.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Manually request the latest status from your dispenser.',
                  style: TextStyle(fontSize: 12, color: c.text2),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Plain default-sized Material 3 OutlinedButton — no
            // custom height/shape override, so it sizes itself
            // normally instead of stretching to a large fixed height.
            OutlinedButton.icon(
              onPressed: () {
                app.requestSync();
                showAppToast(context, 'Sync requested');
              },
              icon: Icon(Icons.sync, size: 17, color: c.primary),
              label: Text('Sync Now with Device',
                  style:
                      TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.primary.withOpacity(0.4)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Device Actions ──
        Text('DEVICE ACTIONS',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: c.muted)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.redBg,
            border: Border.all(color: c.redBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.power_settings_new, size: 18, color: c.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !status.isActuallyOnline
                        ? 'Dispenser appears offline. A restart request will sit queued and run whenever it reconnects.'
                        : status.mode == 'idle'
                            ? 'Dispenser is online and idle: safe to restart now.'
                            : 'Dispenser is online but currently "${status.mode}". The firmware only reboots once it returns to idle, this may not take effect immediately.',
                    style: TextStyle(fontSize: 12, color: c.red, height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _confirmRestart(app),
              icon: Icon(Icons.restart_alt, size: 17, color: c.red),
              label: Text('Restart Device',
                  style: TextStyle(color: c.red, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.red.withOpacity(0.4)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Save / Cancel ──
        // Plain default-sized Material 3 buttons — TextButton for the
        // secondary/dismissive action, FilledButton for the primary
        // one. No custom height, gradient, or shadow — Material 3's
        // own defaults (already themed via AppColorsTheming in
        // app_colors.dart) already look modern at a normal size
        // without needing to hand-design anything here.
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                app.toggleSettings(false);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancel',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: Color.alphaBlend(
                  const Color(0xFFE0453A).withOpacity(0.16),
                  Colors.white,
                ),
                foregroundColor: const Color(0xFFE0453A),
                elevation: 0,
                side: BorderSide(
                    color: const Color(0xFFE0453A).withOpacity(0.35),
                    width: 1.2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () {
                app.saveSettings(DeviceSettings(
                  ssid: _ssid.text,
                  password: _password.text,
                  lowStock: int.tryParse(_lowStock.text) ?? 7,
                ));
                showAppToast(context, 'Saved successfully');
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Save',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/device_settings.dart';
import '../theme/app_colors.dart';

/// Device Settings — configures the dispenser hardware (Wi-Fi, low
/// stock threshold) and triggers a manual sync. Wired to the side
/// menu's "Device Settings" tile — NOT the same as the app-level
/// Settings screen (app_settings_screen.dart), which holds app
/// preferences like the push-notification toggle.
///
/// NONE of these fields are read by firmware yet (see the banner at
/// the top of the screen and DeviceSettings.saveSettings()'s TODO) —
/// values are stored locally in the app only, for now.
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

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = context.read<AppState>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Not-yet-active notice ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  "now — your dispenser's firmware doesn't read this "
                  "config yet. See the setup guide for the firmware "
                  "addition needed to activate these.",
                  style: TextStyle(fontSize: 12, color: c.amber, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Wi-Fi Connection ──
        Text('WI-FI CONNECTION',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: c.deviceGrad,
            border: Border.all(color: c.deviceBorder),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: c.deviceBorder.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 3)),
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
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Stock Alerts ──
        Text('STOCK ALERTS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: c.deviceGrad,
            border: Border.all(color: c.deviceBorder),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: c.deviceBorder.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: TextField(
            controller: _lowStock,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Low Stock Threshold',
              prefixIcon: Icon(Icons.inventory_2_outlined),
              suffixText: 'tablets',
              helperText: "You'll get an alert once a slot drops to or below this count.",
              helperMaxLines: 2,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Device Sync ──
        Text('DEVICE SYNC',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: c.deviceGrad,
            border: Border.all(color: c.deviceBorder),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: c.deviceBorder.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              onPressed: () => app.requestSync(),
              icon: Icon(Icons.sync, size: 17, color: c.primary),
              label: Text('Sync Now with Device', style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.primary.withOpacity(0.4)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 28),

        // ── Save / Cancel ──
        // Plain default-sized Material 3 buttons — TextButton for the
        // secondary/dismissive action, FilledButton for the primary
        // one. No custom height, gradient, or shadow — Material 3's
        // own defaults (already themed via AppColorsTheming in
        // app_colors.dart) already look modern at a normal size
        // without needing to hand-design anything here.
        Row(children: [
          Expanded(
            child: TextButton(
              onPressed: () => app.toggleSettings(false),
              style: TextButton.styleFrom(foregroundColor: c.muted),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () => app.saveSettings(DeviceSettings(
                ssid: _ssid.text,
                password: _password.text,
                lowStock: int.tryParse(_lowStock.text) ?? 7,
              )),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
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
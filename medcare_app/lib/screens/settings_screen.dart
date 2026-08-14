import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/device_settings.dart';
import '../theme/app_colors.dart';

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
        Text('⚙️ Device Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.ink)),
        const SizedBox(height: 12),
        TextField(controller: _ssid, decoration: const InputDecoration(labelText: 'Wi-Fi Network (SSID)')),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Wi-Fi Password'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _lowStock,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Low Stock Threshold (tablets)'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 46,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => app.requestSync(),
            icon: Icon(Icons.sync, size: 18, color: c.primary),
            label: Text('Sync Now with Device', style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.primary.withOpacity(0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => app.toggleSettings(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.muted,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () => app.saveSettings(DeviceSettings(
                  ssid: _ssid.text,
                  password: _password.text,
                  lowStock: int.tryParse(_lowStock.text) ?? 7,
                )),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          "Wi-Fi/password here are stored in the app only for now — your "
          "firmware doesn't yet read config from Firebase. See the guide "
          "for the small addition needed on the device side.",
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
      ],
    );
  }
}
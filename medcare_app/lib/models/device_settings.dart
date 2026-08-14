/// App-side only for now — the firmware doesn't yet read config from
/// Firebase (see the Settings screen note / the Flutter guide).
class DeviceSettings {
  const DeviceSettings({
    this.ssid = '',
    this.password = '',
    this.lowStock = 7,
  });

  final String ssid;
  final String password;
  final int lowStock;

  DeviceSettings copyWith({String? ssid, String? password, int? lowStock}) =>
      DeviceSettings(
        ssid: ssid ?? this.ssid,
        password: password ?? this.password,
        lowStock: lowStock ?? this.lowStock,
      );
}

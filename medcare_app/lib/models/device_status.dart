/// Mirrors /dispensers/{id}/status, written by the firmware's
/// pushHeartbeat() every ~2 minutes.
class DeviceStatus {
  const DeviceStatus({
    this.online = false,
    this.lastSeen = '—',
    this.wifiRssi = 0,
    this.currentSlot = 0,
    this.mode = 'idle',
  });

  final bool online;
  final String lastSeen;
  final int wifiRssi;
  final int currentSlot;
  final String mode; // "idle" | "refill" | "active"

  factory DeviceStatus.fromJson(Map<dynamic, dynamic> j) => DeviceStatus(
        online: j['online'] as bool? ?? false,
        lastSeen: (j['lastSeen'] as String?) ?? '—',
        wifiRssi: (j['wifi_rssi'] as num?)?.toInt() ?? 0,
        currentSlot: (j['currentSlot'] as num?)?.toInt() ?? 0,
        mode: (j['mode'] as String?) ?? 'idle',
      );
}

enum AppNotificationType { missed, stockLow, stockCritical, upcomingReminder }

/// A notification the app has shown (or logged) locally. Persisted via
/// NotificationService — see that file's doc comment for the important
/// "foreground/background only, not killed-app" limitation.
class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.read = false,
  });

  final String id; // unique — used for de-dup and read-state tracking
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime timestamp;
  bool read;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: AppNotificationType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => AppNotificationType.missed,
        ),
        title: j['title'] as String,
        body: j['body'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        read: j['read'] as bool? ?? false,
      );
}

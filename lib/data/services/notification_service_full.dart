// Full notification service — port of neom_claw notification system.
// Extends the basic NotificationService (platform/notification_service.dart)
// with channels, preferences, scheduling, grouping, and export.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Notification category types.
enum NotificationType {
  info,
  success,
  warning,
  error,
  progress,
  permission,
  toolComplete,
  agentComplete,
  mention,
  systemUpdate,
}

/// Notification urgency level.
enum NotificationPriority { low, normal, high, urgent }

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// A button or action attached to a notification.
class NotificationAction {
  final String label;
  final void Function()? callback;
  final bool isPrimary;

  const NotificationAction({
    required this.label,
    this.callback,
    this.isPrimary = false,
  });
}

/// A single notification.
class AppNotification {
  final String id;
  final NotificationType type;
  final NotificationPriority priority;
  final String title;
  final String? body;
  final DateTime timestamp;
  bool read;
  bool dismissed;
  final List<NotificationAction> actions;
  final Map<String, dynamic> metadata;
  final String? groupKey;
  final DateTime? expiresAt;

  /// For progress-type notifications.
  double? progress;
  double? progressTotal;

  AppNotification({
    required this.id,
    required this.type,
    this.priority = NotificationPriority.normal,
    required this.title,
    this.body,
    DateTime? timestamp,
    this.read = false,
    this.dismissed = false,
    this.actions = const [],
    this.metadata = const {},
    this.groupKey,
    this.expiresAt,
    this.progress,
    this.progressTotal,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  @override
  String toString() => 'AppNotification($id "$title" $type)';
}

/// A notification channel controlling delivery behaviour.
class NotificationChannel {
  final String id;
  final String name;
  final String? description;
  bool enabled;
  bool sound;
  bool vibration;
  NotificationPriority priority;

  NotificationChannel({
    required this.id,
    required this.name,
    this.description,
    this.enabled = true,
    this.sound = true,
    this.vibration = true,
    this.priority = NotificationPriority.normal,
  });

  @override
  String toString() => 'NotificationChannel($id "$name")';
}

/// A time window for do-not-disturb scheduling.
class DoNotDisturbSchedule {
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final List<int> daysOfWeek; // 1=Mon .. 7=Sun

  const DoNotDisturbSchedule({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
  });

  /// Returns `true` if [time] falls within the DND window.
  bool isActive([DateTime? time]) {
    final now = time ?? DateTime.now();
    if (!daysOfWeek.contains(now.weekday)) return false;
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;
    final nowMinutes = now.hour * 60 + now.minute;

    if (startMinutes <= endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }
    // Spans midnight.
    return nowMinutes >= startMinutes || nowMinutes < endMinutes;
  }
}

/// User-level notification preferences.
class NotificationPreferences {
  final Map<String, NotificationChannel> channels;
  bool doNotDisturb;
  DoNotDisturbSchedule? doNotDisturbSchedule;
  bool soundEnabled;
  bool groupByType;

  NotificationPreferences({
    Map<String, NotificationChannel>? channels,
    this.doNotDisturb = false,
    this.doNotDisturbSchedule,
    this.soundEnabled = true,
    this.groupByType = true,
  }) : channels = channels ?? {};

  bool get isDndActive {
    if (doNotDisturb) return true;
    if (doNotDisturbSchedule != null) return doNotDisturbSchedule!.isActive();
    return false;
  }
}

// ---------------------------------------------------------------------------
// NotificationServiceFull
// ---------------------------------------------------------------------------

/// Full-featured notification service with channels, scheduling, grouping,
/// history export, and native platform support.
class NotificationServiceFull {
  final List<AppNotification> _notifications = [];
  final Map<String, Timer> _scheduledTimers = {};
  final StreamController<AppNotification> _streamController =
      StreamController<AppNotification>.broadcast();
  NotificationPreferences _preferences = NotificationPreferences();

  static const int _maxHistory = 500;

  /// Live stream of incoming notifications.
  Stream<AppNotification> get notificationStream => _streamController.stream;

  /// Current preferences.
  NotificationPreferences get preferences => _preferences;

  // -------------------------------------------------------------------------
  // Show
  // -------------------------------------------------------------------------

  /// Displays a notification. Respects DND and channel preferences.
  Future<void> show(AppNotification notification) async {
    // Check DND.
    if (_preferences.isDndActive &&
        notification.priority != NotificationPriority.urgent) {
      // Still store it, but don't push to stream.
      _store(notification);
      return;
    }

    // Check channel.
    if (notification.groupKey != null) {
      final channel = _preferences.channels[notification.groupKey];
      if (channel != null && !channel.enabled) {
        _store(notification);
        return;
      }
    }

    _store(notification);
    _streamController.add(notification);

    // Auto-expire.
    if (notification.expiresAt != null) {
      final delay = notification.expiresAt!.difference(DateTime.now());
      if (delay.isNegative) {
        notification.dismissed = true;
      } else {
        Timer(delay, () => dismiss(notification.id));
      }
    }
  }

  /// Convenience method — creates and shows a simple notification.
  Future<void> showQuick(
    String title, {
    String? body,
    NotificationType type = NotificationType.info,
  }) async {
    final notification = AppNotification(
      id: _generateId(),
      type: type,
      title: title,
      body: body,
    );
    await show(notification);
  }

  /// Shows or updates a progress notification.
  Future<void> showProgress(
    String title,
    double progress, {
    double? total,
  }) async {
    final id = 'progress_${title.hashCode}';

    // Update existing if present.
    final existing = _findById(id);
    if (existing != null) {
      existing.progress = progress;
      existing.progressTotal = total;
      _streamController.add(existing);
      return;
    }

    final notification = AppNotification(
      id: id,
      type: NotificationType.progress,
      title: title,
      progress: progress,
      progressTotal: total,
    );
    await show(notification);
  }

  /// Shows a permission request notification for a tool invocation.
  Future<void> showPermissionRequest(String tool, String input) async {
    final notification = AppNotification(
      id: _generateId(),
      type: NotificationType.permission,
      priority: NotificationPriority.high,
      title: 'Permission Required',
      body: '$tool needs approval',
      metadata: {'tool': tool, 'input': input},
      groupKey: 'permissions',
      actions: [
        const NotificationAction(label: 'Allow', isPrimary: true),
        const NotificationAction(label: 'Deny'),
      ],
    );
    await show(notification);
  }

  // -------------------------------------------------------------------------
  // Dismiss / read
  // -------------------------------------------------------------------------

  /// Dismisses a notification by id.
  void dismiss(String id) {
    final notification = _findById(id);
    if (notification != null) {
      notification.dismissed = true;
    }
  }

  /// Dismisses all notifications.
  void dismissAll() {
    for (final n in _notifications) {
      n.dismissed = true;
    }
  }

  /// Marks a notification as read.
  void markRead(String id) {
    final notification = _findById(id);
    if (notification != null) {
      notification.read = true;
    }
  }

  /// Marks all notifications as read.
  void markAllRead() {
    for (final n in _notifications) {
      n.read = true;
    }
  }

  // -------------------------------------------------------------------------
  // Queries
  // -------------------------------------------------------------------------

  /// Returns notifications filtered by the given criteria.
  List<AppNotification> getNotifications({
    bool unreadOnly = false,
    NotificationType? type,
    DateTime? since,
  }) {
    return _notifications.where((n) {
      if (n.dismissed) return false;
      if (n.isExpired) return false;
      if (unreadOnly && n.read) return false;
      if (type != null && n.type != type) return false;
      if (since != null && n.timestamp.isBefore(since)) return false;
      return true;
    }).toList();
  }

  /// Returns the count of unread, non-dismissed notifications.
  int getUnreadCount() {
    return _notifications
        .where((n) => !n.read && !n.dismissed && !n.isExpired)
        .length;
  }

  // -------------------------------------------------------------------------
  // Preferences
  // -------------------------------------------------------------------------

  /// Replaces the current notification preferences.
  void updatePreferences(NotificationPreferences prefs) {
    _preferences = prefs;
  }

  // -------------------------------------------------------------------------
  // Scheduling
  // -------------------------------------------------------------------------

  /// Schedules a notification for future delivery.
  void scheduleNotification(
    AppNotification notification,
    DateTime scheduledFor,
  ) {
    final delay = scheduledFor.difference(DateTime.now());
    if (delay.isNegative) {
      show(notification);
      return;
    }

    _scheduledTimers[notification.id]?.cancel();
    _scheduledTimers[notification.id] = Timer(delay, () {
      show(notification);
      _scheduledTimers.remove(notification.id);
    });
  }

  /// Cancels a previously scheduled notification.
  void cancelScheduled(String id) {
    _scheduledTimers[id]?.cancel();
    _scheduledTimers.remove(id);
  }

  // -------------------------------------------------------------------------
  // Channels
  // -------------------------------------------------------------------------

  /// Creates or replaces a notification channel.
  void createChannel(NotificationChannel channel) {
    _preferences.channels[channel.id] = channel;
  }

  // -------------------------------------------------------------------------
  // Native notifications
  // -------------------------------------------------------------------------

  /// Sends a native OS notification.
  ///
  /// On macOS uses `osascript`, on Linux uses `notify-send`.
  /// Falls back silently on unsupported platforms.
  Future<void> sendNative(String title, String body) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('osascript', [
          '-e',
          'display notification "$body" with title "$title"',
        ]);
      } else if (Platform.isLinux) {
        await Process.run('notify-send', [title, body]);
      }
      // Windows and others: no-op for now.
    } catch (_) {
      // Best effort.
    }
  }

  // -------------------------------------------------------------------------
  // Grouping
  // -------------------------------------------------------------------------

  /// Groups a list of notifications by their [AppNotification.groupKey].
  /// Notifications without a groupKey are placed under the empty string key.
  Map<String, List<AppNotification>> groupNotifications(
    List<AppNotification> notifications,
  ) {
    final groups = <String, List<AppNotification>>{};
    for (final n in notifications) {
      final key = n.groupKey ?? '';
      groups.putIfAbsent(key, () => []).add(n);
    }
    return groups;
  }

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  /// Exports notification history as JSON or CSV.
  String exportHistory({
    DateTime? since,
    String format = 'json',
  }) {
    final filtered = since != null
        ? _notifications.where((n) => n.timestamp.isAfter(since)).toList()
        : List<AppNotification>.from(_notifications);

    if (format == 'csv') {
      return _exportCsv(filtered);
    }
    return _exportJson(filtered);
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  /// Cancels all timers and closes the stream.
  void dispose() {
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    _streamController.close();
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  void _store(AppNotification notification) {
    _notifications.add(notification);
    // Evict old entries.
    while (_notifications.length > _maxHistory) {
      _notifications.removeAt(0);
    }
  }

  AppNotification? _findById(String id) {
    for (final n in _notifications) {
      if (n.id == id) return n;
    }
    return null;
  }

  String _generateId() =>
      'notif_${DateTime.now().millisecondsSinceEpoch}_'
      '${_notifications.length}';

  String _exportJson(List<AppNotification> items) {
    final list = items.map((n) => {
      'id': n.id,
      'type': n.type.name,
      'priority': n.priority.name,
      'title': n.title,
      'body': n.body,
      'timestamp': n.timestamp.toIso8601String(),
      'read': n.read,
      'dismissed': n.dismissed,
      'groupKey': n.groupKey,
      if (n.metadata.isNotEmpty) 'metadata': n.metadata,
    }).toList();

    return const JsonEncoder.withIndent('  ').convert(list);
  }

  String _exportCsv(List<AppNotification> items) {
    final buf = StringBuffer();
    buf.writeln('id,type,priority,title,body,timestamp,read,dismissed');
    for (final n in items) {
      final body = (n.body ?? '').replaceAll('"', '""');
      final title = n.title.replaceAll('"', '""');
      buf.writeln(
        '${n.id},${n.type.name},${n.priority.name},'
        '"$title","$body",${n.timestamp.toIso8601String()},'
        '${n.read},${n.dismissed}',
      );
    }
    return buf.toString();
  }
}

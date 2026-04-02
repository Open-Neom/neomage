// Notification service — port of openclaude notification system.
// Platform-agnostic notifications with desktop/mobile/web support.

import 'dart:async';

/// Notification priority levels.
enum NotificationPriority { low, normal, high, urgent }

/// Notification action button.
class NotificationAction {
  final String id;
  final String label;
  final void Function()? onPressed;

  const NotificationAction({
    required this.id,
    required this.label,
    this.onPressed,
  });
}

/// A notification to display.
class ClawNotification {
  final String id;
  final String title;
  final String body;
  final NotificationPriority priority;
  final List<NotificationAction> actions;
  final Duration? autoHide;
  final DateTime createdAt;
  final String? category;
  final Map<String, dynamic>? data;

  ClawNotification({
    required this.id,
    required this.title,
    required this.body,
    this.priority = NotificationPriority.normal,
    this.actions = const [],
    this.autoHide,
    this.category,
    this.data,
  }) : createdAt = DateTime.now();
}

/// Notification event.
sealed class NotificationEvent {
  final String notificationId;
  const NotificationEvent(this.notificationId);
}

class NotificationShownEvent extends NotificationEvent {
  const NotificationShownEvent(super.id);
}

class NotificationDismissedEvent extends NotificationEvent {
  const NotificationDismissedEvent(super.id);
}

class NotificationActionEvent extends NotificationEvent {
  final String actionId;
  const NotificationActionEvent(super.id, this.actionId);
}

/// Abstract notification backend.
abstract class NotificationBackend {
  Future<bool> isSupported();
  Future<bool> requestPermission();
  Future<void> show(ClawNotification notification);
  Future<void> dismiss(String notificationId);
  Future<void> dismissAll();
}

/// In-app notification backend (always available).
class InAppNotificationBackend implements NotificationBackend {
  final StreamController<ClawNotification> _notifications =
      StreamController.broadcast();
  final Map<String, ClawNotification> _active = {};

  Stream<ClawNotification> get notifications => _notifications.stream;
  List<ClawNotification> get activeNotifications => _active.values.toList();

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show(ClawNotification notification) async {
    _active[notification.id] = notification;
    _notifications.add(notification);

    if (notification.autoHide != null) {
      Future.delayed(notification.autoHide!, () {
        dismiss(notification.id);
      });
    }
  }

  @override
  Future<void> dismiss(String notificationId) async {
    _active.remove(notificationId);
  }

  @override
  Future<void> dismissAll() async {
    _active.clear();
  }

  void dispose() {
    _notifications.close();
  }
}

/// Notification service — manages notifications across backends.
class NotificationService {
  final List<NotificationBackend> _backends;
  final StreamController<NotificationEvent> _events =
      StreamController.broadcast();
  final List<ClawNotification> _history = [];
  static const _maxHistory = 100;

  NotificationService({List<NotificationBackend>? backends})
      : _backends = backends ?? [InAppNotificationBackend()];

  /// Event stream.
  Stream<NotificationEvent> get events => _events.stream;

  /// Notification history.
  List<ClawNotification> get history => List.unmodifiable(_history);

  /// Show a notification.
  Future<void> notify({
    required String title,
    required String body,
    NotificationPriority priority = NotificationPriority.normal,
    List<NotificationAction> actions = const [],
    Duration? autoHide,
    String? category,
  }) async {
    final notification = ClawNotification(
      id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      priority: priority,
      actions: actions,
      autoHide: autoHide ?? const Duration(seconds: 5),
      category: category,
    );

    _history.add(notification);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }

    for (final backend in _backends) {
      if (await backend.isSupported()) {
        await backend.show(notification);
        _events.add(NotificationShownEvent(notification.id));
      }
    }
  }

  /// Show a tool completion notification.
  Future<void> notifyToolComplete(String toolName, {bool isError = false}) =>
      notify(
        title: isError ? 'Tool Failed' : 'Tool Complete',
        body: toolName,
        priority:
            isError ? NotificationPriority.high : NotificationPriority.low,
        category: 'tool',
      );

  /// Show an agent completion notification.
  Future<void> notifyAgentComplete(String agentId, String description) =>
      notify(
        title: 'Agent Complete',
        body: description,
        category: 'agent',
      );

  /// Show a permission request notification.
  Future<void> notifyPermissionRequired(String toolName) => notify(
        title: 'Permission Required',
        body: '$toolName needs approval',
        priority: NotificationPriority.high,
        category: 'permission',
        autoHide: null, // Don't auto-hide
      );

  /// Dismiss a notification.
  Future<void> dismiss(String notificationId) async {
    for (final backend in _backends) {
      await backend.dismiss(notificationId);
    }
    _events.add(NotificationDismissedEvent(notificationId));
  }

  /// Dismiss all notifications.
  Future<void> dismissAll() async {
    for (final backend in _backends) {
      await backend.dismissAll();
    }
  }

  void dispose() {
    _events.close();
    for (final backend in _backends) {
      if (backend is InAppNotificationBackend) backend.dispose();
    }
  }
}

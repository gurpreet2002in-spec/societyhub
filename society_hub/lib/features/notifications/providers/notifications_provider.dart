import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

// Full notification list
final notificationsProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getNotifications();
});

// Unread count \u2014 polled every time the badge is watched
final unreadCountProvider = FutureProvider<int>((ref) async {
  return ref.read(apiServiceProvider).getUnreadNotificationCount();
});

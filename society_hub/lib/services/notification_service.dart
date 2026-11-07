import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/notifications/providers/notifications_provider.dart';
import '../core/routes/app_router.dart';
import 'api_service.dart';
import 'visitor_call.dart';

// Logs only in debug builds (release builds must not leak message contents).
void _log(String message) {
  if (kDebugMode) debugPrint(message);
}

// ── Background message handler (top-level function required by FCM) ────────
// Called when app is terminated or in background and a message arrives.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  _log('[FCM Background] ${message.notification?.title}: ${message.notification?.body}');
  // Normal notifications are shown by FCM itself. A visitor at the gate comes
  // as a data message so we can show a ringing, full-screen "call" (Android).
  if (message.data['type'] == 'visitor_approval' && !kIsWeb && Platform.isAndroid) {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await showVisitorCall(plugin, Map<String, dynamic>.from(message.data));
  }
}

// ── Riverpod provider ──────────────────────────────────────────────────────
final notificationServiceProvider = Provider((ref) => NotificationService(ref));

// ── Notification channel constants ─────────────────────────────────────────
const _kChannelId   = 'society_hub_alerts';
const _kChannelName = 'SocietyHub Alerts';
const _kChannelDesc = 'Society alerts: visitors, notices, payments & polls';

class NotificationService {
  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  NotificationService(this._ref);

  // Live bell: new rows in `notifications` for the logged-in user.
  RealtimeChannel? _channel;
  String? _channelUser;

  // ── initialize() — called once from main() before runApp ──────────────
  Future<void> initialize() async {
    // 1. Register background handler FIRST (before any other FCM call)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 1b. Keep the in-app bell up to date while the app is open.
    _watchNotifications();

    // 2. Request OS-level notification permission
    await _requestPermissions();

    // 3. Set up flutter_local_notifications (shows heads-up in foreground)
    await _setupLocalNotifications();

    // 4. Create the persistent Android notification channel
    await _createNotificationChannel();

    // 5. iOS: show notification even when app is in foreground
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 6. Hook into FCM message streams
    _setupMessageListeners();

    // 7. Handle tap that opened app from terminated state
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage.data);
    }
  }

  // ── saveFcmTokenForCurrentUser() — call after successful login ─────────
  Future<void> saveFcmTokenForCurrentUser() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _ref.read(apiServiceProvider).updateFcmToken(token);
        _log('[FCM] Token saved to Supabase');
      }
    } catch (e) {
      _log('[FCM] Token save error: $e');
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Listens for new notifications of whoever is logged in and refreshes the
  /// bell list + unread badge immediately. (The tone itself comes from the
  /// push notification, shown by _showLocalNotification when the app is open.)
  void _watchNotifications() {
    try {
      final client = Supabase.instance.client;
      void follow(String? uid) {
        if (uid == _channelUser) return;
        if (_channel != null) {
          client.removeChannel(_channel!);
          _channel = null;
        }
        _channelUser = uid;
        if (uid == null) return;
        _channel = client
            .channel('notifications-$uid')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: uid,
              ),
              callback: (_) {
                _ref.invalidate(notificationsProvider);
                _ref.invalidate(unreadCountProvider);
              },
            )
            .subscribe();
      }

      follow(client.auth.currentUser?.id);
      client.auth.onAuthStateChange.listen((state) => follow(state.session?.user.id));
    } catch (e) {
      _log('[Realtime] Live bell not started: $e');
    }
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    if (Platform.isIOS) {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      // Android 13+ (API 33) requires POST_NOTIFICATIONS at runtime
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _localNotifs.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onLocalNotificationResponse,
    );
    // Visitor "call" channel exists before the first ring.
    await ensureVisitorChannel(_localNotifs);

    // App was opened by tapping a local notification (e.g. the visitor call
    // while the app was closed): open the right screen once the app is up.
    try {
      final launch = await _localNotifs.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        Future.delayed(const Duration(milliseconds: 1500), () => _onLocalNotificationResponse(response));
      }
    } catch (_) {}
  }

  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: _kChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _setupMessageListeners() {
    // App FOREGROUND — show local heads-up notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _log('[FCM Foreground] ${message.notification?.title}');
      if (message.data['type'] == 'visitor_approval') {
        // App is open: ring and go straight to the Approve / Decline screen.
        if (!kIsWeb && Platform.isAndroid) {
          showVisitorCall(_localNotifs, Map<String, dynamic>.from(message.data));
        }
        final id = '${message.data['id'] ?? ''}';
        if (id.isNotEmpty) _openVisitorApproval(id);
        return;
      }
      _showLocalNotification(message);
    });

    // App BACKGROUND — user tapped the notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _log('[FCM Opened from background] ${message.notification?.title}');
      _handleNotificationTap(message.data);
    });

    // FCM token rotated — update in Supabase
    _fcm.onTokenRefresh.listen((token) async {
      _log('[FCM] Token refreshed, saving...');
      try {
        await _ref.read(apiServiceProvider).updateFcmToken(token);
      } catch (_) {}
    });
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final type = message.data['type'] as String? ?? 'general';
    final String body = notification.body ?? '';
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: _kChannelDesc,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifs.show(
      id: notification.hashCode,
      title: notification.title,
      body: body,
      notificationDetails: details,
      payload: type,
    );
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    final id = '${data['id'] ?? ''}';
    if (type == 'visitor_approval' && id.isNotEmpty) {
      _openVisitorApproval(id);
      return;
    }
    _navigateForType(type);
  }

  void _onLocalNotificationResponse(NotificationResponse details) {
    final payload = details.payload ?? '';
    if (payload.startsWith(kVisitorPayloadPrefix)) {
      _openVisitorApproval(payload.substring(kVisitorPayloadPrefix.length), action: details.actionId);
      return;
    }
    _navigateForType(payload);
  }

  void _openVisitorApproval(String visitorId, {String? action}) {
    try {
      final q = (action == 'approve' || action == 'decline') ? '?action=$action' : '';
      _ref.read(appRouterProvider).push('/visitor-approval/$visitorId$q');
    } catch (e) {
      _log('[FCM] Could not open visitor approval: $e');
    }
  }

  /// Stops the ringing alert for a visitor (answered here or by someone else).
  Future<void> cancelVisitorCall(String visitorId) async {
    try {
      await _localNotifs.cancel(id: visitorNotificationId(visitorId));
    } catch (_) {}
  }

  void _navigateForType(String type) {
    try {
      final router = _ref.read(appRouterProvider);
      switch (type) {
        case 'visitor':
          router.push('/visitors');
        case 'payment':
          router.push('/payments');
        case 'notice':
          router.push('/community');
        case 'poll':
          router.push('/community');
        case 'amenity':
          router.push('/amenities');
        case 'approval':
          router.push('/admin/users');
        case 'complaint':
          router.push('/complaints');
        case 'visitor_decision':
          router.push('/guard/dashboard');
        default:
          router.push('/notifications');
      }
    } catch (e) {
      // Router may not be ready on cold start — ignore gracefully
      _log('[FCM] Navigation skipped (cold start): $e');
    }
  }
}

import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// "Visitor at the gate" — a call-style alert: rings (the phone's ringtone, on
// repeat) and opens full screen over the lock screen, with Approve / Decline.
// Used from the background message handler too, so keep it free of app state.

const kVisitorChannelId = 'visitor_calls_v1';
const kVisitorChannelName = 'Visitor at the gate';
const kVisitorChannelDesc = 'Rings when the guard asks you to approve a visitor';
const kVisitorPayloadPrefix = 'visitor_approval|';

final _ringtone = UriAndroidNotificationSound('content://settings/system/ringtone');

/// Stable notification id for a visitor request (so it can be cancelled).
int visitorNotificationId(String visitorId) {
  final hex = visitorId.replaceAll('-', '');
  return int.tryParse(hex.length >= 7 ? hex.substring(0, 7) : hex, radix: 16) ?? visitorId.length;
}

Future<void> ensureVisitorChannel(FlutterLocalNotificationsPlugin plugin) async {
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(AndroidNotificationChannel(
        kVisitorChannelId,
        kVisitorChannelName,
        description: kVisitorChannelDesc,
        importance: Importance.max,
        playSound: true,
        sound: _ringtone,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        enableVibration: true,
        showBadge: true,
      ));
}

Future<void> showVisitorCall(FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> data) async {
  final id = '${data['id'] ?? ''}';
  if (id.isEmpty) return;
  await ensureVisitorChannel(plugin);

  final title = '${data['title'] ?? 'Visitor at the gate'}';
  final who = '${data['name'] ?? 'Someone'}';
  final body = (data['body'] as String?) ?? '$who is at the gate. Approve or decline?';

  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      kVisitorChannelId,
      kVisitorChannelName,
      channelDescription: kVisitorChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      timeoutAfter: 120000, // stop ringing after 2 minutes
      additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT: keep ringing until answered
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      sound: _ringtone,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('decline', 'Decline', showsUserInterface: true, cancelNotification: true),
        AndroidNotificationAction('approve', 'Approve', showsUserInterface: true, cancelNotification: true),
      ],
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );

  await plugin.show(
    id: visitorNotificationId(id),
    title: title,
    body: body,
    notificationDetails: details,
    payload: '$kVisitorPayloadPrefix$id',
  );
}

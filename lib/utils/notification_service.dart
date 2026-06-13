import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'daily_reminder';
  static const _notifId = 1;
  static Future<void> initialize() async {
    tzData.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
  }

  static Future<void> requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      await ios.requestPermissions(alert: true, badge: true, sound: true);
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
    }
  }

  static Future<void> scheduleDailyReminder({
    DateTime? examDate,
    int streak = 0,
    bool enabled = true,
    int hour = 20,
  }) async {
    await _plugin.cancel(_notifId);
    if (!enabled) return;

    final daysLeft = examDate != null
        ? examDate.difference(DateTime.now()).inDays
        : null;

    String body;
    if (daysLeft != null && daysLeft >= 0 && daysLeft <= 60) {
      body = '試験まであと$daysLeft日！毎日の積み重ねが合格への近道です。';
    } else if (streak > 1) {
      body = '$streak日連続学習中！今日も続けよう。';
    } else {
      body = 'スキマ時間で一問一答。今日も合格に近づこう！';
    }

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(sound: 'default'),
      android: AndroidNotificationDetails(
        _channelId,
        '学習リマインダー',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );

    await _plugin.zonedSchedule(
      _notifId,
      '今日も学習しよう！',
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancel() async {
    await _plugin.cancel(_notifId);
  }
}

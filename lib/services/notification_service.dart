import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tzdata.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // শুধু notification permission — exact alarm permission বাদ দিলাম
    await _plugin
        .resolvePlatformSpecificImplementation;
    AndroidFlutterLocalNotificationsPlugin()
        ?.requestNotificationsPermission();
  }

  static Future<void> scheduleDailyNotification({
    required int hour,
    required int minute,
  }) async {
    await _plugin.zonedSchedule(
      0,
      'JOE',
      'Hey, kemon gelo aajker din? 🌙',
      _nextInstanceOfTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_checkin',
          'Daily Check-in',
          channelDescription: 'Daily reminder to chat with JOE',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // exactAllowWhileIdle এর বদলে inexact — exact alarm permission লাগবে না
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
    tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
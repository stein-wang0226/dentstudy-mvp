import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'store.dart';

class Reminders {
  final plugin = FlutterLocalNotificationsPlugin();
  bool ready = false;
  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false)));
    ready = true;
  }

  Future<bool> enable() async {
    if (!ready) await init();
    final android = await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final ios = await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return android ?? ios ?? false;
  }

  Future<void> refresh(StudyStore store) async {
    if (!ready) await init();
    await plugin.cancelAll();
    if (!(store.prefs.getBool('reminders') ?? false)) return;
    final states = store.learning.states.values;
    final now = tz.TZDateTime.now(tz.local);
    for (var i = 0; i < 14; i++) {
      final date =
          tz.TZDateTime(tz.local, now.year, now.month, now.day + i, 20);
      if (!date.isAfter(now)) continue;
      final day =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final count = states
          .where((s) => s.due != null && s.due!.compareTo(day) <= 0)
          .length;
      if (count == 0 && store.remainingNew == 0) continue;
      final reviewGoal =
          store.dailyReviewTarget == null ? '不限' : '${store.dailyReviewTarget}';
      final body = '复习 ${store.todayReviewCount}/$reviewGoal（当前待复习 $count）'
          ' · 新题 ${store.todayNewCount}/${store.dailyNewLimit}';
      await plugin.zonedSchedule(
          i,
          '今日口腔学习进度',
          body,
          date,
          const NotificationDetails(
              android: AndroidNotificationDetails('review', '复习提醒',
                  channelDescription: '每天20点提醒到期复习'),
              iOS: DarwinNotificationDetails()),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }
}

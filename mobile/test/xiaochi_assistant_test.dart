import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
  });

  test('小齿设置只保存本机且不写入学习事件', () async {
    final store = StudyStore();
    await store.init();
    await store.setXiaochiEnabled(false);
    await store.setXiaochiPosition(.28, .64);

    expect(store.events, isEmpty);
    expect(store.pending, isEmpty);
    expect(store.xiaochiEnabled, isFalse);
    expect(store.xiaochiPositionX, .28);
    expect(store.xiaochiPositionY, .64);
    expect(await store.claimXiaochiGreeting(), isTrue);
    expect(await store.claimXiaochiGreeting(), isFalse);

    final restored = StudyStore();
    await restored.init();
    expect(restored.xiaochiEnabled, isFalse);
    expect(restored.xiaochiPositionX, .28);
    expect(restored.xiaochiPositionY, .64);
    expect(restored.events, isEmpty);
  });

  test('小齿开关先通知界面，再写入本机偏好', () async {
    final store = StudyStore();
    await store.init();
    var notifications = 0;
    store.addListener(() => notifications++);

    final saving = store.setXiaochiEnabled(false);

    // The profile switch and floating companion must update in the same frame,
    // rather than waiting for the browser preference write to settle.
    expect(store.xiaochiEnabled, isFalse);
    expect(notifications, 1);
    await saving;
    expect(store.events, isEmpty);
  });

  test('小齿只发送当前消息与有限上下文', () async {
    final store = StudyStore();
    await store.init();
    store.baseUrl = 'https://xiaochi-test.invalid';
    store.token = 'xiaochi-test-token';
    final history = List.generate(
        8,
        (index) => {
              'role': index.isEven ? 'user' : 'assistant',
              'content': '第 $index 条'
            });
    await http.runWithClient(() async {
      final reply =
          await store.chatWithXiaochi(message: '我该怎么复习？', history: history);
      expect(reply, '先完成今天的复习，再做 5 道新题。');
    },
        () => MockClient((request) async {
              expect(request.url.path, '/v1/assistant/chat');
              expect(request.headers['authorization'],
                  'Bearer xiaochi-test-token');
              final payload = jsonDecode(request.body) as Map<String, dynamic>;
              expect(payload['message'], '我该怎么复习？');
              expect((payload['history'] as List).length, 6);
              return http.Response(
                  jsonEncode({'reply': '先完成今天的复习，再做 5 道新题。'}), 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });
}

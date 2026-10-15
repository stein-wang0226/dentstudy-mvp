import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/profile/profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.baseUrl = 'https://account-test.invalid';
    app.store.token = '';
    app.store.userId = 'guest';
    app.store.email = '';
    app.store.questions = [];
    app.store.syncing = false;
  });

  for (final register in [false, true]) {
    testWidgets(
        register
            ? 'new registration offers profile onboarding and can skip'
            : 'existing account login never opens profile onboarding',
        (tester) async {
      final requests = <String>[];
      bool completed = false;
      http.Client client() => MockClient((request) async {
            requests.add(request.url.path);
            final Object data;
            switch (request.url.path) {
              case '/v1/auth/login':
              case '/v1/auth/register':
                data = {
                  'token': 'test-only-token',
                  'email': 'student@example.invalid',
                  'userId': 'test-student'
                };
              case '/v1/sync':
                data = {'events': []};
              case '/v1/profile':
                data = {
                  'nickname': '考研同学',
                  'avatar': 'book',
                  'university': '测试大学'
                };
              default:
                throw StateError('Unexpected request: ${request.url.path}');
            }
            return http.Response(jsonEncode(data), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          });

      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => http.runWithClient(
                          () => showAccountDialog(context,
                              onSuccess: () async => completed = true),
                          client),
                      child: const Text('打开登录'))))));
      await tester.tap(find.text('打开登录'));
      await tester.pumpAndSettle();
      if (register) {
        await tester.tap(find.text('没有账号？注册'));
        await tester.pumpAndSettle();
      }
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'student@example.invalid');
      await tester.enterText(fields.at(1), 'test-password-only');
      if (register) {
        await tester.enterText(fields.at(2), 'test-password-only');
      }
      // Invoke the real submit handler with a scoped mock HTTP client. No real
      // accounts are created and no live user data is read or changed.
      final submit = tester.widget<FilledButton>(find.byType(FilledButton));
      await tester.runAsync(() => http.runWithClient(
          () async => await Function.apply(submit.onPressed!, const []),
          client));
      await tester.pumpAndSettle();
      expect(requests, contains('/v1/auth/${register ? 'register' : 'login'}'));
      if (register) {
        expect(find.text('完善个人资料'), findsOneWidget);
        expect(find.text('考研同学'), findsOneWidget);
        expect(completed, isFalse);
        await tester.tap(find.text('跳过，稍后完善'));
        await tester.pumpAndSettle();
      } else {
        expect(find.text('完善个人资料'), findsNothing);
        expect(requests, isNot(contains('/v1/profile')));
      }
      expect(completed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });
  }
}

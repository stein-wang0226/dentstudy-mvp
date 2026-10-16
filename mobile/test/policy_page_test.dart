import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/profile/policy_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.email = '';
  });

  testWidgets('rules hub keeps privacy and copyright actions discoverable',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PolicyPage()));
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私说明'), findsOneWidget);
    expect(find.text('版权投诉'), findsOneWidget);
    expect(find.text('数据删除申请'), findsOneWidget);

    await tester.tap(find.text('版权投诉'));
    await tester.pumpAndSettle();
    expect(find.text('复制投诉邮件模板'), findsOneWidget);
    expect(find.textContaining('非商业用途不等于可以自由转载'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

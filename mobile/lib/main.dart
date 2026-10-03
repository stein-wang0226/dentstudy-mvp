import 'dart:async';
import 'package:flutter/material.dart';
import 'app/app.dart';
import 'app/shared.dart';
export 'app/app.dart' show DentStudy;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await store.init();
    runApp(const DentStudy());
    unawaited(purchases.init(store));
  } catch (e) {
    runApp(MaterialApp(
        home: Scaffold(
            body: Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('本地数据加载失败，请保留数据并联系维护者。\n$e'))))));
  }
}

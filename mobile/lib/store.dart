import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class StudyStore extends ChangeNotifier {
  late SharedPreferences prefs;
  final secure = const FlutterSecureStorage();
  List<Question> questions = [];
  List<Map<String, dynamic>> events = [];
  List<String> pending = [];
  String mode = '考研', email = '', userId = 'guest', baseUrl = '', token = '';
  int dailyNewLimit = 10;
  int? dailyReviewTarget;
  String settingsUpdatedAt = '1970-01-01T00:00:00.000000Z';
  bool syncing = false;
  String syncMessage = '离线学习 · 记录保存在本机';
  LearningState get learning => LearningState(events, questions);
  List<Question> get bank =>
      questions.where((q) => q.modes.contains(mode)).toList();
  // Review-first is account-wide, including questions from other exam tracks.
  List<Question> get due => learning.due(questions, DateTime.now());
  String get today => dayOf(DateTime.now());
  Set<String> get learnedBeforeToday {
    final result = <String>{};
    for (final event in events) {
      if (event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) != today) {
        result.add(event['questionId'] as String);
      }
    }
    return result;
  }

  Set<String> get answeredToday => events
      .where((event) =>
          event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) == today)
      .map((event) => event['questionId'] as String)
      .toSet();
  int get todayNewCount =>
      answeredToday.where((id) => !learnedBeforeToday.contains(id)).length;
  int get todayReviewCount =>
      answeredToday.where(learnedBeforeToday.contains).length;
  int get remainingNew =>
      (dailyNewLimit - todayNewCount).clamp(0, dailyNewLimit);
  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    mode = prefs.getString('mode') ?? '考研';
    baseUrl = prefs.getString('baseUrl') ??
        const String.fromEnvironment('API_URL',
            defaultValue: 'http://10.0.2.2:8787');
    email = prefs.getString('email') ?? '';
    userId = prefs.getString('userId') ?? 'guest';
    token = await secure.read(key: 'token') ?? '';
    final raw = prefs.getString('bank') ??
        await rootBundle.loadString('assets/questions.json');
    questions = (jsonDecode(raw)['questions'] as List)
        .map((q) => Question(Map<String, dynamic>.from(q)))
        .toList();
    _loadAccount();
  }

  void _loadAccount() {
    final data = jsonDecode(
        prefs.getString('account:$userId') ?? '{"events":[],"pending":[]}');
    events = (data['events'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    pending = List<String>.from(data['pending']);
    final settings = Map<String, dynamic>.from(data['settings'] ?? {});
    dailyNewLimit = settings['dailyNewLimit'] as int? ?? 10;
    dailyReviewTarget = settings['dailyReviewTarget'] as int?;
    settingsUpdatedAt =
        settings['updatedAt'] as String? ?? '1970-01-01T00:00:00.000000Z';
  }

  Future<void> _save() async {
    // One atomic preferences value keeps the event log and upload queue together.
    await prefs.setString(
        'account:$userId',
        jsonEncode({
          'events': events,
          'pending': pending,
          'settings': settingsPayload,
        }));
    notifyListeners();
  }

  Map<String, dynamic> get settingsPayload => {
        'dailyNewLimit': dailyNewLimit,
        'dailyReviewTarget': dailyReviewTarget,
        'updatedAt': settingsUpdatedAt,
      };
  Future<void> setGoals(int newLimit, int? reviewTarget) async {
    if (newLimit < 0 ||
        newLimit > 100 ||
        (reviewTarget != null && (reviewTarget < 0 || reviewTarget > 200))) {
      throw Exception('学习目标超出允许范围');
    }
    dailyNewLimit = newLimit;
    dailyReviewTarget = reviewTarget;
    settingsUpdatedAt = DateTime.now().toUtc().toIso8601String();
    await _save();
    if (token.isNotEmpty) {
      try {
        await sync();
      } catch (_) {/* Saved locally and retried on next sync. */}
    }
  }

  Future<void> setMode(String value) async {
    mode = value;
    await prefs.setString('mode', mode);
    notifyListeners();
  }

  Future<void> add(String questionId, String kind, dynamic value) async {
    await addMany([
      {'questionId': questionId, 'kind': kind, 'value': value}
    ]);
  }

  Future<void> addMany(List<Map<String, dynamic>> additions) async {
    final random = Random.secure();
    for (final addition in additions) {
      final id = List.generate(
              20, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      events.add({
        'id': id,
        'at': DateTime.now().toUtc().toIso8601String(),
        ...addition,
      });
      pending.add(id);
    }
    await _save();
  }

  Future<Map<String, dynamic>> request(String path,
      [Map<String, dynamic>? data]) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty)
      throw Exception('请输入有效的 API 地址');
    if (kReleaseMode && uri.scheme != 'https')
      throw Exception('发行版本必须使用 HTTPS 服务');
    final headers = {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token'
    };
    final response = await (data == null
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(data)))
        .timeout(const Duration(seconds: 15));
    final body = Map<String, dynamic>.from(jsonDecode(response.body));
    if (response.statusCode >= 400) throw Exception(body['error'] ?? '服务暂不可用');
    return body;
  }

  Future<void> login(
      String address, String account, String password, bool register) async {
    if (syncing) throw Exception('请等待当前同步完成');
    baseUrl = address.trim();
    final result = await request('/v1/auth/${register ? 'register' : 'login'}',
        {'email': account, 'password': password});
    token = result['token'];
    email = result['email'];
    userId = result['userId'];
    await secure.write(key: 'token', value: token);
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('email', email);
    await prefs.setString('userId', userId);
    _loadAccount(); // Guest history stays in its own namespace, never silently copied to another account.
    try {
      await sync();
    } catch (_) {
      /* Account is valid; pending data remains available for retry. */
    }
  }

  Future<void> importGuest() async {
    if (userId == 'guest' || syncing) return;
    final guest = (jsonDecode(
                prefs.getString('account:guest') ?? '{"events":[]}')['events']
            as List)
        .map((e) => Map<String, dynamic>.from(e));
    final ids = events.map((e) => e['id']).toSet();
    for (final event in guest) {
      if (ids.add(event['id'])) {
        events.add(event);
        pending.add(event['id']);
      }
    }
    await _save();
    await sync();
  }

  Future<void> logout() async {
    if (syncing) throw Exception('请等待当前同步完成');
    // Revoke remotely first; on failure retain the session so the user can retry.
    await request('/v1/auth/logout', {});
    await secure.delete(key: 'token');
    token = '';
    userId = 'guest';
    email = '';
    await prefs.remove('email');
    await prefs.remove('userId');
    _loadAccount();
    syncMessage = '离线学习 · 记录保存在本机';
    notifyListeners();
  }

  Future<void> sync() async {
    if (token.isEmpty || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      do {
        final ids = pending.take(500).toSet();
        final result = await request('/v1/sync', {
          'events': events.where((e) => ids.contains(e['id'])).toList(),
          'settings': settingsPayload,
        });
        final remote =
            (result['events'] as List).map((e) => Map<String, dynamic>.from(e));
        final merged = {for (final e in events) e['id'] as String: e};
        for (final e in remote) {
          merged[e['id'] as String] = e;
        }
        events = merged.values.toList();
        pending.removeWhere(ids.contains);
        final remoteSettings = result['settings'];
        if (remoteSettings is Map &&
            (remoteSettings['updatedAt'] as String)
                    .compareTo(settingsUpdatedAt) >=
                0) {
          dailyNewLimit = remoteSettings['dailyNewLimit'] as int;
          dailyReviewTarget = remoteSettings['dailyReviewTarget'] as int?;
          settingsUpdatedAt = remoteSettings['updatedAt'] as String;
        }
        await _save();
      } while (pending.isNotEmpty);
      syncMessage = '已同步 · ${dayOf(DateTime.now())}';
    } catch (e) {
      syncMessage = '同步未完成，记录已保留：$e';
      rethrow;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    final result = await request('/v1/questions');
    final updated = (result['questions'] as List)
        .map((q) => Question(Map<String, dynamic>.from(q)))
        .toList();
    // Never discard questions referenced by unsynced or historical events.
    final byId = {
      for (final q in questions) q.id: q,
      for (final q in updated) q.id: q
    };
    questions = byId.values.toList();
    await prefs.setString('bank',
        jsonEncode({'questions': questions.map((q) => q.data).toList()}));
    notifyListeners();
  }
}

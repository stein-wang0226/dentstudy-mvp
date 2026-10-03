import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'features/library/catalog.dart';

class StudyStore extends ChangeNotifier {
  late SharedPreferences prefs;
  final secure = const FlutterSecureStorage();
  List<Question> questions = [];
  List<Map<String, dynamic>> events = [];
  List<String> pending = [];
  Map<String, dynamic>? continuation;
  Map<String, Map<String, dynamic>> drafts = {};
  List<Map<String, dynamic>> sessions = [];
  Map<String, dynamic>? dailyPlan;
  String? activeSessionId;
  Future<void> _writeQueue = Future.value();
  QuestionCatalog get catalog => QuestionCatalog(questions, mode);
  String mode = '考研', email = '', userId = 'guest', baseUrl = '', token = '';
  String themeColorKey = 'teal';
  int dailyNewLimit = 10;
  int? dailyReviewTarget;
  bool isVip = false;
  String settingsUpdatedAt = '1970-01-01T00:00:00.000000Z';
  bool syncing = false;
  String syncMessage = '离线学习 · 记录保存在本机';
  LearningState? _learningCache;
  List<Map<String, dynamic>>? _cachedEvents;
  List<Question>? _cachedQuestions;
  int _cachedCount = -1;
  LearningState get learning {
    if (!identical(_cachedEvents, events) ||
        !identical(_cachedQuestions, questions) ||
        _cachedCount != events.length) {
      _learningCache = LearningState(events, questions);
      _cachedEvents = events;
      _cachedQuestions = questions;
      _cachedCount = events.length;
    }
    return _learningCache!;
  }

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
  int? get dailyPracticeLimit => isVip ? null : 200;
  int get todayPracticeCount => events
      .where((event) =>
          event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) == today)
      .length;
  int? get remainingPractice {
    final limit = dailyPracticeLimit;
    return limit == null ? null : (limit - todayPracticeCount).clamp(0, limit);
  }

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
    isVip = prefs.getBool('vipEntitled') ?? false;
    themeColorKey = prefs.getString('themeColorKey') ?? 'teal';
    const bankAsset = String.fromEnvironment('QUESTION_BANK_ASSET',
        defaultValue: 'assets/all_questions.json');
    final raw = await rootBundle.loadString(bankAsset);
    questions = (jsonDecode(raw)['questions'] as List)
        .map((q) => Question(Map<String, dynamic>.from(q)))
        .toList();
    final cached = prefs.getString('bank');
    if (cached != null) {
      try {
        final updates = (jsonDecode(cached)['questions'] as List)
            .map((q) => Question(Map<String, dynamic>.from(q)));
        questions = {
          for (final q in questions) q.id: q,
          for (final q in updates) q.id: q
        }.values.toList();
      } catch (_) {/* Keep the bundled bank if an old cache is invalid. */}
    }
    _loadAccount();
  }

  void _loadAccount() {
    final data = jsonDecode(
        prefs.getString('account:$userId') ?? '{"events":[],"pending":[]}');
    events = (data['events'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    pending = List<String>.from(data['pending']);
    final savedContinuation = data['continuation'];
    continuation = savedContinuation is Map
        ? Map<String, dynamic>.from(savedContinuation)
        : null;
    drafts = (data['drafts'] as Map? ?? {})
        .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v)));
    sessions = (data['sessions'] as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    dailyPlan = data['dailyPlan'] is Map
        ? Map<String, dynamic>.from(data['dailyPlan'])
        : null;
    // Older builds saved only the remaining IDs. Preserve those IDs without
    // inventing the answers or elapsed time they never recorded.
    if (continuation != null && !drafts.containsKey('legacy')) {
      drafts['legacy'] = {
        ...continuation!,
        'id': 'legacy',
        'legacy': true,
        'answers': <String, String>{},
        'saved': <String>[],
        'index': 0
      };
      continuation = null;
    }
    final settings = Map<String, dynamic>.from(data['settings'] ?? {});
    dailyNewLimit = settings['dailyNewLimit'] as int? ?? 10;
    dailyReviewTarget = settings['dailyReviewTarget'] as int?;
    settingsUpdatedAt =
        settings['updatedAt'] as String? ?? '1970-01-01T00:00:00.000000Z';
  }

  Future<void> _save() async {
    // One atomic preferences value keeps the event log and upload queue together.
    final key = 'account:$userId';
    final payload = jsonEncode({
      'events': events,
      'pending': pending,
      if (continuation != null) 'continuation': continuation,
      'settings': settingsPayload,
      'drafts': drafts,
      'sessions': sessions,
      'dailyPlan': dailyPlan,
    });
    final write = _writeQueue.then((_) async {
      if (!await prefs.setString(key, payload)) throw Exception('本机存储失败');
    });
    _writeQueue = write.catchError((_) {});
    await write;
    notifyListeners();
  }

  List<Question> resolveQuestions(Iterable<dynamic> ids) {
    final byId = {for (final q in questions) q.id: q};
    return ids.map((id) => byId[id]).whereType<Question>().toList();
  }

  Future<void> saveDraft(Map<String, dynamic> value) async {
    drafts[value['id'] as String] = value;
    await _save();
  }

  Future<void> finishSession(String id, Map<String, dynamic> summary) async {
    drafts.remove(id);
    sessions.removeWhere((s) => s['id'] == id);
    sessions.add(summary);
    await _save();
  }

  Future<void> savePlan(Map<String, dynamic> plan) async {
    dailyPlan = plan;
    await _save();
  }

  Map<String, dynamic> get settingsPayload => {
        'dailyNewLimit': dailyNewLimit,
        'dailyReviewTarget': dailyReviewTarget,
        'updatedAt': settingsUpdatedAt,
      };

  List<Question> get continuationQuestions {
    final ids = continuation?['questionIds'];
    if (ids is! List) return [];
    final byId = {for (final question in questions) question.id: question};
    return ids
        .whereType<String>()
        .map((id) => byId[id])
        .whereType<Question>()
        .toList();
  }

  Future<void> saveContinuation({
    required List<Question> questions,
    required String practiceMode,
    required String kind,
  }) async {
    if (questions.isEmpty) return;
    continuation = {
      'questionIds': questions.map((question) => question.id).toList(),
      'practiceMode': practiceMode,
      'kind': kind,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _save();
  }

  Future<void> clearContinuation() async {
    if (continuation == null) return;
    continuation = null;
    await _save();
  }

  Future<void> setGoals(int newLimit, int? reviewTarget) async {
    if (newLimit < 0 ||
        newLimit > 1000000 ||
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

  Future<void> setThemeColor(String value) async {
    themeColorKey = value;
    await prefs.setString('themeColorKey', value);
    notifyListeners();
  }

  Future<void> add(String questionId, String kind, dynamic value) async {
    await addMany([
      {'questionId': questionId, 'kind': kind, 'value': value}
    ]);
  }

  Future<void> addMany(List<Map<String, dynamic>> additions) async {
    if (activeSessionId != null) {
      final freshIds = additions
          .where((a) =>
              a['kind'] == 'review' &&
              a['value']?['mode'] != 'exam' &&
              learning.states[a['questionId']]?.lastDay == null)
          .map((a) => a['questionId'])
          .toSet();
      if (freshIds.isNotEmpty && due.isNotEmpty)
        throw Exception('有到期复习题，请返回今日先完成复习；当前作答已保留。');
      if (freshIds.length > remainingNew) throw Exception('今日新题目标已完成，当前作答已保留。');
    }
    final reviewCount =
        additions.where((addition) => addition['kind'] == 'review').length;
    final remaining = remainingPractice;
    if (remaining != null && reviewCount > remaining) {
      throw Exception(
          isVip ? 'VIP 不设每日刷题上限' : '今日免费刷题量已达到 200 道，升级 VIP 后可不限量刷题');
    }
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
      final localSession = drafts[activeSessionId] ??
          sessions.where((s) => s['id'] == activeSessionId).firstOrNull;
      if (addition['kind'] == 'review' && localSession != null) {
        final draft = localSession;
        draft['saved'] = <String>{
          ...List<String>.from(draft['saved'] ?? []),
          addition['questionId'] as String
        }.toList();
        draft['eventIds'] = [...List<String>.from(draft['eventIds'] ?? []), id];
        draft['answers'] = {
          ...Map<String, dynamic>.from(draft['answers'] ?? {}),
          addition['questionId']: addition['value']['answer']
        };
      }
    }
    await _save();
  }

  Future<void> activateVip(String purchaseId) async {
    isVip = true;
    await prefs.setBool('vipEntitled', true);
    await secure.write(key: 'vipPurchaseId', value: purchaseId);
    notifyListeners();
  }

  Future<Map<String, dynamic>> request(String path,
      [Map<String, dynamic>? data]) async {
    final configuredBase = baseUrl.trim();
    final relativeBase = configuredBase.startsWith('/');
    final uri = relativeBase
        ? Uri.base
            .resolve('${configuredBase.replaceAll(RegExp(r'/+$'), '')}$path')
        : Uri.parse('${configuredBase.replaceAll(RegExp(r'/+$'), '')}$path');
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty)
      throw Exception('请输入有效的 API 地址');
    if (kReleaseMode && uri.scheme != 'https' && !relativeBase)
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

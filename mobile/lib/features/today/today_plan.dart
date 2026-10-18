import 'dart:math';
import '../../store.dart';
import '../../models.dart';

class TodayPlan {
  static const _strategy = 'independent-new-v1';
  final StudyStore store;
  TodayPlan(this.store);
  Future<void> ensure({bool next = false}) async {
    final current = store.dailyPlan;
    if (!next &&
        current?['day'] == store.today &&
        current?['mode'] == store.mode &&
        current?['bankSize'] == store.questions.length &&
        current?['settingsAt'] == store.settingsUpdatedAt &&
        current?['strategy'] == _strategy) return;
    final state = store.learning;
    // New study and review are deliberately independent: a due review is a
    // strong reminder, never a lock that prevents the learner from opening
    // today's fresh-question plan.
    final newCount = min(store.remainingNew, store.remainingPractice);
    final fresh = store.catalog.learnable
        .where((q) => state.states[q.id]?.lastDay == null)
        .take(newCount)
        .toList();
    await store.savePlan({
      'day': store.today,
      'mode': store.mode,
      'bankSize': store.questions.length,
      'settingsAt': store.settingsUpdatedAt,
      'strategy': _strategy,
      'reviewIds': const <String>[],
      'newIds': fresh.map((q) => q.id).toList()
    });
  }

  List<Question> _questions(String key) =>
      store.resolveQuestions(store.dailyPlan?[key] as List? ?? []);
  List<Question> get reviews => _questions('reviewIds');
  List<Question> get fresh => _questions('newIds');
  List<Question> get remainingReviews {
    final dueIds = store.due.map((q) => q.id).toSet();
    return reviews.where((q) => dueIds.contains(q.id)).toList();
  }

  List<Question> get remainingNew =>
      fresh.where((q) => store.learning.states[q.id]?.lastDay == null).toList();
  int get total => reviews.length + fresh.length;
  int get completed => total - remainingReviews.length - remainingNew.length;
  int get minutes =>
      ((remainingReviews.length + remainingNew.length) * 1.5).ceil();
}

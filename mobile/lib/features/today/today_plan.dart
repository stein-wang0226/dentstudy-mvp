import 'dart:math';
import '../../store.dart';
import '../../models.dart';

class TodayPlan {
  final StudyStore store;
  TodayPlan(this.store);
  Future<void> ensure({bool next = false}) async {
    final current = store.dailyPlan;
    if (!next &&
        current?['day'] == store.today &&
        current?['mode'] == store.mode &&
        current?['bankSize'] == store.questions.length &&
        current?['settingsAt'] == store.settingsUpdatedAt) return;
    final state = store.learning;
    final quota = store.remainingPractice ?? 200;
    final due = store.due;
    final reviewLimit =
        store.dailyReviewTarget == null || store.dailyReviewTarget == 0
            ? 20
            : store.dailyReviewTarget!;
    final reviews = due.take(min(quota, min(reviewLimit, 20))).toList();
    final newCount =
        min(10, min(store.remainingNew, max(0, quota - reviews.length)));
    final fresh = store.catalog.learnable
        .where((q) => state.states[q.id]?.lastDay == null)
        .take(due.length > reviews.length ? 0 : newCount)
        .toList();
    await store.savePlan({
      'day': store.today,
      'mode': store.mode,
      'bankSize': store.questions.length,
      'settingsAt': store.settingsUpdatedAt,
      'reviewIds': reviews.map((q) => q.id).toList(),
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

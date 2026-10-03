import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../models.dart';
import '../practice/practice_request.dart';
import '../statistics/learning_metrics.dart';
import 'today_plan.dart';

class TodayPage extends StatelessWidget {
  final TodayPlan plan;
  final VoidCallback onPlan, onCustom;
  final void Function(Map<String, dynamic>) onResume;
  final StartPractice onStart;
  const TodayPage(
      {super.key,
      required this.plan,
      required this.onPlan,
      required this.onCustom,
      required this.onResume,
      required this.onStart});
  @override
  Widget build(BuildContext context) {
    final metrics = LearningMetrics(store.learning, store.questions);
    final recentWrong = store.questions
        .where((q) => store.learning.states[q.id]?.wrong == true)
        .toList()
      ..sort((a, b) => (store.learning.states[b.id]?.lastDay ?? '')
          .compareTo(store.learning.states[a.id]?.lastDay ?? ''));
    final drafts = store.drafts.values.toList()
      ..sort((a, b) => (b['savedAt'] as String? ?? '')
          .compareTo(a['savedAt'] as String? ?? ''));
    final hasPlanDraft = drafts.any((d) => d['kind'] == 'today');
    final completedToday = store.answeredToday.length;
    final todayTotal = completedToday +
        plan.remainingReviews.length +
        plan.remainingNew.length;
    return PageBody(children: [
      heading('今天，学一点，记牢一点。', sub: store.catalog.countLabel),
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('今日计划', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('连续学习 ${metrics.streak} 天', style: const TextStyle(fontSize: 12))
        ]),
        const SizedBox(height: 22),
        Text(
            '待复习 ${plan.remainingReviews.length} 题 · 新题 ${plan.remainingNew.length} 题',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text('今日已完成 $completedToday / $todayTotal 题 · 预计还需 ${plan.minutes} 分钟'),
        const SizedBox(height: 14),
        Semantics(
            container: true,
            child: LinearProgressIndicator(
                value: todayTotal == 0 ? 0 : completedToday / todayTotal,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 22),
        SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
                onPressed: plan.total == 0 && !hasPlanDraft ? null : onPlan,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                    hasPlanDraft || plan.completed > 0 ? '继续今日计划' : '开始今日计划'))),
        const SizedBox(height: 10),
        Text(
            plan.remainingReviews.isNotEmpty
                ? '先复习，再进入新题。'
                : plan.remainingNew.isNotEmpty
                    ? '开始学习 ${plan.remainingNew.length} 道新题'
                    : plan.total > 0
                        ? '本轮计划已完成，可继续下一轮。'
                        : store.remainingPractice == 0
                            ? '今日练习额度已用完。'
                            : store.catalog.learnable.isEmpty
                                ? '当前方向题库建设中，可切换学习方向。'
                                : '今日新题目标已完成。',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ])),
      const SizedBox(height: 12),
      OutlinedButton.icon(
          onPressed: onCustom,
          icon: const Icon(Icons.tune),
          label: const Text('自定义练习')),
      for (final draft in drafts) ...[
        const SizedBox(height: 12),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(draft['label'] as String? ?? '上次练习'),
          Text('剩余 ${_remaining(draft)} 题 · ${{
                'deep': '逐题深度',
                'batch': '批量练习',
                'speed': '速刷'
              }[draft['practiceMode']] ?? '练习'}'),
          if (draft['legacy'] == true)
            const Text('旧版记录仅保留题目，答案未记录。', style: TextStyle(fontSize: 12)),
          TextButton.icon(
              onPressed: () => onResume(draft),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('继续上次练习'))
        ])),
      ],
      heading('待复习提醒'),
      Text(store.due.isEmpty
          ? '今天没有到期题，按计划学习新题即可。'
          : '共 ${store.due.length} 道到期题，本轮安排 ${plan.remainingReviews.length} 道。完成后继续下一轮。'),
      heading('最近错题'),
      if (recentWrong.isEmpty)
        const Text('暂无错题。完成练习后会自动归集。')
      else
        for (final q in recentWrong.take(3))
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(q.stem, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${q.subject} · ${q.chapter}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  onStart(PracticeRequest([q], review: true, label: '错题巩固'))),
      heading('薄弱章节'),
      if (metrics.weakChapters.isEmpty)
        const Text('完成一些练习后，这里会出现章节建议。')
      else
        for (final qs in metrics.weakChapters.take(2)) _suggestion(qs, metrics),
    ]);
  }

  int _remaining(Map<String, dynamic> d) {
    final ids = Set<String>.from(d['questionIds'] ?? []);
    ids.removeAll(List<String>.from(d['saved'] ?? []));
    return ids.length;
  }

  Widget _suggestion(List<Question> qs, LearningMetrics m) {
    final wrong =
        qs.where((q) => store.learning.states[q.id]?.wrong == true).toList();
    return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${qs.first.subject} · ${qs.first.chapter}'),
        subtitle: Text(
            '正确率 ${LearningMetrics.percent(m.accuracy(qs))}，建议${wrong.isEmpty ? '复习已学题目' : '先完成 ${wrong.length} 道错题巩固'}。'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => onStart(PracticeRequest(
            wrong.isEmpty
                ? qs
                    .where((q) => store.learning.states[q.id]?.lastDay != null)
                    .toList()
                : wrong,
            review: true,
            label: '${qs.first.chapter} · 巩固')));
  }
}

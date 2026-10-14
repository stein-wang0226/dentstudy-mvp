import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../models.dart';
import '../compliance/filing_footer.dart';
import '../practice/practice_request.dart';
import '../statistics/learning_metrics.dart';
import 'today_plan.dart';

class TodayPage extends StatelessWidget {
  final TodayPlan plan;
  final VoidCallback onPlan, onCustom;
  final void Function(Map<String, dynamic>) onResume;
  final Future<void> Function(String mode) onModeChanged;
  final StartPractice onStart;
  const TodayPage(
      {super.key,
      required this.plan,
      required this.onPlan,
      required this.onCustom,
      required this.onResume,
      required this.onModeChanged,
      required this.onStart});
  @override
  Widget build(BuildContext context) {
    final metrics = LearningMetrics(store.learning, store.questions);
    final activeMistakes = metrics.activeMistakes(store.questions);
    final recentWrong = [...activeMistakes]..sort((a, b) =>
        (store.learning.states[b.id]?.lastDay ?? '')
            .compareTo(store.learning.states[a.id]?.lastDay ?? ''));
    final justWrong = activeMistakes.where(metrics.isWrongToday).toList();
    final repeated = activeMistakes
        .where((q) => !metrics.isWrongToday(q) && metrics.isRepeatedMistake(q))
        .toList();
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
      Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: teal.withAlpha(12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: teal.withAlpha(24))),
          child: Row(children: [
            Icon(Icons.verified_user_outlined, size: 17, color: teal),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('本网站无任何商业用途，请放心使用。',
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey)))
          ])),
      const SizedBox(height: 12),
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('今日计划',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('连续学习 ${metrics.streak} 天', style: const TextStyle(fontSize: 12))
        ]),
        Align(
            alignment: Alignment.centerRight,
            child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                    value: store.mode,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: ['考研', '本科期末', '执医']
                        .map((mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))))
                        .toList(),
                    onChanged: (mode) {
                      if (mode != null) onModeChanged(mode);
                    }))),
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
      if (justWrong.isNotEmpty || repeated.isNotEmpty) ...[
        heading('优先订正', sub: '先把刚错和反复错的知识点补牢，再扩展新题'),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${justWrong.isNotEmpty ? '今日刚错 ${justWrong.length} 题' : ''}${justWrong.isNotEmpty && repeated.isNotEmpty ? ' · ' : ''}${repeated.isNotEmpty ? '反复错 ${repeated.length} 题' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 7),
          const Text('反复错题会优先出现在错题本和今日建议中；完成订正后仍按原有间隔复习安排。',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 10),
          TextButton.icon(
              onPressed: () => onStart(PracticeRequest(
                  [...justWrong, ...repeated].take(10).toList(),
                  review: true,
                  label: '优先订正 · 错题巩固')),
              icon: const Icon(Icons.replay_circle_filled_outlined),
              label: Text(
                  '开始订正 ${[...justWrong, ...repeated].take(10).length} 题')),
        ])),
      ],
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
              subtitle: Text(
                  '${q.subject} · ${q.chapter} · ${_mistakeLabel(q, metrics)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  onStart(PracticeRequest([q], review: true, label: '错题巩固'))),
      heading('薄弱章节'),
      if (metrics.weakChapters.isEmpty)
        const Text('完成一些练习后，这里会出现章节建议。')
      else
        for (final qs in metrics.weakChapters.take(2)) _suggestion(qs, metrics),
      const FilingFooter(),
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
            '${qs.first.subject}${qs.first.chapter}正确率 ${LearningMetrics.percent(m.accuracy(qs))}，${wrong.isEmpty ? '建议复习已学题目，巩固当前掌握度。' : '建议先完成 ${wrong.length} 道错题巩固。'}'),
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

  String _mistakeLabel(Question question, LearningMetrics metrics) {
    if (metrics.isWrongToday(question)) return '今日刚错，优先订正';
    final count = metrics.wrongAttempts(question);
    return count >= 2 ? '已错 $count 次，重点巩固' : '待巩固';
  }
}

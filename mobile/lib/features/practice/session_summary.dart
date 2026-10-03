import 'package:flutter/material.dart';
import '../../app/shared.dart' show box, heading, safely;
import '../statistics/learning_metrics.dart';
import 'session_journal.dart';

enum PracticeAction { mistakes, next, home }

class SessionSummary extends StatelessWidget {
  final SessionJournal journal;
  const SessionSummary({super.key, required this.journal});
  @override
  Widget build(BuildContext context) {
    final store = journal.store;
    final recorded =
        store.sessions.where((s) => s['id'] == journal.id).firstOrNull ??
            journal.data;
    final ids = Set<String>.from(recorded['eventIds'] ?? []);
    final attempts =
        store.learning.attempts.where((a) => ids.contains(a['id'])).toList();
    final objective = attempts.where((a) => a['correct'] != null).toList();
    final wrongIds = attempts
        .where((a) => a['correct'] == false || a['grade'] == 'wrong')
        .map((a) => a['questionId'])
        .toSet();
    final completed = attempts.map((a) => a['questionId']).toSet().length;
    final groups = <String, List<Map<String, dynamic>>>{};
    final byId = {for (final q in journal.questions) q.id: q};
    for (final a in objective) {
      final q = byId[a['questionId']];
      if (q != null)
        groups.putIfAbsent('${q.subject} · ${q.chapter}', () => []).add(a);
    }
    final dates = journal.questions
        .map((q) => store.learning.states[q.id]?.due)
        .whereType<String>()
        .toList()
      ..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading('本次练习完成', sub: journal.data['label'] as String? ?? '练习'),
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('完成 $completed 题',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(
            '客观题正确率 ${LearningMetrics.percent(objective.isEmpty ? null : objective.where((a) => a['correct'] == true).length / objective.length)} · 错题 ${wrongIds.length} 题'),
        Text('学习用时 ${journal.seconds ~/ 60} 分 ${journal.seconds % 60} 秒'),
        if (journal.data['legacy'] == true) const Text('旧版未记录的答案和用时不计入本次统计。'),
        const SizedBox(height: 12),
        Text(dates.isEmpty
            ? '当前待复习 ${store.due.length} 题'
            : '下次复习：${dates.first} · 当前到期 ${store.due.length} 题'),
      ])),
      heading('本次薄弱章节'),
      if (!groups.values.any(
          (a) => a.where((v) => v['correct'] == true).length / a.length < .8))
        const Text('本次暂无低于 80% 的客观题章节。')
      else
        for (final e in groups.entries)
          if (e.value.where((a) => a['correct'] == true).length /
                  e.value.length <
              .8)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.key),
                subtitle: Text(
                    '正确率 ${LearningMetrics.percent(e.value.where((a) => a['correct'] == true).length / e.value.length)} · 本次 ${e.value.length} 次作答')),
      const SizedBox(height: 24),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton(
            onPressed: wrongIds.isEmpty
                ? null
                : () => _act(context, PracticeAction.mistakes),
            child: Text('复习错题 ${wrongIds.length}')),
        FilledButton(
            onPressed: () => _act(context, PracticeAction.next),
            child: const Text('继续学习')),
        TextButton(
            onPressed: () => _act(context, PracticeAction.home),
            child: const Text('返回今日')),
      ])
    ]);
  }

  void _act(BuildContext context, PracticeAction action) =>
      safely(context, () async {
        await journal.finish();
        if (context.mounted) Navigator.pop(context, action);
      });
}

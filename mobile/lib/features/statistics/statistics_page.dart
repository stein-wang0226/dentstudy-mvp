import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../models.dart';
import '../practice/practice_request.dart';
import 'learning_metrics.dart';

class StatisticsPage extends StatelessWidget {
  final StartPractice onStart;
  const StatisticsPage({super.key, required this.onStart});
  @override
  Widget build(BuildContext context) {
    final state = store.learning;
    final metrics = LearningMetrics(state, store.questions);
    final today = DateTime.parse(store.today);
    final monday = today
        .subtract(Duration(days: today.weekday - 1))
        .toIso8601String()
        .substring(0, 10);
    final weekly = state.attempts
        .where((a) => dayOf(DateTime.parse(a['at'])).compareTo(monday) >= 0)
        .toList();
    final objective = weekly.where((a) => a['correct'] != null).toList();
    final times = [...store.sessions, ...store.drafts.values]
        .where((s) =>
            s['startedAt'] != null &&
            dayOf(DateTime.parse(s['startedAt'])).compareTo(monday) >= 0)
        .toList();
    final seconds = times.fold<int>(
        0, (sum, s) => sum + (s['elapsedSeconds'] as int? ?? 0));
    final days = List.generate(
        7,
        (i) => today
            .subtract(Duration(days: 6 - i))
            .toIso8601String()
            .substring(0, 10));
    final counts = days
        .map((d) => state.attempts
            .where((a) => dayOf(DateTime.parse(a['at'])) == d)
            .map((a) => a['questionId'])
            .toSet()
            .length)
        .toList();
    final maximum = counts.fold<int>(0, max);
    return PageBody(children: [
      heading('学习看得见', sub: '本周按北京时间周一开始 · 跨学习方向统计'),
      box(Wrap(spacing: 24, runSpacing: 18, children: [
        _metric(
            '${weekly.map((a) => a['questionId']).toSet().length}', '本周题数（去重）'),
        _metric(
            LearningMetrics.percent(objective.isEmpty
                ? null
                : objective.where((a) => a['correct'] == true).length /
                    objective.length),
            '客观题正确率（按次）'),
        _metric(times.isEmpty ? '未记录' : '${seconds ~/ 60}分${seconds % 60}秒',
            '本周本机会话用时'),
        _metric('${metrics.streak} 天', '连续学习'),
      ])),
      const SizedBox(height: 8),
      const Text('用时从新版开始记录，按会话开始日期归属；旧记录与其他设备用时未计入。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
      heading('近 7 天'),
      if (maximum == 0)
        box(const Column(children: [
          Icon(Icons.bar_chart_rounded, size: 40),
          SizedBox(height: 12),
          Text('近 7 天还没有作答记录'),
          Text('完成一次练习后，这里会显示每天学过的题数。')
        ]))
      else
        box(SizedBox(
            height: 160,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                      Text('${counts[i]}'),
                      const SizedBox(height: 6),
                      Container(
                          height: 100 * counts[i] / maximum,
                          width: 20,
                          decoration: BoxDecoration(
                              color: teal.withAlpha(i == 6 ? 255 : 95),
                              borderRadius: BorderRadius.circular(5))),
                      const SizedBox(height: 6),
                      Text(days[i].substring(5),
                          style: const TextStyle(fontSize: 10))
                    ]))
            ]))),
      heading('薄弱章节', sub: '已作答客观题正确率低于 80% · 小样本仅供参考'),
      if (metrics.weakChapters.isEmpty)
        const Text('暂无薄弱章节，完成练习后会生成建议。')
      else
        for (final qs in metrics.weakChapters)
          Card(
              child: ListTile(
                  title: Text('${qs.first.subject} · ${qs.first.chapter}'),
                  subtitle: Text(
                      '正确率 ${LearningMetrics.percent(metrics.accuracy(qs))} · ${metrics.attemptsFor(qs).length} 次作答\n'
                      '${metrics.wrong(qs) > 0 ? '建议先完成 ${metrics.wrong(qs)} 道错题巩固' : '建议复习本章已学题目'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _chapter(context, qs, metrics))),
    ]);
  }

  Widget _metric(String value, String label) => SizedBox(
      width: 150,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: teal)),
        Text(label, style: const TextStyle(fontSize: 12))
      ]));
  void _chapter(
      BuildContext context, List<Question> qs, LearningMetrics metrics) {
    final wrong =
        qs.where((q) => store.learning.states[q.id]?.wrong == true).toList();
    final learned =
        qs.where((q) => store.learning.states[q.id]?.lastDay != null).toList();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading(qs.first.chapter, sub: qs.first.subject),
                      Text(
                          '已学 ${metrics.learned(qs)} / ${qs.length} · 错题 ${wrong.length} · 待复习 ${metrics.due(qs)}'),
                      Text('最近学习：${metrics.lastDay(qs)}'),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: () {
                            Navigator.pop(c);
                            onStart(PracticeRequest(
                                wrong.isEmpty ? learned : wrong,
                                review: true,
                                label: '${qs.first.chapter} · 巩固'));
                          },
                          child: Text(wrong.isEmpty
                              ? '复习已学题目'
                              : '巩固 ${wrong.length} 道错题'))
                    ]))));
  }
}

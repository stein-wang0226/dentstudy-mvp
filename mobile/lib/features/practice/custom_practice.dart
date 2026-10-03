import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/shared.dart';
import 'practice_request.dart';

Future<PracticeRequest?> choosePractice(BuildContext context) =>
    showModalBottomSheet<PracticeRequest>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const CustomPractice());

class CustomPractice extends StatefulWidget {
  const CustomPractice({super.key});
  @override
  State<CustomPractice> createState() => _CustomPracticeState();
}

class _CustomPracticeState extends State<CustomPractice> {
  String subject = '全部', chapter = '全部', mode = 'deep';
  int count = 10;
  bool random = false;
  @override
  Widget build(BuildContext context) {
    final catalog = store.catalog;
    final qs = catalog.learnable
        .where((q) =>
            (subject == '全部' || q.subject == subject) &&
            (chapter == '全部' || q.chapter == chapter))
        .toList();
    final state = store.learning;
    var newSlots = store.due.isEmpty ? store.remainingNew : 0;
    final eligible =
        qs.where((q) => (mode != 'speed' || q.answer != null)).where((q) {
      if (state.states[q.id]?.lastDay != null) return true;
      if (newSlots <= 0) return false;
      newSlots--;
      return true;
    }).length;
    final actual = min(count, min(eligible, store.remainingPractice ?? count));
    return SafeArea(
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 10, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading('自定义练习', sub: catalog.countLabel),
                  _select(
                      '学科',
                      subject,
                      ['全部', ...catalog.subjects.where(catalog.available)],
                      (v) => setState(() {
                            subject = v;
                            chapter = '全部';
                          })),
                  const SizedBox(height: 12),
                  _select(
                      '章节',
                      chapter,
                      [
                        '全部',
                        ...catalog.learnable
                            .where(
                                (q) => subject == '全部' || q.subject == subject)
                            .map((q) => q.chapter)
                            .toSet()
                      ],
                      (v) => setState(() => chapter = v)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: [
                    for (final n in [10, 20, 50, 100])
                      ChoiceChip(
                          label: Text('$n 题'),
                          selected: count == n,
                          onSelected: (_) => setState(() => count = n))
                  ]),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('随机抽题'),
                      value: random,
                      onChanged: (v) => setState(() => random = v)),
                  for (final entry in {
                    'deep': '逐题深度 · 每题解析与评级',
                    'batch': '批量练习 · 完成后统一解析',
                    'speed': '速刷 · 答对自动下一题'
                  }.entries)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(mode == entry.key
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off),
                        title: Text(entry.value),
                        onTap: () => setState(() => mode = entry.key)),
                  Text('本次可练 $actual 题 · 预计 ${(actual * 1.5).ceil()} 分钟',
                      style: const TextStyle(color: Colors.blueGrey)),
                  if (store.due.isNotEmpty)
                    const Text('有到期复习时，自定义练习仅安排已学题。',
                        style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: actual == 0
                              ? null
                              : () {
                                  final candidates = [
                                    ...qs.where((q) =>
                                        mode != 'speed' || q.answer != null)
                                  ];
                                  if (random) candidates.shuffle(Random());
                                  var slots = store.due.isEmpty
                                      ? store.remainingNew
                                      : 0;
                                  final selected = candidates
                                      .where((q) {
                                        if (state.states[q.id]?.lastDay != null)
                                          return true;
                                        if (slots == 0) return false;
                                        slots--;
                                        return true;
                                      })
                                      .take(actual)
                                      .toList();
                                  Navigator.pop(
                                      context,
                                      PracticeRequest(selected,
                                          mode: mode,
                                          kind: random ? 'random' : 'custom',
                                          label:
                                              '$subject · $chapter${random ? ' · 随机' : ''}'));
                                },
                          child: Text('开始 $actual 题'))),
                ])));
  }

  Widget _select(String label, String value, List<String> values,
          ValueChanged<String> change) =>
      DropdownButtonFormField<String>(
          key: ValueKey('$label:$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: values
              .map((s) => DropdownMenuItem(
                  value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) {
            if (v != null) change(v);
          });
}

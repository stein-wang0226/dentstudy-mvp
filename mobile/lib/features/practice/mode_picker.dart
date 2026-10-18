import 'package:flutter/material.dart';
import '../../app/motion.dart';

Future<String?> chooseStudyMode(BuildContext context,
    {required bool review, required int count, String? helpText}) {
  var resolved = false;
  void finish(BuildContext dialogContext, [String? value]) {
    if (resolved || ModalRoute.of(dialogContext)?.isCurrent != true) return;
    resolved = true;
    Navigator.pop(dialogContext, value);
  }

  return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭模式选择',
      barrierColor: Colors.black.withAlpha(65),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      transitionBuilder: (context, animation, secondary, child) =>
          MotionReveal(animation: animation, child: child),
      pageBuilder: (context, animation, secondary) => SafeArea(
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(26),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(22),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Expanded(
                                          child: Text('选择练习模式',
                                              style: TextStyle(
                                                  fontSize: 23,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      IconButton(
                                          tooltip: '关闭',
                                          onPressed: () => finish(context),
                                          icon: const Icon(Icons.close)),
                                    ]),
                                    Text(
                                        '${review ? '到期复习' : '学习新题'} · $count 题 · 点击一种模式开始'),
                                    const SizedBox(height: 16),
                                    for (final mode in const [
                                      (
                                        'deep',
                                        '深度练习',
                                        '逐题查看解析并评级，适合学习新知识、弄懂错题。',
                                        Icons.menu_book_rounded
                                      ),
                                      (
                                        'batch',
                                        '批量练习',
                                        '先集中作答，再统一查看解析与复盘，适合检验掌握程度。',
                                        Icons.layers_outlined
                                      ),
                                      (
                                        'speed',
                                        '速刷',
                                        '答对自动进入下一题，答错停下来查看解析，适合快速巩固。',
                                        Icons.bolt_rounded
                                      ),
                                    ]) ...[
                                      PressFeedback(
                                          child: Material(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withAlpha(10),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: ListTile(
                                                  key: ValueKey(
                                                      'study-mode-${mode.$1}'),
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 8),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16)),
                                                  leading: Icon(mode.$4,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary),
                                                  title: Text(mode.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                                                  subtitle: Text(mode.$3),
                                                  trailing: const Icon(Icons.chevron_right),
                                                  onTap: () => finish(context, mode.$1)))),
                                      const SizedBox(height: 10),
                                    ],
                                    Text(helpText ?? '已有未完成练习会按原模式继续，保留作答进度。',
                                        style: TextStyle(fontSize: 12)),
                                  ]))))))));
}

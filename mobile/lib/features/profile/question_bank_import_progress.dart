import 'package:flutter/material.dart';

import '../../app/shared.dart';

/// The stages represent completed work, rather than a guessed byte percentage.
/// This keeps the UI honest for local parsing and the subsequent API upload.
enum QuestionBankImportStage {
  idle,
  reading,
  validating,
  saving,
  syncing,
  complete,
  partial,
  failed,
}

extension QuestionBankImportStageInfo on QuestionBankImportStage {
  int get completedSteps => switch (this) {
        QuestionBankImportStage.idle || QuestionBankImportStage.reading => 0,
        QuestionBankImportStage.validating => 1,
        QuestionBankImportStage.saving => 2,
        QuestionBankImportStage.syncing || QuestionBankImportStage.partial => 3,
        QuestionBankImportStage.complete => 4,
        QuestionBankImportStage.failed => 0,
      };

  bool get isWorking => switch (this) {
        QuestionBankImportStage.reading ||
        QuestionBankImportStage.validating ||
        QuestionBankImportStage.saving ||
        QuestionBankImportStage.syncing =>
          true,
        _ => false,
      };
}

class QuestionBankImportProgress extends StatelessWidget {
  final QuestionBankImportStage stage;
  final String detail;

  const QuestionBankImportProgress(
      {super.key, required this.stage, required this.detail});

  static const _labels = ['读取文件', '核对题目', '保存练习', '私密同步'];

  Color get _statusColor => switch (stage) {
        QuestionBankImportStage.complete => teal,
        QuestionBankImportStage.partial => Colors.orange.shade800,
        QuestionBankImportStage.failed => Colors.red.shade700,
        _ => teal,
      };

  IconData get _statusIcon => switch (stage) {
        QuestionBankImportStage.complete => Icons.check_circle_rounded,
        QuestionBankImportStage.partial => Icons.cloud_off_outlined,
        QuestionBankImportStage.failed => Icons.error_outline_rounded,
        _ => Icons.cloud_upload_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final completed = stage.completedSteps;
    final isWorking = stage.isWorking;
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _statusColor.withAlpha(12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _statusColor.withAlpha(44))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
                height: 20,
                width: 20,
                child: isWorking
                    ? CircularProgressIndicator(
                        strokeWidth: 2.4, color: _statusColor)
                    : Icon(_statusIcon, color: _statusColor, size: 21)),
            const SizedBox(width: 9),
            Expanded(
                child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(detail,
                        key: ValueKey('$stage:$detail'),
                        style: TextStyle(
                            color: _statusColor, fontWeight: FontWeight.w600))))
          ]),
          if (stage != QuestionBankImportStage.failed) ...[
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
                tween: Tween(end: completed / _labels.length),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(999),
                    color: _statusColor,
                    backgroundColor: _statusColor.withAlpha(24))),
            const SizedBox(height: 10),
            Wrap(
                spacing: 7,
                runSpacing: 6,
                children: List.generate(_labels.length, (index) {
                  final done = index < completed;
                  final active = isWorking && index == completed;
                  final color = done || active ? _statusColor : Colors.blueGrey;
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        done
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 14,
                        color: color.withAlpha(done || active ? 255 : 120)),
                    const SizedBox(width: 3),
                    Text(_labels[index],
                        style: TextStyle(
                            fontSize: 11,
                            color: color.withAlpha(done || active ? 255 : 145)))
                  ]);
                }))
          ]
        ]));
  }
}

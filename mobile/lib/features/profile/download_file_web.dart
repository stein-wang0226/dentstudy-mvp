// ignore_for_file: deprecated_member_use

import 'dart:html' as html;

String _safeFilename(String value) {
  final lastPart = value.split(RegExp(r'[\\/]')).last.trim();
  final safe = lastPart.replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_');
  return safe.toLowerCase().endsWith('.json') && safe.isNotEmpty
      ? safe
      : 'dentstudy-submission.json';
}

void downloadJsonFile({required String content, required String filename}) {
  final blob = html.Blob([content], 'application/json;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final link = html.AnchorElement(href: url)
    ..download = _safeFilename(filename)
    ..style.display = 'none';
  html.document.body?.children.add(link);
  link.click();
  link.remove();
  html.Url.revokeObjectUrl(url);
}

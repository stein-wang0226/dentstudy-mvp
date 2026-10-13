import 'dart:js_interop';

@JS('window.open')
external JSAny? _open(String url, String target, String features);

void openFilingLookup() {
  _open('https://beian.miit.gov.cn/', '_blank', 'noopener,noreferrer');
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'filing_link_stub.dart'
    if (dart.library.js_interop) 'filing_link_web.dart';

class FilingFooter extends StatelessWidget {
  const FilingFooter({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 8),
      child: Center(
        child: TextButton(
          onPressed: openFilingLookup,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: const Text('浙ICP备2026084344号-1'),
        ),
      ),
    );
  }
}

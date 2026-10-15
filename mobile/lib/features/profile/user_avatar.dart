import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app/shared.dart' show teal;

class UserAvatar extends StatelessWidget {
  final String value;
  final double radius;
  const UserAvatar({super.key, required this.value, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    if (value.startsWith('data:image/png;base64,')) {
      try {
        final bytes = base64Decode(value.split(',').last);
        return ClipOval(
            child: Image.memory(bytes,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback()));
      } catch (_) {/* Fall back if cached image data cannot be decoded. */}
    }
    return _fallback();
  }

  Widget _fallback() => CircleAvatar(
      radius: radius,
      backgroundColor: teal.withAlpha(20),
      child: Icon(
          switch (value) {
            'tooth' => Icons.health_and_safety_outlined,
            'science' => Icons.science_outlined,
            'leaf' => Icons.eco_outlined,
            'star' => Icons.star_outline,
            'smile' => Icons.sentiment_satisfied_alt_outlined,
            _ => Icons.auto_stories_outlined,
          },
          color: teal,
          size: radius));
}

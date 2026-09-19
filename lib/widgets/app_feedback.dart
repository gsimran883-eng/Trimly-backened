import 'package:flutter/material.dart';

enum FeedbackKind { success, error, info }

void showAppFeedback(
  BuildContext context,
  String message, {
  FeedbackKind kind = FeedbackKind.info,
  SnackBarAction? action,
}) {
  final (icon, color) = switch (kind) {
    FeedbackKind.success => (
        Icons.check_circle_outline,
        const Color(0xFF62D6A7)
      ),
    FeedbackKind.error => (Icons.error_outline, const Color(0xFFFF7B86)),
    FeedbackKind.info => (Icons.info_outline, const Color(0xFF68C7FF)),
  };

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      action: action,
    ),
  );
}

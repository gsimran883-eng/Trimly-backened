import 'package:flutter/material.dart';

Future<void> showNotEnoughPointsDialog(
  BuildContext context, {
  required VoidCallback onBuyClicked,
  required VoidCallback onWatchAdClicked,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF151520),
      title: const Text(
        'Out of points',
        style: TextStyle(color: Colors.white),
      ),
      content: const Text(
        'You need more points to generate this Rambo template. Buy a point pack or watch a quick ad to continue.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onWatchAdClicked();
          },
          child: const Text('Watch ad'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onBuyClicked();
          },
          child: const Text('Get points'),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditorToolBottomSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onDismiss;

  const EditorToolBottomSheet({
    super.key,
    required this.title,
    required this.child,
    required this.onDismiss,
  });

  static const double minExtent = 0.18;

  void _dismiss() {
    HapticFeedback.lightImpact();
    onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        if (notification.extent <= minExtent + 0.005) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _dismiss());
        }
        return false;
      },
      child: DraggableScrollableSheet(
        key: const ValueKey('editor-tool-bottom-sheet'),
        initialChildSize: 0.34,
        minChildSize: minExtent,
        maxChildSize: 0.68,
        snap: true,
        snapSizes: const [minExtent, 0.34, 0.68],
        builder: (context, scrollController) {
          return Material(
            color: const Color(0xF511111A),
            elevation: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      const SizedBox(width: 44),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close tool panel',
                        onPressed: _dismiss,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: PrimaryScrollController(
                      controller: scrollController,
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

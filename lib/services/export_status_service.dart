import 'package:flutter/foundation.dart';

class ExportStatus {
  final String label;
  final double progress;
  final bool isActive;
  final bool succeeded;

  const ExportStatus({
    required this.label,
    required this.progress,
    required this.isActive,
    this.succeeded = false,
  });

  const ExportStatus.idle()
      : label = '',
        progress = 0,
        isActive = false,
        succeeded = false;
}

class ExportStatusService {
  ExportStatusService._();

  static final ExportStatusService instance = ExportStatusService._();

  final ValueNotifier<ExportStatus> status =
      ValueNotifier<ExportStatus>(const ExportStatus.idle());

  void start(String label) {
    status.value = ExportStatus(
      label: label,
      progress: 0.1,
      isActive: true,
    );
  }

  void update(double progress) {
    final current = status.value;
    if (!current.isActive) {
      return;
    }
    status.value = ExportStatus(
      label: current.label,
      progress: progress.clamp(0.0, 0.95),
      isActive: true,
    );
  }

  void finish({required bool success}) {
    final current = status.value;
    status.value = ExportStatus(
      label: current.label,
      progress: success ? 1 : 0,
      isActive: false,
      succeeded: success,
    );
  }
}

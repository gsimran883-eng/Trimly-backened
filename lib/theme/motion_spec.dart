import 'package:flutter/animation.dart';

class MotionSpec {
  const MotionSpec._();

  static const Duration entryDuration = Duration(milliseconds: 300);
  static const Duration panelSwitchDuration = Duration(milliseconds: 240);
  static const Duration selectionDuration = Duration(milliseconds: 220);
  static const Duration shimmerSweepDuration = Duration(milliseconds: 4200);

  static const Curve revealCurve = Curves.easeOutCubic;
  static const Curve panelEntranceCurve = Curves.easeOutCubic;
  static const Curve dockEntranceCurve = Curves.easeOutBack;
  static const Curve switchInCurve = Curves.easeOutCubic;
  static const Curve switchOutCurve = Curves.easeInCubic;
  static const Curve emphasisCurve = Curves.easeOutCubic;

  static const double revealStaggerStep = 0.05;
  static const double revealBeginMax = 0.55;
  static const double panelEntranceBegin = 0.24;
  static const double dockEntranceBegin = 0.35;

  static const double revealOffsetY = 0.05;
  static const double panelOffsetY = 0.12;
  static const double switchOffsetX = 0.03;

  static double revealBeginForOrder(int order) {
    final begin = order * revealStaggerStep;
    return begin > revealBeginMax ? revealBeginMax : begin;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/services/point_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts with 50 points and persists deductions', () async {
    expect(await PointService.getPoints(), 50);
    expect(await PointService.deductPoints(10), isTrue);
    expect(await PointService.getPoints(), 40);
  });

  test('rejects deductions larger than the balance', () async {
    expect(await PointService.deductPoints(51), isFalse);
    expect(await PointService.getPoints(), 50);
  });

  test('adds purchased or rewarded points', () async {
    await PointService.addPoints(100);
    expect(await PointService.getPoints(), 150);
  });
}

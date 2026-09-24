import 'package:shared_preferences/shared_preferences.dart';

class PointService {
  static const String _pointsKey = 'user_points_balance';
  static const int startingBalance = 50;
  static const int ramboGenerationCost = 10;
  static const int speechGenerationCost = 5;

  static Future<int> getPoints() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pointsKey) ?? startingBalance;
  }

  static Future<bool> deductPoints(int amount) async {
    if (amount <= 0) {
      return true;
    }

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_pointsKey) ?? startingBalance;
    if (current < amount) {
      return false;
    }

    await prefs.setInt(_pointsKey, current - amount);
    return true;
  }

  static Future<void> addPoints(int amount) async {
    if (amount <= 0) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_pointsKey) ?? startingBalance;
    await prefs.setInt(_pointsKey, current + amount);
  }
}

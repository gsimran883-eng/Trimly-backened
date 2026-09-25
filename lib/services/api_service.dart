import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://trimly-backened-1.onrender.com';

  static Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map && data['ready'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Connection error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> generateRambo(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/v1/rambo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      debugPrint('Error: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Request failed: $e');
      return null;
    }
  }
}

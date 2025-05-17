// lib/services/insights_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class InsightsService {
  // Server URL (change based on your environment)
  static const String serverUrl =
      'http://10.0.2.2:5000'; // For Android emulator
  // static const String serverUrl = 'http://localhost:5000'; // For iOS simulator

  // Get health insights
  static Future<Map<String, dynamic>> getHealthInsights() async {
    try {
      // Create sample user data
      // In a real app, you would get this from Firebase
      final userData = {
        'profile': {
          'age': 28,
          'gestationalAge': 24, // weeks
          'conditions': ['Previous preeclampsia'],
        },
        'vitals': [
          {
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'systolic': 118,
            'diastolic': 75,
          },
          {
            'timestamp':
                DateTime.now()
                    .subtract(const Duration(days: 1))
                    .millisecondsSinceEpoch,
            'systolic': 120,
            'diastolic': 78,
          },
        ],
        'symptoms': [
          {
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'symptomsList': ['mild headache', 'fatigue'],
          },
        ],
      };

      // Call our insights server
      final response = await http.post(
        Uri.parse('$serverUrl/api/insights'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userData': userData}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['insights'];
      } else {
        throw Exception('Failed to get insights: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting health insights: $e');

      // Return fallback data in case of error
      return {
        'summary':
            'Unable to generate insights at this time. Please try again later.',
        'recommendations': [],
        'discussWithDoctor': [],
      };
    }
  }
}

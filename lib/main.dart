// main.dart
import 'package:finale/screens/dashboard.dart';
import 'package:flutter/material.dart';

import 'authentication/login.dart';


void main() {
  runApp(const BloodPressureApp());
}

class BloodPressureApp extends StatelessWidget {
  const BloodPressureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Blood Pressure Tracker',
      theme: ThemeData(
        primaryColor: const Color(0xFF0069B4),
        scaffoldBackgroundColor: const Color(0xFF0069B4),
        fontFamily: 'Roboto',
      ),
      home: const LoginScreen(),
    );
  }
}
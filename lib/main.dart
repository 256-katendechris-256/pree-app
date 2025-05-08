import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'authentication/login.dart';
import 'firebase_options.dart'; // Ensure you have this file generated for Firebase configuration.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

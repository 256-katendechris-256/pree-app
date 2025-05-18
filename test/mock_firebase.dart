// test/firebase_mocks.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FirebaseMocks {
  static Future<void> setupFirebaseCoreMocks() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Mock Firebase Core
    const MethodChannel firebaseCoreChannel = MethodChannel(
      'plugins.flutter.io/firebase_core',
    );
    
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(firebaseCoreChannel, (MethodCall call) async {
      if (call.method == 'Firebase#initializeCore') {
        return [
          {
            'name': '[DEFAULT]',
            'options': {
              'apiKey': 'mock-api-key',
              'appId': 'mock-app-id',
              'messagingSenderId': 'mock-sender-id',
              'projectId': 'mock-project-id',
            },
            'pluginConstants': {},
          }
        ];
      }
      
      if (call.method == 'Firebase#initializeApp') {
        return {
          'name': call.arguments['appName'] ?? '[DEFAULT]',
          'options': call.arguments['options'] ?? {},
          'pluginConstants': {},
        };
      }
      
      return null;
    });
    
    // Mock Firebase Auth
    const MethodChannel firebaseAuthChannel = MethodChannel(
      'plugins.flutter.io/firebase_auth',
    );
    
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(firebaseAuthChannel, (MethodCall call) async {
      switch (call.method) {
        case 'Auth#authStateChanges':
        case 'Auth#idTokenChanges':
        case 'Auth#userChanges':
          return null;
        case 'Auth#getCurrentUser':
          return null;
        case 'Auth#signOut':
          return null;
        default:
          return null;
      }
    });
  }
}
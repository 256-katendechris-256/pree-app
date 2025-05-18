// test/main_function_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'mock_firebase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('Firebase initialization does not throw errors', () async {
    // Setup mocks
    await FirebaseMocks.setupFirebaseCoreMocks();
    
    // Test initialization
    await Firebase.initializeApp();
    
    // Check that Firebase was initialized
    expect(Firebase.apps.length, greaterThan(0));
  });
}
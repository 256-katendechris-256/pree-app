// test/app_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finale/main.dart';
 // Replace with your app name

void main() {
  testWidgets('BloodPressureApp should have correct theme and no debug banner', 
      (WidgetTester tester) async {
    // Create a test home widget
    final testHomeWidget = Container(
      child: const Text('Test Home'),
    );
    
    // Build the app with our test home widget instead of LoginScreen
    await tester.pumpWidget(BloodPressureApp(homeScreen: testHomeWidget));
    
    // Get the MaterialApp widget
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    
    // Test theme settings
    expect(app.theme?.primaryColor, equals(const Color(0xFF0069B4)));
    expect(app.theme?.scaffoldBackgroundColor, equals(const Color(0xFF0069B4)));
    
    // Test that debug banner is not shown
    expect(app.debugShowCheckedModeBanner, isFalse);
    
    // Test that the app has the correct title
    expect(app.title, equals('Blood Pressure Tracker'));
  });
  
  testWidgets('BloodPressureApp should show test home screen', 
      (WidgetTester tester) async {
    // Create a test home widget with specific text
    final testHomeWidget = const Center(
      child: Text('Test Home Text'),
    );
    
    // Build the app with our test widget
    await tester.pumpWidget(BloodPressureApp(homeScreen: testHomeWidget));
    
    // Verify the test text appears
    expect(find.text('Test Home Text'), findsOneWidget);
  });
}
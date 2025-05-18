// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finale/main.dart'; // Replace with your app name

void main() {
  testWidgets('Counter smoke test', (WidgetTester tester) async {
    // Create a simple counter widget for testing
    int count = 0;
    
    final counterWidget = StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        return Scaffold(
          body: Center(
            child: Text('$count'),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              setState(() {
                count++;
              });
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
    
    // Provide our counter widget as the home screen
    await tester.pumpWidget(BloodPressureApp(homeScreen: counterWidget));
    
    // Verify that our counter starts at 0
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    
    // Tap the '+' icon and trigger a frame
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    
    // Verify that our counter has incremented
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
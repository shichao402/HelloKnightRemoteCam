// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, find text, verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:hello_knight_rcc/main.dart';
import 'package:hello_knight_rcc/screens/device_connection_screen.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RemoteCamClientApp());

    // Verify that the app starts (DeviceConnectionScreen should be visible)
    expect(find.byType(DeviceConnectionScreen), findsOneWidget);
  });
}

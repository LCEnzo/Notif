// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

import 'package:notif/main.dart';

void main() {
  testWidgets('App shows the login screen by default',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(
            create: (context) => UserDataService(context.read<AuthService>()),
          ),
        ],
        child: const App(),
      ),
    );

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });
}

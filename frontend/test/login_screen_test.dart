import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_theme.dart';
import 'package:notif/screens/login.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth_test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'lastSuccessfulUsername': 'LCEnzo',
    });
  });

  testWidgets('login screen prefills username and exposes autofill hints', (
    WidgetTester tester,
  ) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(
            create: (_) => AuthService(
              store: InMemorySessionStore(),
              transport: SessionTransport.bearer,
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildNotifTheme(
            colorway: settings.colorway,
            fontSet: settings.fontSet,
          ),
          home: const LogInPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final usernameField = tester.widget<TextFormField>(
      find.byType(TextFormField).at(0),
    );
    final usernameEditable = tester.widget<EditableText>(
      find.byType(EditableText).at(0),
    );
    final passwordEditable = tester.widget<EditableText>(
      find.byType(EditableText).at(1),
    );

    expect(usernameField.controller?.text, 'LCEnzo');
    expect(usernameEditable.autofillHints, contains(AutofillHints.username));
    expect(passwordEditable.autofillHints, contains(AutofillHints.password));

    if (kDebugMode) {
      expect(find.text('Debug login'), findsOneWidget);
    }
  });
}

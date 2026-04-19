import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/auth_texture_tuner.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notif/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    disableAuthTextureTuner();
  });

  testWidgets('App shows the framed login screen by default', (
    WidgetTester tester,
  ) async {
    enableAuthTextureTuner();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppSettingsController()),
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(
            create: (context) => UserDataService(context.read<AuthService>()),
          ),
        ],
        child: const App(),
      ),
    );

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('FORGOT PASSWORD?'), findsOneWidget);
    expect(find.text('Handle'), findsNothing);
    expect(find.text('Passphrase'), findsNothing);
  });

  testWidgets('Forgot password CTA opens the recovery screen', (
    WidgetTester tester,
  ) async {
    enableAuthTextureTuner();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppSettingsController()),
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(
            create: (context) => UserDataService(context.read<AuthService>()),
          ),
        ],
        child: const App(),
      ),
    );

    await tester.tap(find.text('FORGOT PASSWORD?'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot the passphrase?'), findsOneWidget);
    expect(find.text('Back to log in'), findsOneWidget);
  });
}

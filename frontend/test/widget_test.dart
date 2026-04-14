import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/auth_texture_tuner.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
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

  testWidgets('App shows the login screen by default', (
    WidgetTester tester,
  ) async {
    enableAuthTextureTuner();

    final authService = AuthService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppSettingsController()),
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider(
            create: (_) => UserDataService(authService),
          ),
          ChangeNotifierProvider(
            create: (_) => LinkService(authService),
          ),
          ChangeNotifierProvider(
            create: (_) => NotificationService(authService),
          ),
        ],
        child: const App(),
      ),
    );

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/auth_texture_tuner.dart';
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

  testWidgets('App shows the login screen by default',
      (WidgetTester tester) async {
    enableAuthTextureTuner();

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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_background.dart';
import 'package:notif/commons/auth_texture_tuner.dart';
import 'package:notif/commons/notif_theme.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/screens/login.dart';
import 'package:notif/screens/register.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    disableAuthTextureTuner();
  });

  test('AuthTextureTunerController updates fields, notifies listeners, and resets', () {
    final controller = AuthTextureTunerController();
    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    controller.setField(AuthTextureField.grainSpacing, 3.5);

    expect(controller.settings.grainSpacing, 3.5);
    expect(notifications, 1);
    expect(
      controller.settings.toDartSnippet(),
      contains('spacing: 3.5,'),
    );

    controller.reset();

    expect(controller.settings, AuthTextureSettings.defaults);
    expect(notifications, 2);
  });

  testWidgets('PageBackground exposes the debug tuner and updates the controller',
      (WidgetTester tester) async {
    final controller = enableAuthTextureTuner();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNotifTheme(
          colorway: NotifColorway.dusk1,
          fontSet: NotifFontSet.current,
        ),
        home: const Scaffold(
          body: PageBackground(
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('authTextureTunerLauncher')), findsOneWidget);

    await tester.tap(find.byKey(const Key('authTextureTunerLauncher')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('authTextureTunerPanel')), findsOneWidget);
    expect(find.text('Grain'), findsOneWidget);
    expect(find.text('Halftone'), findsOneWidget);

    final sliderFinder =
        find.byKey(const Key('authTextureField-grainSpacing'));
    expect(sliderFinder, findsOneWidget);

    final slider = tester.widget<Slider>(sliderFinder);
    slider.onChanged!(3.5);
    await tester.pump();

    expect(controller.settings.grainSpacing, 3.5);
  });

  testWidgets('Texture settings persist between login and register in one session',
      (WidgetTester tester) async {
    final controller = enableAuthTextureTuner();
    final settings = AppSettingsController();
    final authService = AuthService();
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (context, state) => const LogInPage()),
        GoRoute(path: '/register', builder: (context, state) => const RegisterPage()),
        GoRoute(path: '/about', builder: (context, state) => const Scaffold(body: SizedBox())),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthService>.value(value: authService),
        ],
        child: MaterialApp.router(
          theme: buildNotifTheme(
            colorway: settings.colorway,
            fontSet: settings.fontSet,
          ),
          routerConfig: router,
        ),
      ),
    );
    addTearDown(settings.dispose);
    addTearDown(router.dispose);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('authTextureTunerLauncher')));
    await tester.pumpAndSettle();

    final loginSliderFinder =
        find.byKey(const Key('authTextureField-grainSpacing'));
    final loginSlider = tester.widget<Slider>(loginSliderFinder);
    loginSlider.onChanged!(4.2);
    await tester.pump();

    expect(controller.settings.grainSpacing, 4.2);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterPage), findsOneWidget);
    expect(controller.settings.grainSpacing, 4.2);

    await tester.tap(find.byKey(const Key('authTextureTunerLauncher')));
    await tester.pumpAndSettle();

    final registerSlider = tester.widget<Slider>(
      find.byKey(const Key('authTextureField-grainSpacing')),
    );
    expect(registerSlider.value, 4.2);
  });
}

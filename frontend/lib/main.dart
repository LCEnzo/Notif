import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notif/commons/auth_texture_tuner.dart';
import 'package:notif/screens/shared.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

void main() {
  if (kDebugMode) {
    enableAuthTextureTuner();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppSettingsController()),
        ChangeNotifierProxyProvider<AppSettingsController, AuthService>(
          create: (_) => AuthService(),
          update: (_, settings, auth) => auth!..updateSettings(settings),
        ),
        ChangeNotifierProxyProvider2<
          AuthService,
          AppSettingsController,
          UserDataService
        >(
          create: (context) => UserDataService(context.read<AuthService>()),
          update: (_, auth, settings, userData) =>
              userData!..updateSettings(settings),
        ),
      ],
      child: const App(),
    ),
  );
}

class _DarkFadeUpTransitionBuilder extends PageTransitionsBuilder {
  const _DarkFadeUpTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Fade in + slight upward slide. Uses the dark scaffold color as
    // transition background instead of the default white.
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notif',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 69, 26, 172),
          brightness: Brightness.light,
          primaryContainer: const Color.fromARGB(255, 89, 53, 173),
          primary: const Color.fromARGB(255, 69, 26, 172),
          tertiary: const Color.fromARGB(255, 76, 18, 211),
        ),
        fontFamily: 'Skyling',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 72),
          titleLarge: TextStyle(fontSize: 36),
          bodyMedium: TextStyle(fontSize: 14),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _DarkFadeUpTransitionBuilder(),
            TargetPlatform.iOS: _DarkFadeUpTransitionBuilder(),
            TargetPlatform.linux: _DarkFadeUpTransitionBuilder(),
            TargetPlatform.windows: _DarkFadeUpTransitionBuilder(),
            TargetPlatform.macOS: _DarkFadeUpTransitionBuilder(),
            TargetPlatform.fuchsia: _DarkFadeUpTransitionBuilder(),
          },
        ),
      ),
      home: const LogInPage(),
      routes: {
        '/Home': (context) => const HomePage(),
        '/LogIn': (context) => const LogInPage(),
        '/Register': (context) => const RegisterPage(),
        '/About': (context) => const AboutPage(),
        '/Settings': (context) => const SettingsPage(),
      },
    );
  }
}

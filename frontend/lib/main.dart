import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_texture_tuner.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
import 'package:notif/services/router.dart';
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
        ChangeNotifierProxyProvider2<
          AuthService,
          AppSettingsController,
          LinkService
        >(
          create: (context) => LinkService(context.read<AuthService>()),
          update: (_, auth, settings, linkService) =>
              linkService!..updateDependencies(auth, settings),
        ),
        ChangeNotifierProxyProvider2<
          AuthService,
          AppSettingsController,
          NotificationService
        >(
          create: (context) => NotificationService(context.read<AuthService>()),
          update: (_, auth, settings, notificationService) =>
              notificationService!..updateDependencies(auth, settings),
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
      opacity: Tween<double>(
        begin: 0,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
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

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createRouter(context.read<AuthService>());
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Notif',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: NotifDesignTokens.structBg,
        colorScheme: const ColorScheme.dark(
          primary: NotifDesignTokens.accentPrimary,
          onPrimary: NotifDesignTokens.accentOnAccent,
          secondary: NotifDesignTokens.accentText,
          onSecondary: NotifDesignTokens.structText,
          surface: NotifDesignTokens.structSurface,
          onSurface: NotifDesignTokens.structText,
          error: FeedbackColors.error,
          onError: Colors.white,
        ),
        fontFamily: NotifDesignTokens.bodyFont,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: NotifDesignTokens.displayFont,
            fontSize: 72,
          ),
          titleLarge: TextStyle(
            fontFamily: NotifDesignTokens.displayFont,
            fontSize: 36,
          ),
          bodyMedium: TextStyle(
            fontFamily: NotifDesignTokens.bodyFont,
            fontSize: 14,
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: NotifDesignTokens.structRaised,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          titleTextStyle: const TextStyle(
            fontFamily: NotifDesignTokens.displayFont,
            color: NotifDesignTokens.structText,
            fontSize: 24,
          ),
          contentTextStyle: const TextStyle(
            fontFamily: NotifDesignTokens.bodyFont,
            color: NotifDesignTokens.structText2,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: NotifDesignTokens.structRaised,
          contentTextStyle: const TextStyle(
            fontFamily: NotifDesignTokens.bodyFont,
            color: NotifDesignTokens.structText,
          ),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          behavior: SnackBarBehavior.floating,
          actionTextColor: NotifDesignTokens.accentText,
        ),
        dividerColor: NotifDesignTokens.structDivider,
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
      routerConfig: _router,
    );
  }
}

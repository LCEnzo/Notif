import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/auth_texture_tuner.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
import 'package:notif/services/device_sessions.dart';
import 'package:notif/services/ops.dart';
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
        ChangeNotifierProxyProvider2<
          AuthService,
          AppSettingsController,
          DeviceSessionService
        >(
          create: (context) =>
              DeviceSessionService(context.read<AuthService>()),
          update: (_, auth, settings, sessions) =>
              sessions!..updateDependencies(auth, settings),
        ),
        ChangeNotifierProxyProvider2<
          AuthService,
          AppSettingsController,
          OpsService
        >(
          create: (context) => OpsService(context.read<AuthService>()),
          update: (_, auth, settings, opsService) =>
              opsService!..updateDependencies(auth, settings),
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
    final curveTween = CurveTween(curve: Curves.easeOutCubic);
    final slideTween = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).chain(curveTween);
    final fadeTween = Tween<double>(begin: 0, end: 1).chain(curveTween);

    return FadeTransition(
      opacity: animation.drive(fadeTween),
      child: SlideTransition(
        position: animation.drive(slideTween),
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
    final auth = context.read<AuthService>();
    _router = createRouter(auth);
    // The cold-start probe. Deliberately fire-and-forget: the router follows
    // the resulting state change, and there is nothing here that could
    // usefully handle a failure the state machine has not already classified.
    unawaited(auth.restore());
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final baseTheme = buildNotifTheme(
      colorway: settings.colorway,
      fontSet: settings.fontSet,
    );
    final tokens = baseTheme.extension<NotifTokens>()!;
    final text$ = baseTheme.extension<NotifTextTheme>()!;

    return MaterialApp.router(
      title: 'Notif',
      theme: baseTheme.copyWith(
        dialogTheme: DialogThemeData(
          backgroundColor: tokens.bg2,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          titleTextStyle: text$.title.copyWith(color: tokens.ink),
          contentTextStyle: text$.body.copyWith(color: tokens.inkDim),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: tokens.bg2,
          contentTextStyle: text$.body.copyWith(color: tokens.ink),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          behavior: SnackBarBehavior.floating,
          actionTextColor: tokens.accent,
        ),
        dividerColor: tokens.rule,
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/screens/about.dart';
import 'package:notif/screens/homescreen.dart';
import 'package:notif/screens/login.dart';
import 'package:notif/screens/register.dart';
import 'package:notif/screens/settings.dart';
import 'package:notif/services/auth.dart';

GoRouter createRouter(AuthService authService) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authService,
    redirect: (context, state) {
      final loggedIn = authService.jwt != null;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LogInPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
}

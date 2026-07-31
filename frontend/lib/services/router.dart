import 'package:go_router/go_router.dart';
import 'package:notif/screens/about.dart';
import 'package:notif/screens/account.dart';
import 'package:notif/screens/forgot_password.dart';
import 'package:notif/screens/homescreen.dart';
import 'package:notif/screens/login.dart';
import 'package:notif/screens/ops.dart';
import 'package:notif/screens/register.dart';
import 'package:notif/screens/reset_password.dart';
import 'package:notif/screens/settings.dart';
import 'package:notif/screens/starting.dart';
import 'package:notif/services/auth.dart';

GoRouter createRouter(AuthService authService) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authService,
    redirect: (context, state) {
      final loggedIn = authService.isAuthenticated;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password' ||
          state.matchedLocation == '/reset-password';
      final isPublicRoute = state.matchedLocation == '/about';

      // Restoring and Unavailable are neither signed in nor signed out, and
      // must not be rendered as either. Showing the login form would flash it
      // at a user who turns out to be authenticated (cold start) or claim a
      // sign-out the server never performed (web logout against a dead
      // backend). /starting is the honest screen for "we do not know yet".
      if (authService.isUndecided) {
        return state.matchedLocation == '/starting' ? null : '/starting';
      }
      if (state.matchedLocation == '/starting') {
        return loggedIn ? '/home' : '/login';
      }

      if (!loggedIn && !isAuthRoute && !isPublicRoute) return '/login';
      if (loggedIn && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/starting',
        builder: (context, state) => const StartingPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LogInPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return ResetPasswordPage(email: email);
        },
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/sources',
        builder: (context, state) => const SourcesPage(),
      ),
      GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountPage(),
      ),
      GoRoute(path: '/ops', builder: (context, state) => const OpsPage()),
    ],
  );
}

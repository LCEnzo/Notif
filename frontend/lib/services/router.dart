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
import 'package:notif/services/auth.dart';

/// Where the app waits while a remembered session is being restored, instead
/// of showing the login screen it is about to redirect away from.
const String splashRoute = '/splash';

GoRouter createRouter(AuthService authService) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authService,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isAuthRoute =
          location == '/login' ||
          location == '/register' ||
          location == '/forgot-password' ||
          location == '/reset-password';
      final isPublicRoute = location == '/about';

      // Restoring: we do not yet know whether there is a session, so committing
      // to either side would flash a screen the user is not staying on.
      if (authService.isRestoringSession) {
        if (location == splashRoute || isPublicRoute) return null;
        return splashRoute;
      }

      final loggedIn = authService.jwt != null;
      if (location == splashRoute) return loggedIn ? '/home' : '/login';
      if (!loggedIn && !isAuthRoute && !isPublicRoute) return '/login';
      if (loggedIn && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: splashRoute,
        builder: (context, state) => const SessionRestoreSplash(),
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

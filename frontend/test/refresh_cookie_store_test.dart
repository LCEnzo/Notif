import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/refresh_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores native refresh cookies per backend origin', () async {
    final origin = Uri.parse('https://api.example.com/api/v1/token/');

    await rememberNativeRefreshCookie(origin, [
      'notif_refresh=refresh-token; Max-Age=259200; Path=/api/v1/token/; HttpOnly; SameSite=Lax',
    ]);

    expect(
      await nativeRefreshCookieHeader(
        Uri.parse('https://api.example.com/api/v1/token/refresh/'),
        '/token/refresh/',
      ),
      'notif_refresh=refresh-token',
    );
    expect(
      await nativeRefreshCookieHeader(
        Uri.parse('https://other.example.com/api/v1/token/refresh/'),
        '/token/refresh/',
      ),
      isNull,
    );
    expect(
      await nativeRefreshCookieHeader(
        Uri.parse('https://api.example.com/api/v1/monitoring/links/'),
        '/monitoring/links/',
      ),
      isNull,
    );
  });

  test(
    'clears native refresh cookies from delete Set-Cookie headers',
    () async {
      final origin = Uri.parse('https://api.example.com/api/v1/token/');

      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=refresh-token; Max-Age=259200; Path=/api/v1/token/',
      ]);
      await rememberNativeRefreshCookie(origin, [
        'notif_refresh=""; Max-Age=0; Path=/api/v1/token/',
      ]);

      expect(
        await nativeRefreshCookieHeader(
          Uri.parse('https://api.example.com/api/v1/token/refresh/'),
          '/token/refresh/',
        ),
        isNull,
      );
    },
  );
}

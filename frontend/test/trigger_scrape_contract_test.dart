import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/data.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

/// Pins the POST /monitoring/trigger-scrape/ response contract.
///
/// The endpoint used to return two structurally incompatible 200 bodies — a
/// fixed-key object for a single link and a bare PK-keyed map for scrape-all —
/// which additionally spelled the same datum `updates_found` in one and `count`
/// in the other. Nothing on either side tested it, so the divergence was held
/// together only by the client branching on its own request argument. The
/// backend now always wraps scrape-all in `{"status": "ok", "results": {...}}`
/// and uses `updates_found` everywhere; these tests fail if either side drifts.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The error-path tests reach _recordFailure -> reportClientFailure, which
    // reads package metadata; without this the platform channel throws as an
    // unhandled async error rather than failing an assertion.
    PackageInfo.setMockInitialValues(
      appName: 'notif',
      packageName: 'com.example.notif',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
    resetApiAuthForTesting();
  });

  tearDown(() {
    resetApiAuthForTesting();
    apiDio.httpClientAdapter = HttpClientAdapter();
  });

  /// An authenticated LinkService wired to [handler] for every request except
  /// login and the link refetch that follows a scrape.
  Future<LinkService> scrapingService(FakeHttpHandler handler) async {
    apiDio.httpClientAdapter = FakeHttpAdapter((options) {
      final path = options.uri.path;
      if (path.endsWith('/token/')) {
        return jsonResponse(const {'access': 'access-token'});
      }
      if (path.endsWith('/strategies/')) {
        return jsonResponse(const <Object?>[]);
      }
      if (path.endsWith('/strat-choices')) {
        return jsonResponse(const <Object?>['GeneralSelectorStrategy']);
      }
      if (path.endsWith('/links/')) {
        return jsonResponse(const {
          'count': 0,
          'next': null,
          'results': <Object?>[],
        });
      }
      return handler(options);
    });

    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await settings.initialized;

    final auth = AuthService();
    addTearDown(auth.dispose);
    auth.updateSettings(settings);
    await auth.loginWithRememberMe('user', 'pass', rememberMe: true);

    final links = LinkService(auth);
    addTearDown(links.dispose);
    links.updateDependencies(auth, settings);
    return links;
  }

  group('single-link scrape', () {
    test('reads updates_found from the flat object', () async {
      final links = await scrapingService(
        (_) => jsonResponse(const {'status': 'ok', 'updates_found': 3}),
      );

      expect(await links.triggerScrape(linkId: 7), contains('3 new updates'));
    });

    test('pluralises a single update', () async {
      final links = await scrapingService(
        (_) => jsonResponse(const {'status': 'ok', 'updates_found': 1}),
      );

      expect(await links.triggerScrape(linkId: 7), contains('1 new update.'));
    });

    test('surfaces the server message from a 400', () async {
      final links = await scrapingService(
        (_) => jsonResponse(
          const {'status': 'error', 'message': 'No strategy assigned'},
          statusCode: 400,
        ),
      );

      expect(await links.triggerScrape(linkId: 7), isNull);
      expect(links.error, contains('No strategy assigned'));
    });

    test('surfaces the server message from a 404', () async {
      final links = await scrapingService(
        (_) => jsonResponse(
          const {'status': 'error', 'message': 'Link not found'},
          statusCode: 404,
        ),
      );

      expect(await links.triggerScrape(), isNull);
      expect(links.error, contains('Link not found'));
    });
  });

  group('scrape-all', () {
    test('reads the wrapped results map and sums updates_found', () async {
      final links = await scrapingService(
        (_) => jsonResponse(const {
          'status': 'ok',
          'results': {
            '12': {'status': 'ok', 'updates_found': 3},
            '13': {'status': 'ok', 'updates_found': 4},
          },
        }),
      );

      final message = await links.triggerScrape();

      expect(message, contains('2 links'));
      expect(message, contains('7 updates'));
    });

    test('counts per-link failures separately', () async {
      final links = await scrapingService(
        (_) => jsonResponse(const {
          'status': 'ok',
          'results': {
            '12': {'status': 'ok', 'updates_found': 2},
            '13': {'status': 'error', 'message': 'Unknown strategy class'},
          },
        }),
      );

      final message = await links.triggerScrape();

      expect(message, contains('1 link'));
      expect(message, contains('2 updates'));
      expect(message, contains('1 link failed'));
    });

    test('does not read a top-level PK-keyed map (the old shape)', () async {
      // The pre-unification body. It must no longer be interpreted as a
      // summary: silently reporting "0 links" beats inventing a count, and this
      // is the assertion that fails if the backend regresses to the bare map.
      final links = await scrapingService(
        (_) => jsonResponse(const {
          '12': {'status': 'ok', 'count': 3},
        }),
      );

      expect(await links.triggerScrape(), contains('no summary'));
    });

    test('treats an empty results map as no summary', () async {
      final links = await scrapingService(
        (_) => jsonResponse(const {
          'status': 'ok',
          'results': <String, Object?>{},
        }),
      );

      expect(await links.triggerScrape(), contains('no summary'));
    });

    test(
      'sends no link_id, so the backend takes the scrape-all path',
      () async {
        late RequestOptions scrapeRequest;
        final links = await scrapingService((options) {
          scrapeRequest = options;
          return jsonResponse(const {
            'status': 'ok',
            'results': <String, Object?>{},
          });
        });

        await links.triggerScrape();

        final body =
            jsonDecode(jsonEncode(scrapeRequest.data)) as Map<String, Object?>;
        expect(body.containsKey('link_id'), isFalse);
      },
    );
  });
}

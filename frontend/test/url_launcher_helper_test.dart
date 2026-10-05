import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/url_launcher_helper.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records every URL handed to the OS launcher instead of touching a real
/// platform channel, so a test can assert whether [openUriSafely] actually
/// launched. Extending [UrlLauncherPlatform] (rather than mocking it) means the
/// default super constructor supplies the interface token, so assigning this to
/// [UrlLauncherPlatform.instance] passes verification without a mock mixin.
class _RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}

/// A minimal surface with a ScaffoldMessenger (for SnackBars) and a live
/// BuildContext, wired to call [openUriSafely] on tap.
Widget _launchHost(Uri uri) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => unawaited(openUriSafely(context, uri)),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  late _RecordingUrlLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = original;
  });

  // Snackbar text is a literal per case (not derived from Uri.parse like the
  // implementation does) so a message regression cannot cancel out in both
  // places. The empty and relative entries parse to an empty scheme: default
  // deny must hold even when there is no scheme to match.
  const blockedUrls = <({String url, String snackbar})>[
    (url: 'foo:bar', snackbar: 'Cannot open foo: links from here'),
    (
      url: 'intent://scan/#Intent;end',
      snackbar: 'Cannot open intent: links from here',
    ),
    (
      url: 'javascript:alert(1)',
      snackbar: 'Cannot open javascript: links from here',
    ),
    (
      url: 'file:///etc/passwd',
      snackbar: 'Cannot open file: links from here',
    ),
    (
      url: 'data:text/html,<h1>hi</h1>',
      snackbar: 'Cannot open data: links from here',
    ),
    (url: '', snackbar: 'Cannot open : links from here'),
    (url: '/relative/path?q=1', snackbar: 'Cannot open : links from here'),
  ];

  for (final c in blockedUrls) {
    testWidgets('refuses non-whitelisted "${c.url}" without launching', (
      tester,
    ) async {
      await tester.pumpWidget(_launchHost(Uri.parse(c.url)));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(
        launcher.launchedUrls,
        isEmpty,
        reason: '"${c.url}" must not launch',
      );
      expect(find.text(c.snackbar), findsOneWidget);
    });
  }

  // `launched` is the exact string the platform must receive. Schemes are
  // case-insensitive (RFC 3986): Dart's Uri normalizes them to lowercase at
  // construction and the helper lowercases defensively, so uppercase and
  // mixed-case web URLs stay whitelisted. A trailing space never reaches the
  // scheme: it is percent-encoded into the launched URL.
  const whitelistedUrls = <({String url, String launched})>[
    (url: 'https://example.com', launched: 'https://example.com'),
    (url: 'http://example.com', launched: 'http://example.com'),
    (url: 'mailto:a@b.c', launched: 'mailto:a@b.c'),
    (url: 'HTTPS://EXAMPLE.COM/Path', launched: 'https://example.com/Path'),
    (url: 'HtTpS://example.com', launched: 'https://example.com'),
    (url: 'https://example.com ', launched: 'https://example.com%20'),
    (
      url: 'mailto:someone@example.com?subject=Hello',
      launched: 'mailto:someone@example.com?subject=Hello',
    ),
  ];

  for (final c in whitelistedUrls) {
    testWidgets('launches whitelisted "${c.url}" through the platform', (
      tester,
    ) async {
      await tester.pumpWidget(_launchHost(Uri.parse(c.url)));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(launcher.launchedUrls, <String>[c.launched]);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  // Leading whitespace cannot even construct a Uri (Uri.parse throws), so it
  // can never reach openUriSafely's Uri-typed boundary. Pinned here so an SDK
  // behavior change would surface as a failure instead of a silent new path
  // into the launcher.
  test('leading-whitespace URLs never parse into a launchable Uri', () {
    expect(Uri.tryParse(' https://example.com'), isNull);
    expect(Uri.tryParse(' https://example.com '), isNull);
  });
}

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

  const blockedUrls = <String>[
    'foo:bar',
    'intent://scan/#Intent;end',
    'javascript:alert(1)',
    'file:///etc/passwd',
  ];

  for (final url in blockedUrls) {
    testWidgets('refuses non-whitelisted $url without launching', (
      tester,
    ) async {
      final uri = Uri.parse(url);
      await tester.pumpWidget(_launchHost(uri));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(launcher.launchedUrls, isEmpty, reason: '$url must not launch');
      expect(
        find.text('Cannot open ${uri.scheme}: links from here'),
        findsOneWidget,
      );
    });
  }

  const whitelistedUrls = <String>[
    'https://example.com',
    'http://example.com',
    'mailto:a@b.c',
  ];

  for (final url in whitelistedUrls) {
    testWidgets('launches whitelisted $url through the platform', (
      tester,
    ) async {
      await tester.pumpWidget(_launchHost(Uri.parse(url)));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(launcher.launchedUrls, <String>[url]);
      expect(find.textContaining('Cannot open'), findsNothing);
    });
  }
}

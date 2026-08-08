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

  testWidgets('refuses a disallowed scheme without launching', (tester) async {
    await tester.pumpWidget(_launchHost(Uri.parse('javascript:alert(1)')));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(launcher.launchedUrls, isEmpty);
    expect(
      find.text('Cannot open javascript: links from here'),
      findsOneWidget,
    );
  });

  testWidgets('launches an allowed https URL through the platform', (
    tester,
  ) async {
    await tester.pumpWidget(_launchHost(Uri.parse('https://example.com')));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(launcher.launchedUrls, <String>['https://example.com']);
    expect(find.textContaining('Cannot open'), findsNothing);
  });
}

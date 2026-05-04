import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/screens/about.dart';
import 'package:notif/services/app_settings.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('About loading state is baseline-safe', (tester) async {
    _setSurfaceSize(tester, const Size(800, 1400));

    final controller = AppSettingsController();
    addTearDown(controller.dispose);

    final completer = Completer<PackageInfo>();
    await tester.pumpWidget(
      _buildAboutApp(
        controller: controller,
        packageInfoFuture: completer.future,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('About keeps a 2x2 section grid on wide screens', (tester) async {
    _setSurfaceSize(tester, const Size(1200, 1400));

    final controller = AppSettingsController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _buildAboutApp(
        controller: controller,
        packageInfoFuture: Future.value(_fakePackageInfo()),
      ),
    );
    await tester.pumpAndSettle();

    final pageNotes = tester.getTopLeft(
      find.byKey(const ValueKey('aboutSectionPageNotes')),
    );
    final designSystem = tester.getTopLeft(
      find.byKey(const ValueKey('aboutSectionDesignSystem')),
    );
    final typography = tester.getTopLeft(
      find.byKey(const ValueKey('aboutSectionTypography')),
    );
    final contact = tester.getTopLeft(
      find.byKey(const ValueKey('aboutSectionContact')),
    );
    final pageNotesSize = tester.getSize(
      find.byKey(const ValueKey('aboutSectionPageNotes')),
    );
    final designSystemSize = tester.getSize(
      find.byKey(const ValueKey('aboutSectionDesignSystem')),
    );
    final typographySize = tester.getSize(
      find.byKey(const ValueKey('aboutSectionTypography')),
    );
    final contactSize = tester.getSize(
      find.byKey(const ValueKey('aboutSectionContact')),
    );
    final heroIntro = tester.getTopLeft(
      find.byKey(const ValueKey('aboutHeroIntro')),
    );
    final heroMeta = tester.getTopLeft(
      find.byKey(const ValueKey('aboutHeroMeta')),
    );
    final heroIntroSize = tester.getSize(
      find.byKey(const ValueKey('aboutHeroIntro')),
    );
    final heroMetaSize = tester.getSize(
      find.byKey(const ValueKey('aboutHeroMeta')),
    );
    final heroGitHub = tester.getTopLeft(
      find.byKey(const ValueKey('aboutHeroActionGitHub')),
    );
    final heroPlaceholder = tester.getTopLeft(
      find.byKey(const ValueKey('aboutHeroActionPlaceholder')),
    );
    final heroDiscord = tester.getTopLeft(
      find.byKey(const ValueKey('aboutHeroActionDiscord')),
    );
    final heroContact = tester.getTopLeft(
      find.byKey(const ValueKey('aboutHeroActionContact')),
    );

    expect(designSystem.dy, moreOrLessEquals(pageNotes.dy, epsilon: 1));
    expect(designSystem.dx, greaterThan(pageNotes.dx + 100));
    expect(typography.dx, moreOrLessEquals(pageNotes.dx, epsilon: 1));
    expect(typography.dy, greaterThan(pageNotes.dy + 40));
    expect(contact.dy, moreOrLessEquals(typography.dy, epsilon: 1));
    expect(contact.dx, greaterThan(typography.dx + 100));
    expect(
      designSystemSize.height,
      moreOrLessEquals(pageNotesSize.height, epsilon: 1),
    );
    expect(
      contactSize.height,
      moreOrLessEquals(typographySize.height, epsilon: 1),
    );
    expect(heroMeta.dx, greaterThan(heroIntro.dx + 100));
    expect(
      heroMetaSize.height,
      moreOrLessEquals(heroIntroSize.height, epsilon: 1),
    );
    expect(heroPlaceholder.dy, moreOrLessEquals(heroGitHub.dy, epsilon: 1));
    expect(heroDiscord.dy, moreOrLessEquals(heroGitHub.dy, epsilon: 1));
    expect(heroContact.dy, moreOrLessEquals(heroGitHub.dy, epsilon: 1));
  });
}

Widget _buildAboutApp({
  required AppSettingsController controller,
  required Future<PackageInfo> packageInfoFuture,
}) {
  const colorway = NotifColorway.daybreak;
  return ChangeNotifierProvider<AppSettingsController>.value(
    value: controller,
    child: MaterialApp(
      theme: buildNotifTheme(colorway: colorway, fontSet: NotifFontSet.current),
      home: AboutPage(packageInfoFuture: packageInfoFuture),
    ),
  );
}

PackageInfo _fakePackageInfo() {
  return PackageInfo(
    appName: 'Notif',
    packageName: 'notif',
    version: '0.0.2-alpha',
    buildNumber: '1',
    buildSignature: '',
  );
}

void _setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

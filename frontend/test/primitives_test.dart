import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

Widget _wrapApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      extensions: [
        NotifTokens.build(NotifColorway.dusk1),
        NotifTextTheme.forSet(NotifFontSet.current),
      ],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('NotifButton', () {
    testWidgets('primary variant announces as a button to screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrapApp(
          NotifButton(
            label: 'Test',
            onPressed: () {},
            variant: NotifButtonVariant.primary,
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(NotifButton)),
        matchesSemantics(
          label: 'TEST',
          isButton: true,
          isEnabled: true,
          isFocusable: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('primary variant focuses via Tab and activates via Enter', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrapApp(
          NotifButton(
            label: 'Test',
            onPressed: () => taps++,
            variant: NotifButtonVariant.primary,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.context,
        isNotNull,
        reason: 'Tab should move focus into the NotifButton subtree',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('disabled button is announced as disabled and ignores taps', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      int taps = 0;

      await tester.pumpWidget(
        _wrapApp(
          const NotifButton(
            label: 'Disabled',
            onPressed: null,
            variant: NotifButtonVariant.primary,
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(NotifButton)),
        matchesSemantics(
          label: 'DISABLED',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      await tester.tap(find.text('DISABLED'));
      await tester.pump();
      expect(taps, 0);

      handle.dispose();
    });

    testWidgets('ghost variant renders and is tappable', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrapApp(
          NotifButton(
            label: 'Ghost',
            onPressed: () => taps++,
            variant: NotifButtonVariant.ghost,
          ),
        ),
      );

      await tester.tap(find.text('GHOST'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('link variant renders and is tappable', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrapApp(
          NotifButton(
            label: 'Link',
            onPressed: () => taps++,
            variant: NotifButtonVariant.link,
          ),
        ),
      );

      await tester.tap(find.text('LINK'));
      await tester.pump();
      expect(taps, 1);
    });
  });
}

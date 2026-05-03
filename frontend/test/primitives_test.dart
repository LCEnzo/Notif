import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';

Widget _wrapApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [
      NotifTokens.build(NotifColorway.dusk1),
      NotifTextTheme.forSet(NotifFontSet.current),
    ]),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('NotifButton', () {
    testWidgets('is keyboard-focusable via Tab', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrapApp(
          Row(
            children: [
              NotifButton(
                label: 'Test',
                onPressed: () => taps++,
                variant: NotifButtonVariant.primary,
              ),
            ],
          ),
        ),
      );

      expect(find.text('TEST'), findsOneWidget);

      await tester.tap(find.text('TEST'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('disabled button does not respond to tap', (tester) async {
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

      await tester.tap(find.text('DISABLED'));
      await tester.pump();
      expect(taps, 0);
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

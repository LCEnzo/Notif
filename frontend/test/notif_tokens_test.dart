import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_tokens.dart';

void main() {
  group('NotifTokens.lerp', () {
    test('interpolates same-colorway color and numeric fields', () {
      final from = NotifTokens.build(NotifColorway.dusk1).copyWith(
        ink: const Color(0xFF000000),
        accent: const Color(0xFF102030),
        halftoneBlend: BlendMode.multiply,
        grainOpacity: 0.2,
      );
      final to = NotifTokens.build(NotifColorway.dusk1).copyWith(
        ink: const Color(0xFFFFFFFF),
        accent: const Color(0xFF304050),
        halftoneBlend: BlendMode.screen,
        grainOpacity: 0.8,
      );

      final beforeCut = from.lerp(to, 0.25);
      final afterCut = from.lerp(to, 0.75);

      expect(beforeCut.colorway, NotifColorway.dusk1);
      expect(beforeCut.ink, Color.lerp(from.ink, to.ink, 0.25));
      expect(beforeCut.accent, Color.lerp(from.accent, to.accent, 0.25));
      expect(beforeCut.halftoneBlend, BlendMode.multiply);
      expect(beforeCut.grainOpacity, closeTo(0.35, 0.0001));

      expect(afterCut.ink, Color.lerp(from.ink, to.ink, 0.75));
      expect(afterCut.halftoneBlend, BlendMode.screen);
      expect(afterCut.grainOpacity, closeTo(0.65, 0.0001));
    });

    test('snaps between different colorways at the midpoint', () {
      final from = NotifTokens.build(NotifColorway.dusk1);
      final to = NotifTokens.build(NotifColorway.daybreak);

      expect(identical(from.lerp(to, 0.49), from), isTrue);
      expect(identical(from.lerp(to, 0.5), to), isTrue);
      expect(identical(from.lerp(to, 1), to), isTrue);
    });
  });
}

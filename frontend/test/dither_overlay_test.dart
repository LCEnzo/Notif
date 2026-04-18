import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_design_tokens.dart';
import 'package:notif/commons/notif_tokens.dart';

void main() {
  test('dither overlay palette follows the active colorway', () {
    final tokens = NotifTokens.build(NotifColorway.daybreak);
    final palette = ditherOverlayPaletteFor(tokens);

    expect(palette.neutral, tokens.ink);
    expect(palette.accent, tokens.accent);
    expect(palette.neutral, isNot(NotifDesignTokens.structText));
    expect(palette.accent, isNot(NotifDesignTokens.accentText));
  });
}

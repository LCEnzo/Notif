import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notif/commons/notif_text_theme.dart';

void main() {
  group('NotifTextTheme.forSet', () {
    test('binds current roles to the current font families', () {
      final theme = NotifTextTheme.forSet(NotifFontSet.current);

      expect(theme.display.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.title.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.heading.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.eyebrow.fontFamily, NotifFontFamilies.skyling);
      expect(theme.body.fontFamily, NotifFontFamilies.skyling);
      expect(theme.bodyLong.fontFamily, NotifFontFamilies.skyling);
      expect(theme.micro.fontFamily, NotifFontFamilies.skyling);
      expect(theme.code.fontFamily, NotifFontFamilies.suisseMono);
    });

    test('binds experiment roles to the experiment font families', () {
      final theme = NotifTextTheme.forSet(NotifFontSet.experiment);

      expect(theme.display.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.title.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.heading.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.eyebrow.fontFamily, NotifFontFamilies.jetBrainsMono);
      expect(theme.body.fontFamily, NotifFontFamilies.interTight);
      expect(theme.bodyLong.fontFamily, NotifFontFamilies.newsreader);
      expect(theme.micro.fontFamily, NotifFontFamilies.jetBrainsMono);
      expect(theme.code.fontFamily, NotifFontFamilies.jetBrainsMono);
    });

    test('binds hybrid roles to current families with italic bodyLong', () {
      final theme = NotifTextTheme.forSet(NotifFontSet.hybrid);

      expect(theme.display.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.title.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.heading.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.eyebrow.fontFamily, NotifFontFamilies.suisseMono);
      expect(theme.body.fontFamily, NotifFontFamilies.suisseMono);
      expect(theme.bodyLong.fontFamily, NotifFontFamilies.instrumentSerif);
      expect(theme.bodyLong.fontStyle, FontStyle.italic);
      expect(theme.micro.fontFamily, NotifFontFamilies.suisseMono);
      expect(theme.code.fontFamily, NotifFontFamilies.suisseMono);
    });
  });
}

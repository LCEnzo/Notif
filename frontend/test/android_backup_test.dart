import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android app holds a refresh token. Backup defaults to enabled, so
/// without these settings a Google cloud backup or a device-to-device transfer
/// carries a working session onto another device.
void main() {
  test('Android backup and transfer cannot carry the session off-device', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      reason: 'API 31+ device-to-device transfer is governed by these rules, '
          'not by allowBackup',
    );

    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    );
    expect(rules.existsSync(), isTrue);

    final rulesXml = rules.readAsStringSync();
    for (final section in ['<cloud-backup>', '<device-transfer>']) {
      expect(rulesXml, contains(section));
    }
    for (final domain in ['root', 'file', 'database', 'sharedpref']) {
      expect(
        rulesXml.split('domain="$domain"').length - 1,
        2,
        reason: '$domain must be excluded from both backup and transfer',
      );
    }
  });
}

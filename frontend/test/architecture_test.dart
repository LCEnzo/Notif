import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  test('SharedPreferences access stays in persistence boundary', () {
    final violations = <String>[];
    for (final file in libFiles) {
      final path = _normalize(file.path);
      if (path == 'lib/services/persistence.dart') {
        continue;
      }
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) {
          continue;
        }
        if (line.contains('SharedPreferences')) {
          violations.add(path);
          break;
        }
      }
    }

    expect(violations, isEmpty);
  });

  test('Dio imports stay in HTTP and failure boundaries', () {
    final allowed = {
      'lib/services/api_client.dart',
      'lib/services/dio_credentials.dart',
      'lib/services/dio_credentials_stub.dart',
      'lib/services/dio_credentials_web.dart',
      'lib/services/failures.dart',
    };
    final violations = <String>[];

    for (final file in libFiles) {
      final path = _normalize(file.path);
      if (allowed.contains(path)) {
        continue;
      }
      if (file.readAsStringSync().contains("package:dio/dio.dart")) {
        violations.add(path);
      }
    }

    expect(violations, isEmpty);
  });

  test('raw JSON casts stay in parser boundary files', () {
    final allowed = {
      'lib/services/api_client.dart',
      'lib/services/json_contracts.dart',
    };
    final pattern = RegExp(r'\bas\s+(Map|List|String|int|double|bool)\b');
    final violations = <String>[];

    for (final file in libFiles) {
      final path = _normalize(file.path);
      if (allowed.contains(path)) {
        continue;
      }
      if (pattern.hasMatch(file.readAsStringSync())) {
        violations.add(path);
      }
    }

    expect(violations, isEmpty);
  });
}

String _normalize(String path) => path.replaceAll(r'\', '/');

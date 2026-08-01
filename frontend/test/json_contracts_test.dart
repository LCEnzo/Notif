import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/json_contracts.dart';

void main() {
  JsonCursor cursor(Object? value) {
    return JsonCursor.root(endpoint: 'GET /example/', value: value);
  }

  test('reads nested values', () {
    final json = cursor({
      'results': [
        {'id': 42, 'name': ' Source '},
      ],
    });

    expect(json.field('results').index(0).field('id').integer(), 42);
    expect(json.field('results').index(0).field('name').string(), 'Source');
  });

  test('reports exact path for malformed value', () {
    final json = cursor({
      'results': [
        {'id': false},
      ],
    });

    expect(
      () => json.field('results').index(0).field('id').integer(),
      throwsA(
        isA<ContractViolation>()
            .having((error) => error.endpoint, 'endpoint', 'GET /example/')
            .having((error) => error.path, 'path', r'$.results[0].id')
            .having((error) => error.expected, 'expected', 'integer')
            .having((error) => error.actual, 'actual', 'boolean'),
      ),
    );
  });
}

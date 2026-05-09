class ContractViolation implements Exception {
  const ContractViolation({
    required this.endpoint,
    required this.path,
    required this.expected,
    required this.actual,
    this.cause,
  });

  final String endpoint;
  final String path;
  final String expected;
  final String actual;
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' Cause: $cause';
    return 'ContractViolation($endpoint at $path): expected $expected, '
        'got $actual.$suffix';
  }
}

class JsonCursor {
  const JsonCursor.root({required this.endpoint, required this.value})
    : path = r'$';

  const JsonCursor._({
    required this.endpoint,
    required this.path,
    required this.value,
  });

  final String endpoint;
  final String path;
  final Object? value;

  bool get isNull => value == null;

  JsonCursor field(String key) {
    final objectValue = object();
    if (!objectValue.containsKey(key)) {
      throw _violation('field "$key"', 'missing field');
    }
    return JsonCursor._(
      endpoint: endpoint,
      path: '$path.$key',
      value: objectValue[key],
    );
  }

  JsonCursor? optionalField(String key) {
    final objectValue = object();
    if (!objectValue.containsKey(key) || objectValue[key] == null) {
      return null;
    }
    return JsonCursor._(
      endpoint: endpoint,
      path: '$path.$key',
      value: objectValue[key],
    );
  }

  bool hasNonNullField(String key) {
    final objectValue = object();
    return objectValue.containsKey(key) && objectValue[key] != null;
  }

  JsonCursor index(int index) {
    final arrayValue = array();
    if (index < 0 || index >= arrayValue.length) {
      throw _violation('array index $index', 'missing index');
    }
    return JsonCursor._(
      endpoint: endpoint,
      path: '$path[$index]',
      value: arrayValue[index],
    );
  }

  Map<String, Object?> object() {
    final raw = value;
    if (raw is! Map<Object?, Object?>) {
      throw _violation('JSON object', describeJsonShape(raw));
    }

    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw _violation(
          'JSON object with string keys',
          'key ${key.runtimeType}',
        );
      }
      result[key] = entry.value;
    }
    return result;
  }

  List<Object?> array() {
    final raw = value;
    if (raw is! List<Object?>) {
      throw _violation('JSON array', describeJsonShape(raw));
    }
    return List<Object?>.unmodifiable(raw);
  }

  List<JsonCursor> items() {
    final values = array();
    return [
      for (var i = 0; i < values.length; i += 1)
        JsonCursor._(
          endpoint: endpoint,
          path: '$path[$i]',
          value: values[i],
        ),
    ];
  }

  String string({bool allowEmpty = true}) {
    final raw = value;
    if (raw is! String) {
      throw _violation('string', describeJsonShape(raw));
    }
    final normalized = raw.trim();
    if (!allowEmpty && normalized.isEmpty) {
      throw _violation('non-empty string', 'empty string');
    }
    return normalized;
  }

  String? nullableString({bool allowEmpty = true}) {
    if (value == null) {
      return null;
    }
    return string(allowEmpty: allowEmpty);
  }

  int integer() {
    final raw = value;
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    throw _violation('integer', describeJsonShape(raw));
  }

  int? nullableInteger() {
    if (value == null) {
      return null;
    }
    return integer();
  }

  bool boolean() {
    final raw = value;
    if (raw is bool) {
      return raw;
    }
    throw _violation('boolean', describeJsonShape(raw));
  }

  DateTime dateTime() {
    final raw = string(allowEmpty: false);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw _violation('ISO-8601 datetime string', 'invalid datetime string');
    }
    return parsed.toLocal();
  }

  DateTime? nullableDateTime() {
    if (value == null) {
      return null;
    }
    return dateTime();
  }

  ContractViolation _violation(String expectedValue, String actualValue) {
    return ContractViolation(
      endpoint: endpoint,
      path: path,
      expected: expectedValue,
      actual: actualValue,
    );
  }
}

String describeJsonShape(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is Map<Object?, Object?>) {
    return 'JSON object';
  }
  if (value is List<Object?>) {
    return 'JSON array';
  }
  if (value is String) {
    return value.isEmpty ? 'empty string' : 'string';
  }
  if (value is int) {
    return 'integer';
  }
  if (value is num) {
    return 'number';
  }
  if (value is bool) {
    return 'boolean';
  }
  return value.runtimeType.toString();
}

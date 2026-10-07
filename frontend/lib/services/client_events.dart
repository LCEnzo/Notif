import 'package:flutter/foundation.dart';
import 'package:notif/generated/openapi.swagger.dart' as api;
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/failures.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String _gitHash = String.fromEnvironment('GIT_HASH', defaultValue: '');

/// `maxLength` of each string field of the schema's `ClientEventRequest`,
/// keyed by wire name. The generated model does not carry these, and the
/// server rejects an overlong field with a 400 rather than truncating it.
@visibleForTesting
const Map<String, int> clientEventFieldLimits = {
  'route': 200,
  'endpoint': 200,
  'request_id': 120,
  'contract_path': 200,
  'expected': 500,
  'actual': 500,
  'app_version': 60,
  'git_hash': 80,
  'browser': 200,
  'message': 500,
  'stack': 2000,
};

/// Best-effort: a report that cannot be delivered is dropped, never retried.
Future<void> reportClientFailure({
  required AppSettingsController? settings,
  required Object error,
  StackTrace? stackTrace,
  String? route,
  String? endpoint,
}) async {
  final failure = AppFailure.from(error, endpoint: endpoint);
  final request = api.ClientEventRequest(
    category: failure.category.wire,
    route: route,
    endpoint: failure.endpoint,
    contractPath: failure.contractPath,
    expected: failure.expected,
    actual: failure.actual,
    appVersion: await _loadAppVersion(),
    gitHash: _gitHash,
    browser: _browserSummary(),
    message: failure.message,
    stack: stackTrace?.toString(),
  );

  try {
    await apiPostWithoutSession(
      '/client-events/',
      settings: settings,
      baseUrl: apiBaseUrlForError(error, settings),
      headers: jsonHeaders,
      body: clientEventBody(request),
    );
  } on Exception catch (reportError) {
    if (kDebugMode) {
      debugPrint('reportClientFailure failed: $reportError');
    }
  }
}

/// The wire body for [request]: absent fields omitted (the schema makes them
/// optional, not nullable) and every string clipped to its limit.
@visibleForTesting
Map<String, dynamic> clientEventBody(api.ClientEventRequest request) {
  final body = request.toJson()..removeWhere((_, value) => value == null);
  for (final MapEntry(key: field, value: limit)
      in clientEventFieldLimits.entries) {
    final value = body[field];
    if (value is String) {
      body[field] = clipToLength(value, limit);
    }
  }
  return body;
}

/// [value] cut to at most [max] UTF-16 code units without splitting a
/// surrogate pair. The server counts code points, so this never overshoots.
@visibleForTesting
String clipToLength(String value, int max) {
  if (value.length <= max) {
    return value;
  }
  var end = max;
  if (end > 0 && _isHighSurrogate(value.codeUnitAt(end - 1))) {
    end -= 1;
  }
  return value.substring(0, end);
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

Future<String> _loadAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.isEmpty ? '' : '+${info.buildNumber}';
    return '${info.version}$build';
  } on Exception {
    return '';
  }
}

String _browserSummary() {
  if (kIsWeb) {
    return 'web';
  }
  return defaultTargetPlatform.name;
}

import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/failures.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _jsonHeaders = {'Content-Type': 'application/json'};
const String _gitHash = String.fromEnvironment('GIT_HASH', defaultValue: '');

Future<void> reportClientFailure({
  required AppSettingsController? settings,
  required Object error,
  StackTrace? stackTrace,
  String? route,
  String? endpoint,
}) async {
  final failure = AppFailure.from(error, endpoint: endpoint);
  final packageInfo = await _loadPackageInfo();

  try {
    await apiPostWithoutSession(
      '/client-events/',
      settings: settings,
      baseUrl: apiBaseUrlForError(error, settings),
      headers: _jsonHeaders,
      body: {
        'category': failure.category.wireName,
        'route': route ?? '',
        'endpoint': failure.endpoint ?? endpoint ?? '',
        'contract_path': failure.contractPath ?? '',
        'expected': failure.expected ?? '',
        'actual': failure.actual ?? '',
        'app_version': packageInfo,
        'git_hash': _gitHash,
        'browser': _browserSummary(),
        'message': failure.message,
        'stack': stackTrace?.toString() ?? '',
      },
    );
  } on Exception catch (reportError) {
    if (kDebugMode) {
      debugPrint('reportClientFailure failed: $reportError');
    }
  }
}

Future<String> _loadPackageInfo() async {
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

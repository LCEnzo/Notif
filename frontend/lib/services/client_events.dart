import 'package:flutter/foundation.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/failures.dart';
import 'package:notif/services/json_contracts.dart';
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
  final failure = AppFailure.from(
    error,
    endpoint: endpoint,
  );
  final packageInfo = await _loadPackageInfo();
  final contract = error is ContractViolation ? error : null;

  try {
    await apiPost(
      '/client-events/',
      settings: settings,
      headers: _jsonHeaders,
      body: {
        // Every free-text field is capped at the sink's max_length, because
        // DRF rejects over-length values outright rather than truncating -
        // an uncapped stack trace would 400 and lose the whole report.
        'category': failure.category.wireName,
        'route': _capped(route ?? '', 200),
        'endpoint': _capped(failure.endpoint ?? endpoint ?? '', 200),
        'contract_path': _capped(
          failure.contractPath ?? contract?.path ?? '',
          200,
        ),
        'expected': _capped(failure.expected ?? contract?.expected ?? '', 500),
        'actual': _capped(failure.actual ?? contract?.actual ?? '', 500),
        'app_version': _capped(packageInfo, 60),
        'git_hash': _capped(_gitHash, 80),
        'browser': _capped(_browserSummary(), 200),
        // debugMessage, not the user copy: this channel exists for diagnosis,
        // and the transport detail is the part that identifies an outage.
        'message': _capped(failure.debugMessage, 500),
        'stack': _capped(stackTrace?.toString() ?? '', 2000),
      },
    );
  } on Exception catch (reportError) {
    if (kDebugMode) {
      debugPrint('reportClientFailure failed: $reportError');
    }
  }
}

String _capped(String value, int maxLength) =>
    value.length <= maxLength ? value : value.substring(0, maxLength);

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

import 'package:notif/generated/openapi.swagger.dart' as api;
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';

const String healthIngestPath = '/health/ingest/';
const String healthIngestEndpoint = 'POST $healthIngestPath';

/// Sends one prepared batch body. Errors propagate as the api client raised
/// them; the sync engine classifies them.
abstract interface class HealthIngestUploader {
  Future<api.HealthIngestResponse> upload(String body);
}

/// Through [apiPost], so the credential, origin pinning and fallback rules are
/// the app's own. The body goes out as the exact string batching measured.
class ApiHealthIngestUploader implements HealthIngestUploader {
  const ApiHealthIngestUploader(this._settings);

  final AppSettingsController? _settings;

  @override
  Future<api.HealthIngestResponse> upload(String body) async {
    final response = await apiPost(
      healthIngestPath,
      settings: _settings,
      headers: jsonHeaders,
      body: body,
    );
    final json = expectSuccessJson(response, 'Health ingest');
    return parseContract(
      'HealthIngestResponse',
      () => api.HealthIngestResponse.fromJson(json),
    );
  }
}

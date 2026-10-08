import 'package:notif/generated/openapi.swagger.dart' as api;
import 'package:notif/services/health/uploader.dart';

/// Records every body; throws whatever [failures] holds for that call index.
class FakeUploader implements HealthIngestUploader {
  final List<String> bodies = [];
  final Map<int, Exception> failures = {};
  int calls = 0;

  @override
  Future<api.HealthIngestResponse> upload(String body) async {
    final index = calls++;
    final failure = failures[index];
    if (failure != null) throw failure;
    bodies.add(body);
    return const api.HealthIngestResponse(
      batchId: 1,
      recordsWritten: 0,
      recordsIgnored: 0,
      recordsDeleted: 0,
      aggregatesWritten: 0,
      aggregatesIgnored: 0,
    );
  }
}

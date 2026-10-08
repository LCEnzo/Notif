import 'package:notif/services/health/scheduler.dart';

/// Records what the app asked WorkManager for.
class FakeHealthScheduler implements HealthScheduler {
  final List<String> calls = [];

  @override
  Future<void> ensurePeriodicSync() async => calls.add('periodic');

  @override
  Future<void> enqueueSyncNow() async => calls.add('now');

  @override
  Future<void> ensureBackfill() async => calls.add('backfill');

  @override
  Future<void> cancelBackfill() async => calls.add('cancel backfill');
}

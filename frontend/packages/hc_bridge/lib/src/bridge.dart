import 'package:flutter/services.dart';
import 'package:hc_bridge/src/errors.dart';
import 'package:hc_bridge/src/models.dart';

/// Every operation either returns its typed result or throws
/// [HcBridgeException].
abstract interface class HcBridge {
  Future<HcStatus> status();

  /// Shows Health Connect's permission sheet for [permissions] and returns the
  /// ones granted afterwards. Needs a foreground activity.
  Future<Set<String>> requestPermissions(Set<String> permissions);

  /// One page of [type] records in `[startMs, endMs)`.
  Future<HcRecordPage> readRecords(
    HcRecordType type, {
    required int startMs,
    required int endMs,
    String? pageToken,
    int pageSize,
  });

  /// `aggregateGroupByDuration` in one-hour slices. [startMs] and [endMs] fall
  /// on UTC hours, at most 744 hours apart.
  Future<HcAggregateWindow> aggregateHourly(
    HcAggregateMetric metric, {
    required int startMs,
    required int endMs,
  });

  Future<String> changesToken(Set<HcRecordType> types);

  Future<HcChangesPage> changes(String token);

  /// `aggregateGroupByPeriod` by local calendar month since 2015 for [types].
  Future<HcCoverage> coverageProbe(Set<HcRecordType> types);
}

class MethodChannelHcBridge implements HcBridge {
  const MethodChannelHcBridge({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'com.lcenzo.notif/hc_bridge';

  final MethodChannel _channel;

  @override
  Future<HcStatus> status() async =>
      HcStatus.decode(await _invoke('status', null));

  @override
  Future<Set<String>> requestPermissions(Set<String> permissions) async {
    final raw = await _invoke('requestPermissions', {
      'permissions': permissions.toList(growable: false),
    });
    if (raw is! List<Object?> || raw.any((item) => item is! String)) {
      throw const HcBridgeException(
        HcErrorCode.malformedResponse,
        'expected a list of permission names',
        operation: 'requestPermissions',
      );
    }
    return raw.cast<String>().toSet();
  }

  @override
  Future<HcRecordPage> readRecords(
    HcRecordType type, {
    required int startMs,
    required int endMs,
    String? pageToken,
    int pageSize = 1000,
  }) async => HcRecordPage.decode(
    await _invoke('readRecords', {
      'type': type.wire,
      'start_ms': startMs,
      'end_ms': endMs,
      'page_token': pageToken,
      'page_size': pageSize,
    }),
  );

  @override
  Future<HcAggregateWindow> aggregateHourly(
    HcAggregateMetric metric, {
    required int startMs,
    required int endMs,
  }) async => HcAggregateWindow.decode(
    await _invoke('aggregateHourly', {
      'metric': metric.wire,
      'start_ms': startMs,
      'end_ms': endMs,
    }),
  );

  @override
  Future<String> changesToken(Set<HcRecordType> types) async {
    final raw = await _invoke('changesToken', {
      'types': [for (final type in types) type.wire],
    });
    if (raw is String && raw.isNotEmpty) return raw;
    throw const HcBridgeException(
      HcErrorCode.malformedResponse,
      'expected a non-empty token',
      operation: 'changesToken',
    );
  }

  @override
  Future<HcChangesPage> changes(String token) async =>
      HcChangesPage.decode(await _invoke('changes', {'token': token}));

  @override
  Future<HcCoverage> coverageProbe(Set<HcRecordType> types) async =>
      HcCoverage.decode(
        await _invoke('coverageProbe', {
          'types': [for (final type in types) type.wire],
        }),
      );

  Future<Object?> _invoke(
    String method,
    Map<String, Object?>? arguments,
  ) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw HcBridgeException(
        HcErrorCode.fromWire(error.code),
        error.message ?? error.code,
        operation: method,
      );
    } on MissingPluginException {
      throw HcBridgeException(
        HcErrorCode.unavailable,
        'the Health Connect bridge is not registered on this platform',
        operation: method,
      );
    }
  }
}

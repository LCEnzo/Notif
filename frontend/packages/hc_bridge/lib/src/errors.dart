/// Why a bridge call failed. The wire names are the Kotlin side's error codes.
enum HcErrorCode {
  /// Health Connect is missing, disabled, or needs an update.
  unavailable('unavailable'),

  /// A read permission the call needs is not granted.
  permissionDenied('permission_denied'),

  /// Health Connect's read quota is spent; retry later.
  rateLimited('rate_limited'),

  /// The bridge refused its arguments, or Health Connect refused the request.
  invalidArgument('invalid_argument'),

  /// Health Connect's database failed.
  io('io'),

  /// The IPC to Health Connect failed. Before Android 14 this also covers an
  /// outdated changes token, which the old client reports the same way.
  remote('remote'),

  /// A permission request needs a foreground activity and there is none.
  noActivity('no_activity'),

  /// A permission request is already showing.
  requestInProgress('request_in_progress'),

  /// Anything else the platform threw.
  unexpected('unexpected'),

  /// The platform answered with a shape this side does not understand.
  malformedResponse('malformed_response');

  const HcErrorCode(this.wire);

  final String wire;

  static HcErrorCode fromWire(String? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return unexpected;
  }
}

class HcBridgeException implements Exception {
  const HcBridgeException(this.code, this.message, {required this.operation});

  final HcErrorCode code;
  final String message;

  /// The bridge method that failed, e.g. `readRecords`.
  final String operation;

  @override
  String toString() =>
      'Health Connect $operation failed (${code.wire}): $message';
}

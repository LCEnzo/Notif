// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element_parameter

import 'package:json_annotation/json_annotation.dart';
import 'package:json_annotation/json_annotation.dart' as json;
import 'package:collection/collection.dart';
import 'dart:convert';

import 'openapi.enums.swagger.dart' as enums;
export 'openapi.enums.swagger.dart';

part 'openapi.swagger.g.dart';

@JsonSerializable(explicitToJson: true)
class CaddyAccessLogResponse {
  const CaddyAccessLogResponse({this.configuredPath, required this.results});

  factory CaddyAccessLogResponse.fromJson(Map<String, dynamic> json) =>
      _$CaddyAccessLogResponseFromJson(json);

  static const toJsonFactory = _$CaddyAccessLogResponseToJson;
  Map<String, dynamic> toJson() => _$CaddyAccessLogResponseToJson(this);

  @JsonKey(name: 'configured_path')
  final String? configuredPath;
  @JsonKey(name: 'results', defaultValue: <Object>[])
  final List<Object> results;
  static const fromJsonFactory = _$CaddyAccessLogResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CaddyAccessLogResponse &&
            (identical(other.configuredPath, configuredPath) ||
                const DeepCollectionEquality().equals(
                  other.configuredPath,
                  configuredPath,
                )) &&
            (identical(other.results, results) ||
                const DeepCollectionEquality().equals(other.results, results)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(configuredPath) ^
      const DeepCollectionEquality().hash(results) ^
      runtimeType.hashCode;
}

extension $CaddyAccessLogResponseExtension on CaddyAccessLogResponse {
  CaddyAccessLogResponse copyWith({
    String? configuredPath,
    List<Object>? results,
  }) {
    return CaddyAccessLogResponse(
      configuredPath: configuredPath ?? this.configuredPath,
      results: results ?? this.results,
    );
  }

  CaddyAccessLogResponse copyWithWrapped({
    Wrapped<String?>? configuredPath,
    Wrapped<List<Object>>? results,
  }) {
    return CaddyAccessLogResponse(
      configuredPath: (configuredPath != null
          ? configuredPath.value
          : this.configuredPath),
      results: (results != null ? results.value : this.results),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ChangePasswordRequest {
  const ChangePasswordRequest({this.currentPassword, this.newPassword});

  factory ChangePasswordRequest.fromJson(Map<String, dynamic> json) =>
      _$ChangePasswordRequestFromJson(json);

  static const toJsonFactory = _$ChangePasswordRequestToJson;
  Map<String, dynamic> toJson() => _$ChangePasswordRequestToJson(this);

  @JsonKey(name: 'current_password')
  final String? currentPassword;
  @JsonKey(name: 'new_password')
  final String? newPassword;
  static const fromJsonFactory = _$ChangePasswordRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ChangePasswordRequest &&
            (identical(other.currentPassword, currentPassword) ||
                const DeepCollectionEquality().equals(
                  other.currentPassword,
                  currentPassword,
                )) &&
            (identical(other.newPassword, newPassword) ||
                const DeepCollectionEquality().equals(
                  other.newPassword,
                  newPassword,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(currentPassword) ^
      const DeepCollectionEquality().hash(newPassword) ^
      runtimeType.hashCode;
}

extension $ChangePasswordRequestExtension on ChangePasswordRequest {
  ChangePasswordRequest copyWith({
    String? currentPassword,
    String? newPassword,
  }) {
    return ChangePasswordRequest(
      currentPassword: currentPassword ?? this.currentPassword,
      newPassword: newPassword ?? this.newPassword,
    );
  }

  ChangePasswordRequest copyWithWrapped({
    Wrapped<String?>? currentPassword,
    Wrapped<String?>? newPassword,
  }) {
    return ChangePasswordRequest(
      currentPassword: (currentPassword != null
          ? currentPassword.value
          : this.currentPassword),
      newPassword: (newPassword != null ? newPassword.value : this.newPassword),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ClientEventAccepted {
  const ClientEventAccepted({required this.status});

  factory ClientEventAccepted.fromJson(Map<String, dynamic> json) =>
      _$ClientEventAcceptedFromJson(json);

  static const toJsonFactory = _$ClientEventAcceptedToJson;
  Map<String, dynamic> toJson() => _$ClientEventAcceptedToJson(this);

  @JsonKey(name: 'status')
  final String status;
  static const fromJsonFactory = _$ClientEventAcceptedFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ClientEventAccepted &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^ runtimeType.hashCode;
}

extension $ClientEventAcceptedExtension on ClientEventAccepted {
  ClientEventAccepted copyWith({String? status}) {
    return ClientEventAccepted(status: status ?? this.status);
  }

  ClientEventAccepted copyWithWrapped({Wrapped<String>? status}) {
    return ClientEventAccepted(
      status: (status != null ? status.value : this.status),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ClientEventRequest {
  const ClientEventRequest({
    required this.category,
    this.route,
    this.endpoint,
    this.requestId,
    this.contractPath,
    this.expected,
    this.actual,
    this.appVersion,
    this.gitHash,
    this.browser,
    this.message,
    this.stack,
  });

  factory ClientEventRequest.fromJson(Map<String, dynamic> json) =>
      _$ClientEventRequestFromJson(json);

  static const toJsonFactory = _$ClientEventRequestToJson;
  Map<String, dynamic> toJson() => _$ClientEventRequestToJson(this);

  @JsonKey(
    name: 'category',
    toJson: categoryEnumToJson,
    fromJson: categoryEnumFromJson,
  )
  final enums.CategoryEnum category;
  @JsonKey(name: 'route')
  final String? route;
  @JsonKey(name: 'endpoint')
  final String? endpoint;
  @JsonKey(name: 'request_id')
  final String? requestId;
  @JsonKey(name: 'contract_path')
  final String? contractPath;
  @JsonKey(name: 'expected')
  final String? expected;
  @JsonKey(name: 'actual')
  final String? actual;
  @JsonKey(name: 'app_version')
  final String? appVersion;
  @JsonKey(name: 'git_hash')
  final String? gitHash;
  @JsonKey(name: 'browser')
  final String? browser;
  @JsonKey(name: 'message')
  final String? message;
  @JsonKey(name: 'stack')
  final String? stack;
  static const fromJsonFactory = _$ClientEventRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ClientEventRequest &&
            (identical(other.category, category) ||
                const DeepCollectionEquality().equals(
                  other.category,
                  category,
                )) &&
            (identical(other.route, route) ||
                const DeepCollectionEquality().equals(other.route, route)) &&
            (identical(other.endpoint, endpoint) ||
                const DeepCollectionEquality().equals(
                  other.endpoint,
                  endpoint,
                )) &&
            (identical(other.requestId, requestId) ||
                const DeepCollectionEquality().equals(
                  other.requestId,
                  requestId,
                )) &&
            (identical(other.contractPath, contractPath) ||
                const DeepCollectionEquality().equals(
                  other.contractPath,
                  contractPath,
                )) &&
            (identical(other.expected, expected) ||
                const DeepCollectionEquality().equals(
                  other.expected,
                  expected,
                )) &&
            (identical(other.actual, actual) ||
                const DeepCollectionEquality().equals(other.actual, actual)) &&
            (identical(other.appVersion, appVersion) ||
                const DeepCollectionEquality().equals(
                  other.appVersion,
                  appVersion,
                )) &&
            (identical(other.gitHash, gitHash) ||
                const DeepCollectionEquality().equals(
                  other.gitHash,
                  gitHash,
                )) &&
            (identical(other.browser, browser) ||
                const DeepCollectionEquality().equals(
                  other.browser,
                  browser,
                )) &&
            (identical(other.message, message) ||
                const DeepCollectionEquality().equals(
                  other.message,
                  message,
                )) &&
            (identical(other.stack, stack) ||
                const DeepCollectionEquality().equals(other.stack, stack)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(category) ^
      const DeepCollectionEquality().hash(route) ^
      const DeepCollectionEquality().hash(endpoint) ^
      const DeepCollectionEquality().hash(requestId) ^
      const DeepCollectionEquality().hash(contractPath) ^
      const DeepCollectionEquality().hash(expected) ^
      const DeepCollectionEquality().hash(actual) ^
      const DeepCollectionEquality().hash(appVersion) ^
      const DeepCollectionEquality().hash(gitHash) ^
      const DeepCollectionEquality().hash(browser) ^
      const DeepCollectionEquality().hash(message) ^
      const DeepCollectionEquality().hash(stack) ^
      runtimeType.hashCode;
}

extension $ClientEventRequestExtension on ClientEventRequest {
  ClientEventRequest copyWith({
    enums.CategoryEnum? category,
    String? route,
    String? endpoint,
    String? requestId,
    String? contractPath,
    String? expected,
    String? actual,
    String? appVersion,
    String? gitHash,
    String? browser,
    String? message,
    String? stack,
  }) {
    return ClientEventRequest(
      category: category ?? this.category,
      route: route ?? this.route,
      endpoint: endpoint ?? this.endpoint,
      requestId: requestId ?? this.requestId,
      contractPath: contractPath ?? this.contractPath,
      expected: expected ?? this.expected,
      actual: actual ?? this.actual,
      appVersion: appVersion ?? this.appVersion,
      gitHash: gitHash ?? this.gitHash,
      browser: browser ?? this.browser,
      message: message ?? this.message,
      stack: stack ?? this.stack,
    );
  }

  ClientEventRequest copyWithWrapped({
    Wrapped<enums.CategoryEnum>? category,
    Wrapped<String?>? route,
    Wrapped<String?>? endpoint,
    Wrapped<String?>? requestId,
    Wrapped<String?>? contractPath,
    Wrapped<String?>? expected,
    Wrapped<String?>? actual,
    Wrapped<String?>? appVersion,
    Wrapped<String?>? gitHash,
    Wrapped<String?>? browser,
    Wrapped<String?>? message,
    Wrapped<String?>? stack,
  }) {
    return ClientEventRequest(
      category: (category != null ? category.value : this.category),
      route: (route != null ? route.value : this.route),
      endpoint: (endpoint != null ? endpoint.value : this.endpoint),
      requestId: (requestId != null ? requestId.value : this.requestId),
      contractPath: (contractPath != null
          ? contractPath.value
          : this.contractPath),
      expected: (expected != null ? expected.value : this.expected),
      actual: (actual != null ? actual.value : this.actual),
      appVersion: (appVersion != null ? appVersion.value : this.appVersion),
      gitHash: (gitHash != null ? gitHash.value : this.gitHash),
      browser: (browser != null ? browser.value : this.browser),
      message: (message != null ? message.value : this.message),
      stack: (stack != null ? stack.value : this.stack),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class DeviceSession {
  const DeviceSession({
    this.publicId,
    this.deviceLabel,
    this.transport,
    this.createdAt,
    this.lastUsedAt,
    this.ip,
    this.userAgent,
    this.current,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) =>
      _$DeviceSessionFromJson(json);

  static const toJsonFactory = _$DeviceSessionToJson;
  Map<String, dynamic> toJson() => _$DeviceSessionToJson(this);

  @JsonKey(name: 'public_id')
  final String? publicId;
  @JsonKey(name: 'device_label')
  final String? deviceLabel;
  @JsonKey(
    name: 'transport',
    toJson: transportEnumNullableToJson,
    fromJson: transportEnumNullableFromJson,
  )
  final enums.TransportEnum? transport;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @JsonKey(name: 'last_used_at')
  final DateTime? lastUsedAt;
  @JsonKey(name: 'ip')
  final String? ip;
  @JsonKey(name: 'user_agent')
  final String? userAgent;
  @JsonKey(name: 'current')
  final bool? current;
  static const fromJsonFactory = _$DeviceSessionFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DeviceSession &&
            (identical(other.publicId, publicId) ||
                const DeepCollectionEquality().equals(
                  other.publicId,
                  publicId,
                )) &&
            (identical(other.deviceLabel, deviceLabel) ||
                const DeepCollectionEquality().equals(
                  other.deviceLabel,
                  deviceLabel,
                )) &&
            (identical(other.transport, transport) ||
                const DeepCollectionEquality().equals(
                  other.transport,
                  transport,
                )) &&
            (identical(other.createdAt, createdAt) ||
                const DeepCollectionEquality().equals(
                  other.createdAt,
                  createdAt,
                )) &&
            (identical(other.lastUsedAt, lastUsedAt) ||
                const DeepCollectionEquality().equals(
                  other.lastUsedAt,
                  lastUsedAt,
                )) &&
            (identical(other.ip, ip) ||
                const DeepCollectionEquality().equals(other.ip, ip)) &&
            (identical(other.userAgent, userAgent) ||
                const DeepCollectionEquality().equals(
                  other.userAgent,
                  userAgent,
                )) &&
            (identical(other.current, current) ||
                const DeepCollectionEquality().equals(other.current, current)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(publicId) ^
      const DeepCollectionEquality().hash(deviceLabel) ^
      const DeepCollectionEquality().hash(transport) ^
      const DeepCollectionEquality().hash(createdAt) ^
      const DeepCollectionEquality().hash(lastUsedAt) ^
      const DeepCollectionEquality().hash(ip) ^
      const DeepCollectionEquality().hash(userAgent) ^
      const DeepCollectionEquality().hash(current) ^
      runtimeType.hashCode;
}

extension $DeviceSessionExtension on DeviceSession {
  DeviceSession copyWith({
    String? publicId,
    String? deviceLabel,
    enums.TransportEnum? transport,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    String? ip,
    String? userAgent,
    bool? current,
  }) {
    return DeviceSession(
      publicId: publicId ?? this.publicId,
      deviceLabel: deviceLabel ?? this.deviceLabel,
      transport: transport ?? this.transport,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      ip: ip ?? this.ip,
      userAgent: userAgent ?? this.userAgent,
      current: current ?? this.current,
    );
  }

  DeviceSession copyWithWrapped({
    Wrapped<String?>? publicId,
    Wrapped<String?>? deviceLabel,
    Wrapped<enums.TransportEnum?>? transport,
    Wrapped<DateTime?>? createdAt,
    Wrapped<DateTime?>? lastUsedAt,
    Wrapped<String?>? ip,
    Wrapped<String?>? userAgent,
    Wrapped<bool?>? current,
  }) {
    return DeviceSession(
      publicId: (publicId != null ? publicId.value : this.publicId),
      deviceLabel: (deviceLabel != null ? deviceLabel.value : this.deviceLabel),
      transport: (transport != null ? transport.value : this.transport),
      createdAt: (createdAt != null ? createdAt.value : this.createdAt),
      lastUsedAt: (lastUsedAt != null ? lastUsedAt.value : this.lastUsedAt),
      ip: (ip != null ? ip.value : this.ip),
      userAgent: (userAgent != null ? userAgent.value : this.userAgent),
      current: (current != null ? current.value : this.current),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ErrorDetail {
  const ErrorDetail({required this.detail});

  factory ErrorDetail.fromJson(Map<String, dynamic> json) =>
      _$ErrorDetailFromJson(json);

  static const toJsonFactory = _$ErrorDetailToJson;
  Map<String, dynamic> toJson() => _$ErrorDetailToJson(this);

  @JsonKey(name: 'detail')
  final String detail;
  static const fromJsonFactory = _$ErrorDetailFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ErrorDetail &&
            (identical(other.detail, detail) ||
                const DeepCollectionEquality().equals(other.detail, detail)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(detail) ^ runtimeType.hashCode;
}

extension $ErrorDetailExtension on ErrorDetail {
  ErrorDetail copyWith({String? detail}) {
    return ErrorDetail(detail: detail ?? this.detail);
  }

  ErrorDetail copyWithWrapped({Wrapped<String>? detail}) {
    return ErrorDetail(detail: (detail != null ? detail.value : this.detail));
  }
}

@JsonSerializable(explicitToJson: true)
class ErrorMessage {
  const ErrorMessage({required this.error});

  factory ErrorMessage.fromJson(Map<String, dynamic> json) =>
      _$ErrorMessageFromJson(json);

  static const toJsonFactory = _$ErrorMessageToJson;
  Map<String, dynamic> toJson() => _$ErrorMessageToJson(this);

  @JsonKey(name: 'error')
  final String error;
  static const fromJsonFactory = _$ErrorMessageFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ErrorMessage &&
            (identical(other.error, error) ||
                const DeepCollectionEquality().equals(other.error, error)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(error) ^ runtimeType.hashCode;
}

extension $ErrorMessageExtension on ErrorMessage {
  ErrorMessage copyWith({String? error}) {
    return ErrorMessage(error: error ?? this.error);
  }

  ErrorMessage copyWithWrapped({Wrapped<String>? error}) {
    return ErrorMessage(error: (error != null ? error.value : this.error));
  }
}

@JsonSerializable(explicitToJson: true)
class HealthAggregateBucketRequest {
  const HealthAggregateBucketRequest({
    required this.startMs,
    required this.value,
    required this.dataOrigins,
  });

  factory HealthAggregateBucketRequest.fromJson(Map<String, dynamic> json) =>
      _$HealthAggregateBucketRequestFromJson(json);

  static const toJsonFactory = _$HealthAggregateBucketRequestToJson;
  Map<String, dynamic> toJson() => _$HealthAggregateBucketRequestToJson(this);

  @JsonKey(name: 'start_ms')
  final int startMs;
  @JsonKey(name: 'value')
  final int value;
  @JsonKey(name: 'data_origins', defaultValue: <String>[])
  final List<String> dataOrigins;
  static const fromJsonFactory = _$HealthAggregateBucketRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HealthAggregateBucketRequest &&
            (identical(other.startMs, startMs) ||
                const DeepCollectionEquality().equals(
                  other.startMs,
                  startMs,
                )) &&
            (identical(other.value, value) ||
                const DeepCollectionEquality().equals(other.value, value)) &&
            (identical(other.dataOrigins, dataOrigins) ||
                const DeepCollectionEquality().equals(
                  other.dataOrigins,
                  dataOrigins,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(startMs) ^
      const DeepCollectionEquality().hash(value) ^
      const DeepCollectionEquality().hash(dataOrigins) ^
      runtimeType.hashCode;
}

extension $HealthAggregateBucketRequestExtension
    on HealthAggregateBucketRequest {
  HealthAggregateBucketRequest copyWith({
    int? startMs,
    int? value,
    List<String>? dataOrigins,
  }) {
    return HealthAggregateBucketRequest(
      startMs: startMs ?? this.startMs,
      value: value ?? this.value,
      dataOrigins: dataOrigins ?? this.dataOrigins,
    );
  }

  HealthAggregateBucketRequest copyWithWrapped({
    Wrapped<int>? startMs,
    Wrapped<int>? value,
    Wrapped<List<String>>? dataOrigins,
  }) {
    return HealthAggregateBucketRequest(
      startMs: (startMs != null ? startMs.value : this.startMs),
      value: (value != null ? value.value : this.value),
      dataOrigins: (dataOrigins != null ? dataOrigins.value : this.dataOrigins),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class HealthAggregateWindowRequest {
  const HealthAggregateWindowRequest({
    required this.metric,
    required this.startMs,
    required this.endMs,
    required this.computedAtMs,
    required this.buckets,
  });

  factory HealthAggregateWindowRequest.fromJson(Map<String, dynamic> json) =>
      _$HealthAggregateWindowRequestFromJson(json);

  static const toJsonFactory = _$HealthAggregateWindowRequestToJson;
  Map<String, dynamic> toJson() => _$HealthAggregateWindowRequestToJson(this);

  @JsonKey(
    name: 'metric',
    toJson: healthAggregateMetricEnumToJson,
    fromJson: healthAggregateMetricEnumFromJson,
  )
  final enums.HealthAggregateMetricEnum metric;
  @JsonKey(name: 'start_ms')
  final int startMs;
  @JsonKey(name: 'end_ms')
  final int endMs;
  @JsonKey(name: 'computed_at_ms')
  final int computedAtMs;
  @JsonKey(name: 'buckets', defaultValue: <HealthAggregateBucketRequest>[])
  final List<HealthAggregateBucketRequest> buckets;
  static const fromJsonFactory = _$HealthAggregateWindowRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HealthAggregateWindowRequest &&
            (identical(other.metric, metric) ||
                const DeepCollectionEquality().equals(other.metric, metric)) &&
            (identical(other.startMs, startMs) ||
                const DeepCollectionEquality().equals(
                  other.startMs,
                  startMs,
                )) &&
            (identical(other.endMs, endMs) ||
                const DeepCollectionEquality().equals(other.endMs, endMs)) &&
            (identical(other.computedAtMs, computedAtMs) ||
                const DeepCollectionEquality().equals(
                  other.computedAtMs,
                  computedAtMs,
                )) &&
            (identical(other.buckets, buckets) ||
                const DeepCollectionEquality().equals(other.buckets, buckets)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(metric) ^
      const DeepCollectionEquality().hash(startMs) ^
      const DeepCollectionEquality().hash(endMs) ^
      const DeepCollectionEquality().hash(computedAtMs) ^
      const DeepCollectionEquality().hash(buckets) ^
      runtimeType.hashCode;
}

extension $HealthAggregateWindowRequestExtension
    on HealthAggregateWindowRequest {
  HealthAggregateWindowRequest copyWith({
    enums.HealthAggregateMetricEnum? metric,
    int? startMs,
    int? endMs,
    int? computedAtMs,
    List<HealthAggregateBucketRequest>? buckets,
  }) {
    return HealthAggregateWindowRequest(
      metric: metric ?? this.metric,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      computedAtMs: computedAtMs ?? this.computedAtMs,
      buckets: buckets ?? this.buckets,
    );
  }

  HealthAggregateWindowRequest copyWithWrapped({
    Wrapped<enums.HealthAggregateMetricEnum>? metric,
    Wrapped<int>? startMs,
    Wrapped<int>? endMs,
    Wrapped<int>? computedAtMs,
    Wrapped<List<HealthAggregateBucketRequest>>? buckets,
  }) {
    return HealthAggregateWindowRequest(
      metric: (metric != null ? metric.value : this.metric),
      startMs: (startMs != null ? startMs.value : this.startMs),
      endMs: (endMs != null ? endMs.value : this.endMs),
      computedAtMs: (computedAtMs != null
          ? computedAtMs.value
          : this.computedAtMs),
      buckets: (buckets != null ? buckets.value : this.buckets),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class HealthCheckResponse {
  const HealthCheckResponse({required this.status});

  factory HealthCheckResponse.fromJson(Map<String, dynamic> json) =>
      _$HealthCheckResponseFromJson(json);

  static const toJsonFactory = _$HealthCheckResponseToJson;
  Map<String, dynamic> toJson() => _$HealthCheckResponseToJson(this);

  @JsonKey(name: 'status')
  final String status;
  static const fromJsonFactory = _$HealthCheckResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HealthCheckResponse &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^ runtimeType.hashCode;
}

extension $HealthCheckResponseExtension on HealthCheckResponse {
  HealthCheckResponse copyWith({String? status}) {
    return HealthCheckResponse(status: status ?? this.status);
  }

  HealthCheckResponse copyWithWrapped({Wrapped<String>? status}) {
    return HealthCheckResponse(
      status: (status != null ? status.value : this.status),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class HealthDeletionRequest {
  const HealthDeletionRequest({required this.hcId, required this.observedAtMs});

  factory HealthDeletionRequest.fromJson(Map<String, dynamic> json) =>
      _$HealthDeletionRequestFromJson(json);

  static const toJsonFactory = _$HealthDeletionRequestToJson;
  Map<String, dynamic> toJson() => _$HealthDeletionRequestToJson(this);

  @JsonKey(name: 'hc_id')
  final String hcId;
  @JsonKey(name: 'observed_at_ms')
  final int observedAtMs;
  static const fromJsonFactory = _$HealthDeletionRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HealthDeletionRequest &&
            (identical(other.hcId, hcId) ||
                const DeepCollectionEquality().equals(other.hcId, hcId)) &&
            (identical(other.observedAtMs, observedAtMs) ||
                const DeepCollectionEquality().equals(
                  other.observedAtMs,
                  observedAtMs,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(hcId) ^
      const DeepCollectionEquality().hash(observedAtMs) ^
      runtimeType.hashCode;
}

extension $HealthDeletionRequestExtension on HealthDeletionRequest {
  HealthDeletionRequest copyWith({String? hcId, int? observedAtMs}) {
    return HealthDeletionRequest(
      hcId: hcId ?? this.hcId,
      observedAtMs: observedAtMs ?? this.observedAtMs,
    );
  }

  HealthDeletionRequest copyWithWrapped({
    Wrapped<String>? hcId,
    Wrapped<int>? observedAtMs,
  }) {
    return HealthDeletionRequest(
      hcId: (hcId != null ? hcId.value : this.hcId),
      observedAtMs: (observedAtMs != null
          ? observedAtMs.value
          : this.observedAtMs),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class HealthDeviceRequest {
  const HealthDeviceRequest({
    required this.type,
    this.manufacturer,
    this.model,
  });

  factory HealthDeviceRequest.fromJson(Map<String, dynamic> json) =>
      _$HealthDeviceRequestFromJson(json);

  static const toJsonFactory = _$HealthDeviceRequestToJson;
  Map<String, dynamic> toJson() => _$HealthDeviceRequestToJson(this);

  @JsonKey(
    name: 'type',
    toJson: healthDeviceTypeEnumToJson,
    fromJson: healthDeviceTypeEnumFromJson,
  )
  final enums.HealthDeviceTypeEnum type;
  @JsonKey(name: 'manufacturer')
  final String? manufacturer;
  @JsonKey(name: 'model')
  final String? model;
  static const fromJsonFactory = _$HealthDeviceRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HealthDeviceRequest &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)) &&
            (identical(other.manufacturer, manufacturer) ||
                const DeepCollectionEquality().equals(
                  other.manufacturer,
                  manufacturer,
                )) &&
            (identical(other.model, model) ||
                const DeepCollectionEquality().equals(other.model, model)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(type) ^
      const DeepCollectionEquality().hash(manufacturer) ^
      const DeepCollectionEquality().hash(model) ^
      runtimeType.hashCode;
}

extension $HealthDeviceRequestExtension on HealthDeviceRequest {
  HealthDeviceRequest copyWith({
    enums.HealthDeviceTypeEnum? type,
    String? manufacturer,
    String? model,
  }) {
    return HealthDeviceRequest(
      type: type ?? this.type,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
    );
  }

  HealthDeviceRequest copyWithWrapped({
    Wrapped<enums.HealthDeviceTypeEnum>? type,
    Wrapped<String?>? manufacturer,
    Wrapped<String?>? model,
  }) {
    return HealthDeviceRequest(
      type: (type != null ? type.value : this.type),
      manufacturer: (manufacturer != null
          ? manufacturer.value
          : this.manufacturer),
      model: (model != null ? model.value : this.model),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class HealthIngestRequest {
  const HealthIngestRequest({
    this.coverageStartMs,
    this.steps,
    this.restingHeartRate,
    this.sleepSession,
    this.deletions,
    this.aggregateWindows,
  });

  factory HealthIngestRequest.fromJson(Map<String, dynamic> json) =>
      _$HealthIngestRequestFromJson(json);

  static const toJsonFactory = _$HealthIngestRequestToJson;
  Map<String, dynamic> toJson() => _$HealthIngestRequestToJson(this);

  @JsonKey(name: 'coverage_start_ms')
  final int? coverageStartMs;
  @JsonKey(name: 'steps', defaultValue: <StepsRecordRequest>[])
  final List<StepsRecordRequest>? steps;
  @JsonKey(
    name: 'resting_heart_rate',
    defaultValue: <RestingHeartRateRecordRequest>[],
  )
  final List<RestingHeartRateRecordRequest>? restingHeartRate;
  @JsonKey(name: 'sleep_session', defaultValue: <SleepSessionRecordRequest>[])
  final List<SleepSessionRecordRequest>? sleepSession;
  @JsonKey(name: 'deletions', defaultValue: <HealthDeletionRequest>[])
  final List<HealthDeletionRequest>? deletions;
  @JsonKey(
    name: 'aggregate_windows',
    defaultValue: <HealthAggregateWindowRequest>[],
  )
  final List<HealthAggregateWindowRequest>? aggregateWindows;
  static const fromJsonFactory = _$HealthIngestRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HealthIngestRequest &&
            (identical(other.coverageStartMs, coverageStartMs) ||
                const DeepCollectionEquality().equals(
                  other.coverageStartMs,
                  coverageStartMs,
                )) &&
            (identical(other.steps, steps) ||
                const DeepCollectionEquality().equals(other.steps, steps)) &&
            (identical(other.restingHeartRate, restingHeartRate) ||
                const DeepCollectionEquality().equals(
                  other.restingHeartRate,
                  restingHeartRate,
                )) &&
            (identical(other.sleepSession, sleepSession) ||
                const DeepCollectionEquality().equals(
                  other.sleepSession,
                  sleepSession,
                )) &&
            (identical(other.deletions, deletions) ||
                const DeepCollectionEquality().equals(
                  other.deletions,
                  deletions,
                )) &&
            (identical(other.aggregateWindows, aggregateWindows) ||
                const DeepCollectionEquality().equals(
                  other.aggregateWindows,
                  aggregateWindows,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(coverageStartMs) ^
      const DeepCollectionEquality().hash(steps) ^
      const DeepCollectionEquality().hash(restingHeartRate) ^
      const DeepCollectionEquality().hash(sleepSession) ^
      const DeepCollectionEquality().hash(deletions) ^
      const DeepCollectionEquality().hash(aggregateWindows) ^
      runtimeType.hashCode;
}

extension $HealthIngestRequestExtension on HealthIngestRequest {
  HealthIngestRequest copyWith({
    int? coverageStartMs,
    List<StepsRecordRequest>? steps,
    List<RestingHeartRateRecordRequest>? restingHeartRate,
    List<SleepSessionRecordRequest>? sleepSession,
    List<HealthDeletionRequest>? deletions,
    List<HealthAggregateWindowRequest>? aggregateWindows,
  }) {
    return HealthIngestRequest(
      coverageStartMs: coverageStartMs ?? this.coverageStartMs,
      steps: steps ?? this.steps,
      restingHeartRate: restingHeartRate ?? this.restingHeartRate,
      sleepSession: sleepSession ?? this.sleepSession,
      deletions: deletions ?? this.deletions,
      aggregateWindows: aggregateWindows ?? this.aggregateWindows,
    );
  }

  HealthIngestRequest copyWithWrapped({
    Wrapped<int?>? coverageStartMs,
    Wrapped<List<StepsRecordRequest>?>? steps,
    Wrapped<List<RestingHeartRateRecordRequest>?>? restingHeartRate,
    Wrapped<List<SleepSessionRecordRequest>?>? sleepSession,
    Wrapped<List<HealthDeletionRequest>?>? deletions,
    Wrapped<List<HealthAggregateWindowRequest>?>? aggregateWindows,
  }) {
    return HealthIngestRequest(
      coverageStartMs: (coverageStartMs != null
          ? coverageStartMs.value
          : this.coverageStartMs),
      steps: (steps != null ? steps.value : this.steps),
      restingHeartRate: (restingHeartRate != null
          ? restingHeartRate.value
          : this.restingHeartRate),
      sleepSession: (sleepSession != null
          ? sleepSession.value
          : this.sleepSession),
      deletions: (deletions != null ? deletions.value : this.deletions),
      aggregateWindows: (aggregateWindows != null
          ? aggregateWindows.value
          : this.aggregateWindows),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class HealthIngestResponse {
  const HealthIngestResponse({
    required this.batchId,
    required this.recordsWritten,
    required this.recordsIgnored,
    required this.recordsDeleted,
    required this.aggregatesWritten,
    required this.aggregatesIgnored,
  });

  factory HealthIngestResponse.fromJson(Map<String, dynamic> json) =>
      _$HealthIngestResponseFromJson(json);

  static const toJsonFactory = _$HealthIngestResponseToJson;
  Map<String, dynamic> toJson() => _$HealthIngestResponseToJson(this);

  @JsonKey(name: 'batch_id')
  final int batchId;
  @JsonKey(name: 'records_written')
  final int recordsWritten;
  @JsonKey(name: 'records_ignored')
  final int recordsIgnored;
  @JsonKey(name: 'records_deleted')
  final int recordsDeleted;
  @JsonKey(name: 'aggregates_written')
  final int aggregatesWritten;
  @JsonKey(name: 'aggregates_ignored')
  final int aggregatesIgnored;
  static const fromJsonFactory = _$HealthIngestResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HealthIngestResponse &&
            (identical(other.batchId, batchId) ||
                const DeepCollectionEquality().equals(
                  other.batchId,
                  batchId,
                )) &&
            (identical(other.recordsWritten, recordsWritten) ||
                const DeepCollectionEquality().equals(
                  other.recordsWritten,
                  recordsWritten,
                )) &&
            (identical(other.recordsIgnored, recordsIgnored) ||
                const DeepCollectionEquality().equals(
                  other.recordsIgnored,
                  recordsIgnored,
                )) &&
            (identical(other.recordsDeleted, recordsDeleted) ||
                const DeepCollectionEquality().equals(
                  other.recordsDeleted,
                  recordsDeleted,
                )) &&
            (identical(other.aggregatesWritten, aggregatesWritten) ||
                const DeepCollectionEquality().equals(
                  other.aggregatesWritten,
                  aggregatesWritten,
                )) &&
            (identical(other.aggregatesIgnored, aggregatesIgnored) ||
                const DeepCollectionEquality().equals(
                  other.aggregatesIgnored,
                  aggregatesIgnored,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(batchId) ^
      const DeepCollectionEquality().hash(recordsWritten) ^
      const DeepCollectionEquality().hash(recordsIgnored) ^
      const DeepCollectionEquality().hash(recordsDeleted) ^
      const DeepCollectionEquality().hash(aggregatesWritten) ^
      const DeepCollectionEquality().hash(aggregatesIgnored) ^
      runtimeType.hashCode;
}

extension $HealthIngestResponseExtension on HealthIngestResponse {
  HealthIngestResponse copyWith({
    int? batchId,
    int? recordsWritten,
    int? recordsIgnored,
    int? recordsDeleted,
    int? aggregatesWritten,
    int? aggregatesIgnored,
  }) {
    return HealthIngestResponse(
      batchId: batchId ?? this.batchId,
      recordsWritten: recordsWritten ?? this.recordsWritten,
      recordsIgnored: recordsIgnored ?? this.recordsIgnored,
      recordsDeleted: recordsDeleted ?? this.recordsDeleted,
      aggregatesWritten: aggregatesWritten ?? this.aggregatesWritten,
      aggregatesIgnored: aggregatesIgnored ?? this.aggregatesIgnored,
    );
  }

  HealthIngestResponse copyWithWrapped({
    Wrapped<int>? batchId,
    Wrapped<int>? recordsWritten,
    Wrapped<int>? recordsIgnored,
    Wrapped<int>? recordsDeleted,
    Wrapped<int>? aggregatesWritten,
    Wrapped<int>? aggregatesIgnored,
  }) {
    return HealthIngestResponse(
      batchId: (batchId != null ? batchId.value : this.batchId),
      recordsWritten: (recordsWritten != null
          ? recordsWritten.value
          : this.recordsWritten),
      recordsIgnored: (recordsIgnored != null
          ? recordsIgnored.value
          : this.recordsIgnored),
      recordsDeleted: (recordsDeleted != null
          ? recordsDeleted.value
          : this.recordsDeleted),
      aggregatesWritten: (aggregatesWritten != null
          ? aggregatesWritten.value
          : this.aggregatesWritten),
      aggregatesIgnored: (aggregatesIgnored != null
          ? aggregatesIgnored.value
          : this.aggregatesIgnored),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Link {
  const Link({
    this.id,
    required this.name,
    required this.url,
    this.user,
    this.strategy,
    this.lastScraped,
    this.scrapeIntervalMinutes,
    this.nextScrapeAt,
    this.scrapeDisabled,
    this.scrapeFailureCount,
    this.lastScrapeError,
    this.comparisonInfo,
  });

  factory Link.fromJson(Map<String, dynamic> json) => _$LinkFromJson(json);

  static const toJsonFactory = _$LinkToJson;
  Map<String, dynamic> toJson() => _$LinkToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'name')
  final String name;
  @JsonKey(name: 'url')
  final String url;
  @JsonKey(name: 'user')
  final int? user;
  @JsonKey(name: 'strategy')
  final int? strategy;
  @JsonKey(name: 'last_scraped')
  final DateTime? lastScraped;
  @JsonKey(name: 'scrape_interval_minutes')
  final int? scrapeIntervalMinutes;
  @JsonKey(name: 'next_scrape_at')
  final DateTime? nextScrapeAt;
  @JsonKey(name: 'scrape_disabled')
  final bool? scrapeDisabled;
  @JsonKey(name: 'scrape_failure_count')
  final int? scrapeFailureCount;
  @JsonKey(name: 'last_scrape_error')
  final String? lastScrapeError;
  @JsonKey(name: 'comparison_info')
  final String? comparisonInfo;
  static const fromJsonFactory = _$LinkFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Link &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.user, user) ||
                const DeepCollectionEquality().equals(other.user, user)) &&
            (identical(other.strategy, strategy) ||
                const DeepCollectionEquality().equals(
                  other.strategy,
                  strategy,
                )) &&
            (identical(other.lastScraped, lastScraped) ||
                const DeepCollectionEquality().equals(
                  other.lastScraped,
                  lastScraped,
                )) &&
            (identical(other.scrapeIntervalMinutes, scrapeIntervalMinutes) ||
                const DeepCollectionEquality().equals(
                  other.scrapeIntervalMinutes,
                  scrapeIntervalMinutes,
                )) &&
            (identical(other.nextScrapeAt, nextScrapeAt) ||
                const DeepCollectionEquality().equals(
                  other.nextScrapeAt,
                  nextScrapeAt,
                )) &&
            (identical(other.scrapeDisabled, scrapeDisabled) ||
                const DeepCollectionEquality().equals(
                  other.scrapeDisabled,
                  scrapeDisabled,
                )) &&
            (identical(other.scrapeFailureCount, scrapeFailureCount) ||
                const DeepCollectionEquality().equals(
                  other.scrapeFailureCount,
                  scrapeFailureCount,
                )) &&
            (identical(other.lastScrapeError, lastScrapeError) ||
                const DeepCollectionEquality().equals(
                  other.lastScrapeError,
                  lastScrapeError,
                )) &&
            (identical(other.comparisonInfo, comparisonInfo) ||
                const DeepCollectionEquality().equals(
                  other.comparisonInfo,
                  comparisonInfo,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(user) ^
      const DeepCollectionEquality().hash(strategy) ^
      const DeepCollectionEquality().hash(lastScraped) ^
      const DeepCollectionEquality().hash(scrapeIntervalMinutes) ^
      const DeepCollectionEquality().hash(nextScrapeAt) ^
      const DeepCollectionEquality().hash(scrapeDisabled) ^
      const DeepCollectionEquality().hash(scrapeFailureCount) ^
      const DeepCollectionEquality().hash(lastScrapeError) ^
      const DeepCollectionEquality().hash(comparisonInfo) ^
      runtimeType.hashCode;
}

extension $LinkExtension on Link {
  Link copyWith({
    int? id,
    String? name,
    String? url,
    int? user,
    int? strategy,
    DateTime? lastScraped,
    int? scrapeIntervalMinutes,
    DateTime? nextScrapeAt,
    bool? scrapeDisabled,
    int? scrapeFailureCount,
    String? lastScrapeError,
    String? comparisonInfo,
  }) {
    return Link(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      user: user ?? this.user,
      strategy: strategy ?? this.strategy,
      lastScraped: lastScraped ?? this.lastScraped,
      scrapeIntervalMinutes:
          scrapeIntervalMinutes ?? this.scrapeIntervalMinutes,
      nextScrapeAt: nextScrapeAt ?? this.nextScrapeAt,
      scrapeDisabled: scrapeDisabled ?? this.scrapeDisabled,
      scrapeFailureCount: scrapeFailureCount ?? this.scrapeFailureCount,
      lastScrapeError: lastScrapeError ?? this.lastScrapeError,
      comparisonInfo: comparisonInfo ?? this.comparisonInfo,
    );
  }

  Link copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<String>? name,
    Wrapped<String>? url,
    Wrapped<int?>? user,
    Wrapped<int?>? strategy,
    Wrapped<DateTime?>? lastScraped,
    Wrapped<int?>? scrapeIntervalMinutes,
    Wrapped<DateTime?>? nextScrapeAt,
    Wrapped<bool?>? scrapeDisabled,
    Wrapped<int?>? scrapeFailureCount,
    Wrapped<String?>? lastScrapeError,
    Wrapped<String?>? comparisonInfo,
  }) {
    return Link(
      id: (id != null ? id.value : this.id),
      name: (name != null ? name.value : this.name),
      url: (url != null ? url.value : this.url),
      user: (user != null ? user.value : this.user),
      strategy: (strategy != null ? strategy.value : this.strategy),
      lastScraped: (lastScraped != null ? lastScraped.value : this.lastScraped),
      scrapeIntervalMinutes: (scrapeIntervalMinutes != null
          ? scrapeIntervalMinutes.value
          : this.scrapeIntervalMinutes),
      nextScrapeAt: (nextScrapeAt != null
          ? nextScrapeAt.value
          : this.nextScrapeAt),
      scrapeDisabled: (scrapeDisabled != null
          ? scrapeDisabled.value
          : this.scrapeDisabled),
      scrapeFailureCount: (scrapeFailureCount != null
          ? scrapeFailureCount.value
          : this.scrapeFailureCount),
      lastScrapeError: (lastScrapeError != null
          ? lastScrapeError.value
          : this.lastScrapeError),
      comparisonInfo: (comparisonInfo != null
          ? comparisonInfo.value
          : this.comparisonInfo),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class LinkRequest {
  const LinkRequest({
    required this.name,
    required this.url,
    this.strategy,
    this.scrapeIntervalMinutes,
    this.scrapeDisabled,
  });

  factory LinkRequest.fromJson(Map<String, dynamic> json) =>
      _$LinkRequestFromJson(json);

  static const toJsonFactory = _$LinkRequestToJson;
  Map<String, dynamic> toJson() => _$LinkRequestToJson(this);

  @JsonKey(name: 'name')
  final String name;
  @JsonKey(name: 'url')
  final String url;
  @JsonKey(name: 'strategy')
  final int? strategy;
  @JsonKey(name: 'scrape_interval_minutes')
  final int? scrapeIntervalMinutes;
  @JsonKey(name: 'scrape_disabled')
  final bool? scrapeDisabled;
  static const fromJsonFactory = _$LinkRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LinkRequest &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.strategy, strategy) ||
                const DeepCollectionEquality().equals(
                  other.strategy,
                  strategy,
                )) &&
            (identical(other.scrapeIntervalMinutes, scrapeIntervalMinutes) ||
                const DeepCollectionEquality().equals(
                  other.scrapeIntervalMinutes,
                  scrapeIntervalMinutes,
                )) &&
            (identical(other.scrapeDisabled, scrapeDisabled) ||
                const DeepCollectionEquality().equals(
                  other.scrapeDisabled,
                  scrapeDisabled,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(strategy) ^
      const DeepCollectionEquality().hash(scrapeIntervalMinutes) ^
      const DeepCollectionEquality().hash(scrapeDisabled) ^
      runtimeType.hashCode;
}

extension $LinkRequestExtension on LinkRequest {
  LinkRequest copyWith({
    String? name,
    String? url,
    int? strategy,
    int? scrapeIntervalMinutes,
    bool? scrapeDisabled,
  }) {
    return LinkRequest(
      name: name ?? this.name,
      url: url ?? this.url,
      strategy: strategy ?? this.strategy,
      scrapeIntervalMinutes:
          scrapeIntervalMinutes ?? this.scrapeIntervalMinutes,
      scrapeDisabled: scrapeDisabled ?? this.scrapeDisabled,
    );
  }

  LinkRequest copyWithWrapped({
    Wrapped<String>? name,
    Wrapped<String>? url,
    Wrapped<int?>? strategy,
    Wrapped<int?>? scrapeIntervalMinutes,
    Wrapped<bool?>? scrapeDisabled,
  }) {
    return LinkRequest(
      name: (name != null ? name.value : this.name),
      url: (url != null ? url.value : this.url),
      strategy: (strategy != null ? strategy.value : this.strategy),
      scrapeIntervalMinutes: (scrapeIntervalMinutes != null
          ? scrapeIntervalMinutes.value
          : this.scrapeIntervalMinutes),
      scrapeDisabled: (scrapeDisabled != null
          ? scrapeDisabled.value
          : this.scrapeDisabled),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class LoginRequest {
  const LoginRequest({
    required this.username,
    this.password,
    required this.transport,
    this.deviceLabel,
  });

  factory LoginRequest.fromJson(Map<String, dynamic> json) =>
      _$LoginRequestFromJson(json);

  static const toJsonFactory = _$LoginRequestToJson;
  Map<String, dynamic> toJson() => _$LoginRequestToJson(this);

  @JsonKey(name: 'username')
  final String username;
  @JsonKey(name: 'password')
  final String? password;
  @JsonKey(
    name: 'transport',
    toJson: transportEnumToJson,
    fromJson: transportEnumFromJson,
  )
  final enums.TransportEnum transport;
  @JsonKey(name: 'device_label')
  final String? deviceLabel;
  static const fromJsonFactory = _$LoginRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LoginRequest &&
            (identical(other.username, username) ||
                const DeepCollectionEquality().equals(
                  other.username,
                  username,
                )) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )) &&
            (identical(other.transport, transport) ||
                const DeepCollectionEquality().equals(
                  other.transport,
                  transport,
                )) &&
            (identical(other.deviceLabel, deviceLabel) ||
                const DeepCollectionEquality().equals(
                  other.deviceLabel,
                  deviceLabel,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(username) ^
      const DeepCollectionEquality().hash(password) ^
      const DeepCollectionEquality().hash(transport) ^
      const DeepCollectionEquality().hash(deviceLabel) ^
      runtimeType.hashCode;
}

extension $LoginRequestExtension on LoginRequest {
  LoginRequest copyWith({
    String? username,
    String? password,
    enums.TransportEnum? transport,
    String? deviceLabel,
  }) {
    return LoginRequest(
      username: username ?? this.username,
      password: password ?? this.password,
      transport: transport ?? this.transport,
      deviceLabel: deviceLabel ?? this.deviceLabel,
    );
  }

  LoginRequest copyWithWrapped({
    Wrapped<String>? username,
    Wrapped<String?>? password,
    Wrapped<enums.TransportEnum>? transport,
    Wrapped<String?>? deviceLabel,
  }) {
    return LoginRequest(
      username: (username != null ? username.value : this.username),
      password: (password != null ? password.value : this.password),
      transport: (transport != null ? transport.value : this.transport),
      deviceLabel: (deviceLabel != null ? deviceLabel.value : this.deviceLabel),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class LoginResponse {
  const LoginResponse({
    required this.transport,
    required this.publicId,
    this.token,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseFromJson(json);

  static const toJsonFactory = _$LoginResponseToJson;
  Map<String, dynamic> toJson() => _$LoginResponseToJson(this);

  @JsonKey(
    name: 'transport',
    toJson: transportEnumToJson,
    fromJson: transportEnumFromJson,
  )
  final enums.TransportEnum transport;
  @JsonKey(name: 'public_id')
  final String publicId;
  @JsonKey(name: 'token')
  final String? token;
  static const fromJsonFactory = _$LoginResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LoginResponse &&
            (identical(other.transport, transport) ||
                const DeepCollectionEquality().equals(
                  other.transport,
                  transport,
                )) &&
            (identical(other.publicId, publicId) ||
                const DeepCollectionEquality().equals(
                  other.publicId,
                  publicId,
                )) &&
            (identical(other.token, token) ||
                const DeepCollectionEquality().equals(other.token, token)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(transport) ^
      const DeepCollectionEquality().hash(publicId) ^
      const DeepCollectionEquality().hash(token) ^
      runtimeType.hashCode;
}

extension $LoginResponseExtension on LoginResponse {
  LoginResponse copyWith({
    enums.TransportEnum? transport,
    String? publicId,
    String? token,
  }) {
    return LoginResponse(
      transport: transport ?? this.transport,
      publicId: publicId ?? this.publicId,
      token: token ?? this.token,
    );
  }

  LoginResponse copyWithWrapped({
    Wrapped<enums.TransportEnum>? transport,
    Wrapped<String>? publicId,
    Wrapped<String?>? token,
  }) {
    return LoginResponse(
      transport: (transport != null ? transport.value : this.transport),
      publicId: (publicId != null ? publicId.value : this.publicId),
      token: (token != null ? token.value : this.token),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class MarkAllReadResponse {
  const MarkAllReadResponse({required this.markedRead});

  factory MarkAllReadResponse.fromJson(Map<String, dynamic> json) =>
      _$MarkAllReadResponseFromJson(json);

  static const toJsonFactory = _$MarkAllReadResponseToJson;
  Map<String, dynamic> toJson() => _$MarkAllReadResponseToJson(this);

  @JsonKey(name: 'marked_read')
  final int markedRead;
  static const fromJsonFactory = _$MarkAllReadResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MarkAllReadResponse &&
            (identical(other.markedRead, markedRead) ||
                const DeepCollectionEquality().equals(
                  other.markedRead,
                  markedRead,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(markedRead) ^ runtimeType.hashCode;
}

extension $MarkAllReadResponseExtension on MarkAllReadResponse {
  MarkAllReadResponse copyWith({int? markedRead}) {
    return MarkAllReadResponse(markedRead: markedRead ?? this.markedRead);
  }

  MarkAllReadResponse copyWithWrapped({Wrapped<int>? markedRead}) {
    return MarkAllReadResponse(
      markedRead: (markedRead != null ? markedRead.value : this.markedRead),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Notification {
  const Notification({this.id, this.update, this.status, this.readAt});

  factory Notification.fromJson(Map<String, dynamic> json) =>
      _$NotificationFromJson(json);

  static const toJsonFactory = _$NotificationToJson;
  Map<String, dynamic> toJson() => _$NotificationToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'update')
  final Update? update;
  @JsonKey(
    name: 'status',
    toJson: statusEnumNullableToJson,
    fromJson: statusEnumNullableFromJson,
  )
  final enums.StatusEnum? status;
  @JsonKey(name: 'read_at')
  final DateTime? readAt;
  static const fromJsonFactory = _$NotificationFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Notification &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.update, update) ||
                const DeepCollectionEquality().equals(other.update, update)) &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)) &&
            (identical(other.readAt, readAt) ||
                const DeepCollectionEquality().equals(other.readAt, readAt)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(update) ^
      const DeepCollectionEquality().hash(status) ^
      const DeepCollectionEquality().hash(readAt) ^
      runtimeType.hashCode;
}

extension $NotificationExtension on Notification {
  Notification copyWith({
    int? id,
    Update? update,
    enums.StatusEnum? status,
    DateTime? readAt,
  }) {
    return Notification(
      id: id ?? this.id,
      update: update ?? this.update,
      status: status ?? this.status,
      readAt: readAt ?? this.readAt,
    );
  }

  Notification copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<Update?>? update,
    Wrapped<enums.StatusEnum?>? status,
    Wrapped<DateTime?>? readAt,
  }) {
    return Notification(
      id: (id != null ? id.value : this.id),
      update: (update != null ? update.value : this.update),
      status: (status != null ? status.value : this.status),
      readAt: (readAt != null ? readAt.value : this.readAt),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class NotificationRequest {
  const NotificationRequest({this.status});

  factory NotificationRequest.fromJson(Map<String, dynamic> json) =>
      _$NotificationRequestFromJson(json);

  static const toJsonFactory = _$NotificationRequestToJson;
  Map<String, dynamic> toJson() => _$NotificationRequestToJson(this);

  @JsonKey(
    name: 'status',
    toJson: statusEnumNullableToJson,
    fromJson: statusEnumNullableFromJson,
  )
  final enums.StatusEnum? status;
  static const fromJsonFactory = _$NotificationRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NotificationRequest &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^ runtimeType.hashCode;
}

extension $NotificationRequestExtension on NotificationRequest {
  NotificationRequest copyWith({enums.StatusEnum? status}) {
    return NotificationRequest(status: status ?? this.status);
  }

  NotificationRequest copyWithWrapped({Wrapped<enums.StatusEnum?>? status}) {
    return NotificationRequest(
      status: (status != null ? status.value : this.status),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PaginatedLinkList {
  const PaginatedLinkList({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  factory PaginatedLinkList.fromJson(Map<String, dynamic> json) =>
      _$PaginatedLinkListFromJson(json);

  static const toJsonFactory = _$PaginatedLinkListToJson;
  Map<String, dynamic> toJson() => _$PaginatedLinkListToJson(this);

  @JsonKey(name: 'count')
  final int count;
  @JsonKey(name: 'next')
  final String? next;
  @JsonKey(name: 'previous')
  final String? previous;
  @JsonKey(name: 'results', defaultValue: <Link>[])
  final List<Link> results;
  static const fromJsonFactory = _$PaginatedLinkListFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PaginatedLinkList &&
            (identical(other.count, count) ||
                const DeepCollectionEquality().equals(other.count, count)) &&
            (identical(other.next, next) ||
                const DeepCollectionEquality().equals(other.next, next)) &&
            (identical(other.previous, previous) ||
                const DeepCollectionEquality().equals(
                  other.previous,
                  previous,
                )) &&
            (identical(other.results, results) ||
                const DeepCollectionEquality().equals(other.results, results)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(count) ^
      const DeepCollectionEquality().hash(next) ^
      const DeepCollectionEquality().hash(previous) ^
      const DeepCollectionEquality().hash(results) ^
      runtimeType.hashCode;
}

extension $PaginatedLinkListExtension on PaginatedLinkList {
  PaginatedLinkList copyWith({
    int? count,
    String? next,
    String? previous,
    List<Link>? results,
  }) {
    return PaginatedLinkList(
      count: count ?? this.count,
      next: next ?? this.next,
      previous: previous ?? this.previous,
      results: results ?? this.results,
    );
  }

  PaginatedLinkList copyWithWrapped({
    Wrapped<int>? count,
    Wrapped<String?>? next,
    Wrapped<String?>? previous,
    Wrapped<List<Link>>? results,
  }) {
    return PaginatedLinkList(
      count: (count != null ? count.value : this.count),
      next: (next != null ? next.value : this.next),
      previous: (previous != null ? previous.value : this.previous),
      results: (results != null ? results.value : this.results),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PaginatedNotificationList {
  const PaginatedNotificationList({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  factory PaginatedNotificationList.fromJson(Map<String, dynamic> json) =>
      _$PaginatedNotificationListFromJson(json);

  static const toJsonFactory = _$PaginatedNotificationListToJson;
  Map<String, dynamic> toJson() => _$PaginatedNotificationListToJson(this);

  @JsonKey(name: 'count')
  final int count;
  @JsonKey(name: 'next')
  final String? next;
  @JsonKey(name: 'previous')
  final String? previous;
  @JsonKey(name: 'results', defaultValue: <Notification>[])
  final List<Notification> results;
  static const fromJsonFactory = _$PaginatedNotificationListFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PaginatedNotificationList &&
            (identical(other.count, count) ||
                const DeepCollectionEquality().equals(other.count, count)) &&
            (identical(other.next, next) ||
                const DeepCollectionEquality().equals(other.next, next)) &&
            (identical(other.previous, previous) ||
                const DeepCollectionEquality().equals(
                  other.previous,
                  previous,
                )) &&
            (identical(other.results, results) ||
                const DeepCollectionEquality().equals(other.results, results)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(count) ^
      const DeepCollectionEquality().hash(next) ^
      const DeepCollectionEquality().hash(previous) ^
      const DeepCollectionEquality().hash(results) ^
      runtimeType.hashCode;
}

extension $PaginatedNotificationListExtension on PaginatedNotificationList {
  PaginatedNotificationList copyWith({
    int? count,
    String? next,
    String? previous,
    List<Notification>? results,
  }) {
    return PaginatedNotificationList(
      count: count ?? this.count,
      next: next ?? this.next,
      previous: previous ?? this.previous,
      results: results ?? this.results,
    );
  }

  PaginatedNotificationList copyWithWrapped({
    Wrapped<int>? count,
    Wrapped<String?>? next,
    Wrapped<String?>? previous,
    Wrapped<List<Notification>>? results,
  }) {
    return PaginatedNotificationList(
      count: (count != null ? count.value : this.count),
      next: (next != null ? next.value : this.next),
      previous: (previous != null ? previous.value : this.previous),
      results: (results != null ? results.value : this.results),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PaginatedSystemEventList {
  const PaginatedSystemEventList({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  factory PaginatedSystemEventList.fromJson(Map<String, dynamic> json) =>
      _$PaginatedSystemEventListFromJson(json);

  static const toJsonFactory = _$PaginatedSystemEventListToJson;
  Map<String, dynamic> toJson() => _$PaginatedSystemEventListToJson(this);

  @JsonKey(name: 'count')
  final int count;
  @JsonKey(name: 'next')
  final String? next;
  @JsonKey(name: 'previous')
  final String? previous;
  @JsonKey(name: 'results', defaultValue: <SystemEvent>[])
  final List<SystemEvent> results;
  static const fromJsonFactory = _$PaginatedSystemEventListFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PaginatedSystemEventList &&
            (identical(other.count, count) ||
                const DeepCollectionEquality().equals(other.count, count)) &&
            (identical(other.next, next) ||
                const DeepCollectionEquality().equals(other.next, next)) &&
            (identical(other.previous, previous) ||
                const DeepCollectionEquality().equals(
                  other.previous,
                  previous,
                )) &&
            (identical(other.results, results) ||
                const DeepCollectionEquality().equals(other.results, results)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(count) ^
      const DeepCollectionEquality().hash(next) ^
      const DeepCollectionEquality().hash(previous) ^
      const DeepCollectionEquality().hash(results) ^
      runtimeType.hashCode;
}

extension $PaginatedSystemEventListExtension on PaginatedSystemEventList {
  PaginatedSystemEventList copyWith({
    int? count,
    String? next,
    String? previous,
    List<SystemEvent>? results,
  }) {
    return PaginatedSystemEventList(
      count: count ?? this.count,
      next: next ?? this.next,
      previous: previous ?? this.previous,
      results: results ?? this.results,
    );
  }

  PaginatedSystemEventList copyWithWrapped({
    Wrapped<int>? count,
    Wrapped<String?>? next,
    Wrapped<String?>? previous,
    Wrapped<List<SystemEvent>>? results,
  }) {
    return PaginatedSystemEventList(
      count: (count != null ? count.value : this.count),
      next: (next != null ? next.value : this.next),
      previous: (previous != null ? previous.value : this.previous),
      results: (results != null ? results.value : this.results),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PasswordResetConfirmRequest {
  const PasswordResetConfirmRequest({
    required this.email,
    required this.code,
    required this.newPassword,
  });

  factory PasswordResetConfirmRequest.fromJson(Map<String, dynamic> json) =>
      _$PasswordResetConfirmRequestFromJson(json);

  static const toJsonFactory = _$PasswordResetConfirmRequestToJson;
  Map<String, dynamic> toJson() => _$PasswordResetConfirmRequestToJson(this);

  @JsonKey(name: 'email')
  final String email;
  @JsonKey(name: 'code')
  final String code;
  @JsonKey(name: 'new_password')
  final String newPassword;
  static const fromJsonFactory = _$PasswordResetConfirmRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PasswordResetConfirmRequest &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.code, code) ||
                const DeepCollectionEquality().equals(other.code, code)) &&
            (identical(other.newPassword, newPassword) ||
                const DeepCollectionEquality().equals(
                  other.newPassword,
                  newPassword,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(code) ^
      const DeepCollectionEquality().hash(newPassword) ^
      runtimeType.hashCode;
}

extension $PasswordResetConfirmRequestExtension on PasswordResetConfirmRequest {
  PasswordResetConfirmRequest copyWith({
    String? email,
    String? code,
    String? newPassword,
  }) {
    return PasswordResetConfirmRequest(
      email: email ?? this.email,
      code: code ?? this.code,
      newPassword: newPassword ?? this.newPassword,
    );
  }

  PasswordResetConfirmRequest copyWithWrapped({
    Wrapped<String>? email,
    Wrapped<String>? code,
    Wrapped<String>? newPassword,
  }) {
    return PasswordResetConfirmRequest(
      email: (email != null ? email.value : this.email),
      code: (code != null ? code.value : this.code),
      newPassword: (newPassword != null ? newPassword.value : this.newPassword),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PasswordResetRequest {
  const PasswordResetRequest({required this.email});

  factory PasswordResetRequest.fromJson(Map<String, dynamic> json) =>
      _$PasswordResetRequestFromJson(json);

  static const toJsonFactory = _$PasswordResetRequestToJson;
  Map<String, dynamic> toJson() => _$PasswordResetRequestToJson(this);

  @JsonKey(name: 'email')
  final String email;
  static const fromJsonFactory = _$PasswordResetRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PasswordResetRequest &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(email) ^ runtimeType.hashCode;
}

extension $PasswordResetRequestExtension on PasswordResetRequest {
  PasswordResetRequest copyWith({String? email}) {
    return PasswordResetRequest(email: email ?? this.email);
  }

  PasswordResetRequest copyWithWrapped({Wrapped<String>? email}) {
    return PasswordResetRequest(
      email: (email != null ? email.value : this.email),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PatchedLinkRequest {
  const PatchedLinkRequest({
    this.name,
    this.url,
    this.strategy,
    this.scrapeIntervalMinutes,
    this.scrapeDisabled,
  });

  factory PatchedLinkRequest.fromJson(Map<String, dynamic> json) =>
      _$PatchedLinkRequestFromJson(json);

  static const toJsonFactory = _$PatchedLinkRequestToJson;
  Map<String, dynamic> toJson() => _$PatchedLinkRequestToJson(this);

  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'url')
  final String? url;
  @JsonKey(name: 'strategy')
  final int? strategy;
  @JsonKey(name: 'scrape_interval_minutes')
  final int? scrapeIntervalMinutes;
  @JsonKey(name: 'scrape_disabled')
  final bool? scrapeDisabled;
  static const fromJsonFactory = _$PatchedLinkRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PatchedLinkRequest &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.url, url) ||
                const DeepCollectionEquality().equals(other.url, url)) &&
            (identical(other.strategy, strategy) ||
                const DeepCollectionEquality().equals(
                  other.strategy,
                  strategy,
                )) &&
            (identical(other.scrapeIntervalMinutes, scrapeIntervalMinutes) ||
                const DeepCollectionEquality().equals(
                  other.scrapeIntervalMinutes,
                  scrapeIntervalMinutes,
                )) &&
            (identical(other.scrapeDisabled, scrapeDisabled) ||
                const DeepCollectionEquality().equals(
                  other.scrapeDisabled,
                  scrapeDisabled,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(url) ^
      const DeepCollectionEquality().hash(strategy) ^
      const DeepCollectionEquality().hash(scrapeIntervalMinutes) ^
      const DeepCollectionEquality().hash(scrapeDisabled) ^
      runtimeType.hashCode;
}

extension $PatchedLinkRequestExtension on PatchedLinkRequest {
  PatchedLinkRequest copyWith({
    String? name,
    String? url,
    int? strategy,
    int? scrapeIntervalMinutes,
    bool? scrapeDisabled,
  }) {
    return PatchedLinkRequest(
      name: name ?? this.name,
      url: url ?? this.url,
      strategy: strategy ?? this.strategy,
      scrapeIntervalMinutes:
          scrapeIntervalMinutes ?? this.scrapeIntervalMinutes,
      scrapeDisabled: scrapeDisabled ?? this.scrapeDisabled,
    );
  }

  PatchedLinkRequest copyWithWrapped({
    Wrapped<String?>? name,
    Wrapped<String?>? url,
    Wrapped<int?>? strategy,
    Wrapped<int?>? scrapeIntervalMinutes,
    Wrapped<bool?>? scrapeDisabled,
  }) {
    return PatchedLinkRequest(
      name: (name != null ? name.value : this.name),
      url: (url != null ? url.value : this.url),
      strategy: (strategy != null ? strategy.value : this.strategy),
      scrapeIntervalMinutes: (scrapeIntervalMinutes != null
          ? scrapeIntervalMinutes.value
          : this.scrapeIntervalMinutes),
      scrapeDisabled: (scrapeDisabled != null
          ? scrapeDisabled.value
          : this.scrapeDisabled),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PatchedNotificationRequest {
  const PatchedNotificationRequest({this.status});

  factory PatchedNotificationRequest.fromJson(Map<String, dynamic> json) =>
      _$PatchedNotificationRequestFromJson(json);

  static const toJsonFactory = _$PatchedNotificationRequestToJson;
  Map<String, dynamic> toJson() => _$PatchedNotificationRequestToJson(this);

  @JsonKey(
    name: 'status',
    toJson: statusEnumNullableToJson,
    fromJson: statusEnumNullableFromJson,
  )
  final enums.StatusEnum? status;
  static const fromJsonFactory = _$PatchedNotificationRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PatchedNotificationRequest &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^ runtimeType.hashCode;
}

extension $PatchedNotificationRequestExtension on PatchedNotificationRequest {
  PatchedNotificationRequest copyWith({enums.StatusEnum? status}) {
    return PatchedNotificationRequest(status: status ?? this.status);
  }

  PatchedNotificationRequest copyWithWrapped({
    Wrapped<enums.StatusEnum?>? status,
  }) {
    return PatchedNotificationRequest(
      status: (status != null ? status.value : this.status),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PatchedStrategyRequest {
  const PatchedStrategyRequest({this.stratCls, this.data});

  factory PatchedStrategyRequest.fromJson(Map<String, dynamic> json) =>
      _$PatchedStrategyRequestFromJson(json);

  static const toJsonFactory = _$PatchedStrategyRequestToJson;
  Map<String, dynamic> toJson() => _$PatchedStrategyRequestToJson(this);

  @JsonKey(
    name: 'strat_cls',
    toJson: stratClsEnumNullableToJson,
    fromJson: stratClsEnumNullableFromJson,
  )
  final enums.StratClsEnum? stratCls;
  @JsonKey(name: 'data')
  final dynamic data;
  static const fromJsonFactory = _$PatchedStrategyRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PatchedStrategyRequest &&
            (identical(other.stratCls, stratCls) ||
                const DeepCollectionEquality().equals(
                  other.stratCls,
                  stratCls,
                )) &&
            (identical(other.data, data) ||
                const DeepCollectionEquality().equals(other.data, data)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(stratCls) ^
      const DeepCollectionEquality().hash(data) ^
      runtimeType.hashCode;
}

extension $PatchedStrategyRequestExtension on PatchedStrategyRequest {
  PatchedStrategyRequest copyWith({
    enums.StratClsEnum? stratCls,
    dynamic data,
  }) {
    return PatchedStrategyRequest(
      stratCls: stratCls ?? this.stratCls,
      data: data ?? this.data,
    );
  }

  PatchedStrategyRequest copyWithWrapped({
    Wrapped<enums.StratClsEnum?>? stratCls,
    Wrapped<dynamic>? data,
  }) {
    return PatchedStrategyRequest(
      stratCls: (stratCls != null ? stratCls.value : this.stratCls),
      data: (data != null ? data.value : this.data),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PatchedUserCreationRequest {
  const PatchedUserCreationRequest({
    this.username,
    this.email,
    this.name,
    this.password,
  });

  factory PatchedUserCreationRequest.fromJson(Map<String, dynamic> json) =>
      _$PatchedUserCreationRequestFromJson(json);

  static const toJsonFactory = _$PatchedUserCreationRequestToJson;
  Map<String, dynamic> toJson() => _$PatchedUserCreationRequestToJson(this);

  @JsonKey(name: 'username')
  final String? username;
  @JsonKey(name: 'email')
  final String? email;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'password')
  final String? password;
  static const fromJsonFactory = _$PatchedUserCreationRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PatchedUserCreationRequest &&
            (identical(other.username, username) ||
                const DeepCollectionEquality().equals(
                  other.username,
                  username,
                )) &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(username) ^
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(password) ^
      runtimeType.hashCode;
}

extension $PatchedUserCreationRequestExtension on PatchedUserCreationRequest {
  PatchedUserCreationRequest copyWith({
    String? username,
    String? email,
    String? name,
    String? password,
  }) {
    return PatchedUserCreationRequest(
      username: username ?? this.username,
      email: email ?? this.email,
      name: name ?? this.name,
      password: password ?? this.password,
    );
  }

  PatchedUserCreationRequest copyWithWrapped({
    Wrapped<String?>? username,
    Wrapped<String?>? email,
    Wrapped<String?>? name,
    Wrapped<String?>? password,
  }) {
    return PatchedUserCreationRequest(
      username: (username != null ? username.value : this.username),
      email: (email != null ? email.value : this.email),
      name: (name != null ? name.value : this.name),
      password: (password != null ? password.value : this.password),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class RestingHeartRateRecordRequest {
  const RestingHeartRateRecordRequest({
    required this.hcId,
    required this.dataOrigin,
    required this.lastModifiedMs,
    required this.recordingMethod,
    this.device,
    required this.timeMs,
    this.offsetS,
    required this.beatsPerMinute,
  });

  factory RestingHeartRateRecordRequest.fromJson(Map<String, dynamic> json) =>
      _$RestingHeartRateRecordRequestFromJson(json);

  static const toJsonFactory = _$RestingHeartRateRecordRequestToJson;
  Map<String, dynamic> toJson() => _$RestingHeartRateRecordRequestToJson(this);

  @JsonKey(name: 'hc_id')
  final String hcId;
  @JsonKey(name: 'data_origin')
  final String dataOrigin;
  @JsonKey(name: 'last_modified_ms')
  final int lastModifiedMs;
  @JsonKey(
    name: 'recording_method',
    toJson: recordingMethodEnumToJson,
    fromJson: recordingMethodEnumFromJson,
  )
  final enums.RecordingMethodEnum recordingMethod;
  @JsonKey(name: 'device')
  final HealthDeviceRequest? device;
  @JsonKey(name: 'time_ms')
  final int timeMs;
  @JsonKey(name: 'offset_s')
  final int? offsetS;
  @JsonKey(name: 'beats_per_minute')
  final int beatsPerMinute;
  static const fromJsonFactory = _$RestingHeartRateRecordRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is RestingHeartRateRecordRequest &&
            (identical(other.hcId, hcId) ||
                const DeepCollectionEquality().equals(other.hcId, hcId)) &&
            (identical(other.dataOrigin, dataOrigin) ||
                const DeepCollectionEquality().equals(
                  other.dataOrigin,
                  dataOrigin,
                )) &&
            (identical(other.lastModifiedMs, lastModifiedMs) ||
                const DeepCollectionEquality().equals(
                  other.lastModifiedMs,
                  lastModifiedMs,
                )) &&
            (identical(other.recordingMethod, recordingMethod) ||
                const DeepCollectionEquality().equals(
                  other.recordingMethod,
                  recordingMethod,
                )) &&
            (identical(other.device, device) ||
                const DeepCollectionEquality().equals(other.device, device)) &&
            (identical(other.timeMs, timeMs) ||
                const DeepCollectionEquality().equals(other.timeMs, timeMs)) &&
            (identical(other.offsetS, offsetS) ||
                const DeepCollectionEquality().equals(
                  other.offsetS,
                  offsetS,
                )) &&
            (identical(other.beatsPerMinute, beatsPerMinute) ||
                const DeepCollectionEquality().equals(
                  other.beatsPerMinute,
                  beatsPerMinute,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(hcId) ^
      const DeepCollectionEquality().hash(dataOrigin) ^
      const DeepCollectionEquality().hash(lastModifiedMs) ^
      const DeepCollectionEquality().hash(recordingMethod) ^
      const DeepCollectionEquality().hash(device) ^
      const DeepCollectionEquality().hash(timeMs) ^
      const DeepCollectionEquality().hash(offsetS) ^
      const DeepCollectionEquality().hash(beatsPerMinute) ^
      runtimeType.hashCode;
}

extension $RestingHeartRateRecordRequestExtension
    on RestingHeartRateRecordRequest {
  RestingHeartRateRecordRequest copyWith({
    String? hcId,
    String? dataOrigin,
    int? lastModifiedMs,
    enums.RecordingMethodEnum? recordingMethod,
    HealthDeviceRequest? device,
    int? timeMs,
    int? offsetS,
    int? beatsPerMinute,
  }) {
    return RestingHeartRateRecordRequest(
      hcId: hcId ?? this.hcId,
      dataOrigin: dataOrigin ?? this.dataOrigin,
      lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
      recordingMethod: recordingMethod ?? this.recordingMethod,
      device: device ?? this.device,
      timeMs: timeMs ?? this.timeMs,
      offsetS: offsetS ?? this.offsetS,
      beatsPerMinute: beatsPerMinute ?? this.beatsPerMinute,
    );
  }

  RestingHeartRateRecordRequest copyWithWrapped({
    Wrapped<String>? hcId,
    Wrapped<String>? dataOrigin,
    Wrapped<int>? lastModifiedMs,
    Wrapped<enums.RecordingMethodEnum>? recordingMethod,
    Wrapped<HealthDeviceRequest?>? device,
    Wrapped<int>? timeMs,
    Wrapped<int?>? offsetS,
    Wrapped<int>? beatsPerMinute,
  }) {
    return RestingHeartRateRecordRequest(
      hcId: (hcId != null ? hcId.value : this.hcId),
      dataOrigin: (dataOrigin != null ? dataOrigin.value : this.dataOrigin),
      lastModifiedMs: (lastModifiedMs != null
          ? lastModifiedMs.value
          : this.lastModifiedMs),
      recordingMethod: (recordingMethod != null
          ? recordingMethod.value
          : this.recordingMethod),
      device: (device != null ? device.value : this.device),
      timeMs: (timeMs != null ? timeMs.value : this.timeMs),
      offsetS: (offsetS != null ? offsetS.value : this.offsetS),
      beatsPerMinute: (beatsPerMinute != null
          ? beatsPerMinute.value
          : this.beatsPerMinute),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class SessionRevokeResponse {
  const SessionRevokeResponse({required this.status, required this.revoked});

  factory SessionRevokeResponse.fromJson(Map<String, dynamic> json) =>
      _$SessionRevokeResponseFromJson(json);

  static const toJsonFactory = _$SessionRevokeResponseToJson;
  Map<String, dynamic> toJson() => _$SessionRevokeResponseToJson(this);

  @JsonKey(name: 'status')
  final String status;
  @JsonKey(name: 'revoked')
  final int revoked;
  static const fromJsonFactory = _$SessionRevokeResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SessionRevokeResponse &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)) &&
            (identical(other.revoked, revoked) ||
                const DeepCollectionEquality().equals(other.revoked, revoked)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^
      const DeepCollectionEquality().hash(revoked) ^
      runtimeType.hashCode;
}

extension $SessionRevokeResponseExtension on SessionRevokeResponse {
  SessionRevokeResponse copyWith({String? status, int? revoked}) {
    return SessionRevokeResponse(
      status: status ?? this.status,
      revoked: revoked ?? this.revoked,
    );
  }

  SessionRevokeResponse copyWithWrapped({
    Wrapped<String>? status,
    Wrapped<int>? revoked,
  }) {
    return SessionRevokeResponse(
      status: (status != null ? status.value : this.status),
      revoked: (revoked != null ? revoked.value : this.revoked),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class SleepSessionRecordRequest {
  const SleepSessionRecordRequest({
    required this.hcId,
    required this.dataOrigin,
    required this.lastModifiedMs,
    required this.recordingMethod,
    this.device,
    required this.startMs,
    this.startOffsetS,
    required this.endMs,
    this.endOffsetS,
    this.title,
    this.notes,
    required this.stages,
  });

  factory SleepSessionRecordRequest.fromJson(Map<String, dynamic> json) =>
      _$SleepSessionRecordRequestFromJson(json);

  static const toJsonFactory = _$SleepSessionRecordRequestToJson;
  Map<String, dynamic> toJson() => _$SleepSessionRecordRequestToJson(this);

  @JsonKey(name: 'hc_id')
  final String hcId;
  @JsonKey(name: 'data_origin')
  final String dataOrigin;
  @JsonKey(name: 'last_modified_ms')
  final int lastModifiedMs;
  @JsonKey(
    name: 'recording_method',
    toJson: recordingMethodEnumToJson,
    fromJson: recordingMethodEnumFromJson,
  )
  final enums.RecordingMethodEnum recordingMethod;
  @JsonKey(name: 'device')
  final HealthDeviceRequest? device;
  @JsonKey(name: 'start_ms')
  final int startMs;
  @JsonKey(name: 'start_offset_s')
  final int? startOffsetS;
  @JsonKey(name: 'end_ms')
  final int endMs;
  @JsonKey(name: 'end_offset_s')
  final int? endOffsetS;
  @JsonKey(name: 'title')
  final String? title;
  @JsonKey(name: 'notes')
  final String? notes;
  @JsonKey(name: 'stages', defaultValue: <SleepStageRequest>[])
  final List<SleepStageRequest> stages;
  static const fromJsonFactory = _$SleepSessionRecordRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SleepSessionRecordRequest &&
            (identical(other.hcId, hcId) ||
                const DeepCollectionEquality().equals(other.hcId, hcId)) &&
            (identical(other.dataOrigin, dataOrigin) ||
                const DeepCollectionEquality().equals(
                  other.dataOrigin,
                  dataOrigin,
                )) &&
            (identical(other.lastModifiedMs, lastModifiedMs) ||
                const DeepCollectionEquality().equals(
                  other.lastModifiedMs,
                  lastModifiedMs,
                )) &&
            (identical(other.recordingMethod, recordingMethod) ||
                const DeepCollectionEquality().equals(
                  other.recordingMethod,
                  recordingMethod,
                )) &&
            (identical(other.device, device) ||
                const DeepCollectionEquality().equals(other.device, device)) &&
            (identical(other.startMs, startMs) ||
                const DeepCollectionEquality().equals(
                  other.startMs,
                  startMs,
                )) &&
            (identical(other.startOffsetS, startOffsetS) ||
                const DeepCollectionEquality().equals(
                  other.startOffsetS,
                  startOffsetS,
                )) &&
            (identical(other.endMs, endMs) ||
                const DeepCollectionEquality().equals(other.endMs, endMs)) &&
            (identical(other.endOffsetS, endOffsetS) ||
                const DeepCollectionEquality().equals(
                  other.endOffsetS,
                  endOffsetS,
                )) &&
            (identical(other.title, title) ||
                const DeepCollectionEquality().equals(other.title, title)) &&
            (identical(other.notes, notes) ||
                const DeepCollectionEquality().equals(other.notes, notes)) &&
            (identical(other.stages, stages) ||
                const DeepCollectionEquality().equals(other.stages, stages)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(hcId) ^
      const DeepCollectionEquality().hash(dataOrigin) ^
      const DeepCollectionEquality().hash(lastModifiedMs) ^
      const DeepCollectionEquality().hash(recordingMethod) ^
      const DeepCollectionEquality().hash(device) ^
      const DeepCollectionEquality().hash(startMs) ^
      const DeepCollectionEquality().hash(startOffsetS) ^
      const DeepCollectionEquality().hash(endMs) ^
      const DeepCollectionEquality().hash(endOffsetS) ^
      const DeepCollectionEquality().hash(title) ^
      const DeepCollectionEquality().hash(notes) ^
      const DeepCollectionEquality().hash(stages) ^
      runtimeType.hashCode;
}

extension $SleepSessionRecordRequestExtension on SleepSessionRecordRequest {
  SleepSessionRecordRequest copyWith({
    String? hcId,
    String? dataOrigin,
    int? lastModifiedMs,
    enums.RecordingMethodEnum? recordingMethod,
    HealthDeviceRequest? device,
    int? startMs,
    int? startOffsetS,
    int? endMs,
    int? endOffsetS,
    String? title,
    String? notes,
    List<SleepStageRequest>? stages,
  }) {
    return SleepSessionRecordRequest(
      hcId: hcId ?? this.hcId,
      dataOrigin: dataOrigin ?? this.dataOrigin,
      lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
      recordingMethod: recordingMethod ?? this.recordingMethod,
      device: device ?? this.device,
      startMs: startMs ?? this.startMs,
      startOffsetS: startOffsetS ?? this.startOffsetS,
      endMs: endMs ?? this.endMs,
      endOffsetS: endOffsetS ?? this.endOffsetS,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      stages: stages ?? this.stages,
    );
  }

  SleepSessionRecordRequest copyWithWrapped({
    Wrapped<String>? hcId,
    Wrapped<String>? dataOrigin,
    Wrapped<int>? lastModifiedMs,
    Wrapped<enums.RecordingMethodEnum>? recordingMethod,
    Wrapped<HealthDeviceRequest?>? device,
    Wrapped<int>? startMs,
    Wrapped<int?>? startOffsetS,
    Wrapped<int>? endMs,
    Wrapped<int?>? endOffsetS,
    Wrapped<String?>? title,
    Wrapped<String?>? notes,
    Wrapped<List<SleepStageRequest>>? stages,
  }) {
    return SleepSessionRecordRequest(
      hcId: (hcId != null ? hcId.value : this.hcId),
      dataOrigin: (dataOrigin != null ? dataOrigin.value : this.dataOrigin),
      lastModifiedMs: (lastModifiedMs != null
          ? lastModifiedMs.value
          : this.lastModifiedMs),
      recordingMethod: (recordingMethod != null
          ? recordingMethod.value
          : this.recordingMethod),
      device: (device != null ? device.value : this.device),
      startMs: (startMs != null ? startMs.value : this.startMs),
      startOffsetS: (startOffsetS != null
          ? startOffsetS.value
          : this.startOffsetS),
      endMs: (endMs != null ? endMs.value : this.endMs),
      endOffsetS: (endOffsetS != null ? endOffsetS.value : this.endOffsetS),
      title: (title != null ? title.value : this.title),
      notes: (notes != null ? notes.value : this.notes),
      stages: (stages != null ? stages.value : this.stages),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class SleepStageRequest {
  const SleepStageRequest({
    required this.startMs,
    required this.endMs,
    required this.stage,
  });

  factory SleepStageRequest.fromJson(Map<String, dynamic> json) =>
      _$SleepStageRequestFromJson(json);

  static const toJsonFactory = _$SleepStageRequestToJson;
  Map<String, dynamic> toJson() => _$SleepStageRequestToJson(this);

  @JsonKey(name: 'start_ms')
  final int startMs;
  @JsonKey(name: 'end_ms')
  final int endMs;
  @JsonKey(
    name: 'stage',
    toJson: sleepStageEnumToJson,
    fromJson: sleepStageEnumFromJson,
  )
  final enums.SleepStageEnum stage;
  static const fromJsonFactory = _$SleepStageRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SleepStageRequest &&
            (identical(other.startMs, startMs) ||
                const DeepCollectionEquality().equals(
                  other.startMs,
                  startMs,
                )) &&
            (identical(other.endMs, endMs) ||
                const DeepCollectionEquality().equals(other.endMs, endMs)) &&
            (identical(other.stage, stage) ||
                const DeepCollectionEquality().equals(other.stage, stage)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(startMs) ^
      const DeepCollectionEquality().hash(endMs) ^
      const DeepCollectionEquality().hash(stage) ^
      runtimeType.hashCode;
}

extension $SleepStageRequestExtension on SleepStageRequest {
  SleepStageRequest copyWith({
    int? startMs,
    int? endMs,
    enums.SleepStageEnum? stage,
  }) {
    return SleepStageRequest(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      stage: stage ?? this.stage,
    );
  }

  SleepStageRequest copyWithWrapped({
    Wrapped<int>? startMs,
    Wrapped<int>? endMs,
    Wrapped<enums.SleepStageEnum>? stage,
  }) {
    return SleepStageRequest(
      startMs: (startMs != null ? startMs.value : this.startMs),
      endMs: (endMs != null ? endMs.value : this.endMs),
      stage: (stage != null ? stage.value : this.stage),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class StatusCheckResponse {
  const StatusCheckResponse({
    required this.status,
    required this.db,
    required this.version,
    required this.commit,
    required this.environment,
  });

  factory StatusCheckResponse.fromJson(Map<String, dynamic> json) =>
      _$StatusCheckResponseFromJson(json);

  static const toJsonFactory = _$StatusCheckResponseToJson;
  Map<String, dynamic> toJson() => _$StatusCheckResponseToJson(this);

  @JsonKey(name: 'status')
  final String status;
  @JsonKey(name: 'db')
  final String db;
  @JsonKey(name: 'version')
  final String version;
  @JsonKey(name: 'commit')
  final String commit;
  @JsonKey(name: 'environment')
  final String environment;
  static const fromJsonFactory = _$StatusCheckResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StatusCheckResponse &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)) &&
            (identical(other.db, db) ||
                const DeepCollectionEquality().equals(other.db, db)) &&
            (identical(other.version, version) ||
                const DeepCollectionEquality().equals(
                  other.version,
                  version,
                )) &&
            (identical(other.commit, commit) ||
                const DeepCollectionEquality().equals(other.commit, commit)) &&
            (identical(other.environment, environment) ||
                const DeepCollectionEquality().equals(
                  other.environment,
                  environment,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^
      const DeepCollectionEquality().hash(db) ^
      const DeepCollectionEquality().hash(version) ^
      const DeepCollectionEquality().hash(commit) ^
      const DeepCollectionEquality().hash(environment) ^
      runtimeType.hashCode;
}

extension $StatusCheckResponseExtension on StatusCheckResponse {
  StatusCheckResponse copyWith({
    String? status,
    String? db,
    String? version,
    String? commit,
    String? environment,
  }) {
    return StatusCheckResponse(
      status: status ?? this.status,
      db: db ?? this.db,
      version: version ?? this.version,
      commit: commit ?? this.commit,
      environment: environment ?? this.environment,
    );
  }

  StatusCheckResponse copyWithWrapped({
    Wrapped<String>? status,
    Wrapped<String>? db,
    Wrapped<String>? version,
    Wrapped<String>? commit,
    Wrapped<String>? environment,
  }) {
    return StatusCheckResponse(
      status: (status != null ? status.value : this.status),
      db: (db != null ? db.value : this.db),
      version: (version != null ? version.value : this.version),
      commit: (commit != null ? commit.value : this.commit),
      environment: (environment != null ? environment.value : this.environment),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class StatusResponse {
  const StatusResponse({required this.status});

  factory StatusResponse.fromJson(Map<String, dynamic> json) =>
      _$StatusResponseFromJson(json);

  static const toJsonFactory = _$StatusResponseToJson;
  Map<String, dynamic> toJson() => _$StatusResponseToJson(this);

  @JsonKey(name: 'status')
  final String status;
  static const fromJsonFactory = _$StatusResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StatusResponse &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^ runtimeType.hashCode;
}

extension $StatusResponseExtension on StatusResponse {
  StatusResponse copyWith({String? status}) {
    return StatusResponse(status: status ?? this.status);
  }

  StatusResponse copyWithWrapped({Wrapped<String>? status}) {
    return StatusResponse(
      status: (status != null ? status.value : this.status),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class StepsRecordRequest {
  const StepsRecordRequest({
    required this.hcId,
    required this.dataOrigin,
    required this.lastModifiedMs,
    required this.recordingMethod,
    this.device,
    required this.startMs,
    this.startOffsetS,
    required this.endMs,
    this.endOffsetS,
    required this.count,
  });

  factory StepsRecordRequest.fromJson(Map<String, dynamic> json) =>
      _$StepsRecordRequestFromJson(json);

  static const toJsonFactory = _$StepsRecordRequestToJson;
  Map<String, dynamic> toJson() => _$StepsRecordRequestToJson(this);

  @JsonKey(name: 'hc_id')
  final String hcId;
  @JsonKey(name: 'data_origin')
  final String dataOrigin;
  @JsonKey(name: 'last_modified_ms')
  final int lastModifiedMs;
  @JsonKey(
    name: 'recording_method',
    toJson: recordingMethodEnumToJson,
    fromJson: recordingMethodEnumFromJson,
  )
  final enums.RecordingMethodEnum recordingMethod;
  @JsonKey(name: 'device')
  final HealthDeviceRequest? device;
  @JsonKey(name: 'start_ms')
  final int startMs;
  @JsonKey(name: 'start_offset_s')
  final int? startOffsetS;
  @JsonKey(name: 'end_ms')
  final int endMs;
  @JsonKey(name: 'end_offset_s')
  final int? endOffsetS;
  @JsonKey(name: 'count')
  final int count;
  static const fromJsonFactory = _$StepsRecordRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StepsRecordRequest &&
            (identical(other.hcId, hcId) ||
                const DeepCollectionEquality().equals(other.hcId, hcId)) &&
            (identical(other.dataOrigin, dataOrigin) ||
                const DeepCollectionEquality().equals(
                  other.dataOrigin,
                  dataOrigin,
                )) &&
            (identical(other.lastModifiedMs, lastModifiedMs) ||
                const DeepCollectionEquality().equals(
                  other.lastModifiedMs,
                  lastModifiedMs,
                )) &&
            (identical(other.recordingMethod, recordingMethod) ||
                const DeepCollectionEquality().equals(
                  other.recordingMethod,
                  recordingMethod,
                )) &&
            (identical(other.device, device) ||
                const DeepCollectionEquality().equals(other.device, device)) &&
            (identical(other.startMs, startMs) ||
                const DeepCollectionEquality().equals(
                  other.startMs,
                  startMs,
                )) &&
            (identical(other.startOffsetS, startOffsetS) ||
                const DeepCollectionEquality().equals(
                  other.startOffsetS,
                  startOffsetS,
                )) &&
            (identical(other.endMs, endMs) ||
                const DeepCollectionEquality().equals(other.endMs, endMs)) &&
            (identical(other.endOffsetS, endOffsetS) ||
                const DeepCollectionEquality().equals(
                  other.endOffsetS,
                  endOffsetS,
                )) &&
            (identical(other.count, count) ||
                const DeepCollectionEquality().equals(other.count, count)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(hcId) ^
      const DeepCollectionEquality().hash(dataOrigin) ^
      const DeepCollectionEquality().hash(lastModifiedMs) ^
      const DeepCollectionEquality().hash(recordingMethod) ^
      const DeepCollectionEquality().hash(device) ^
      const DeepCollectionEquality().hash(startMs) ^
      const DeepCollectionEquality().hash(startOffsetS) ^
      const DeepCollectionEquality().hash(endMs) ^
      const DeepCollectionEquality().hash(endOffsetS) ^
      const DeepCollectionEquality().hash(count) ^
      runtimeType.hashCode;
}

extension $StepsRecordRequestExtension on StepsRecordRequest {
  StepsRecordRequest copyWith({
    String? hcId,
    String? dataOrigin,
    int? lastModifiedMs,
    enums.RecordingMethodEnum? recordingMethod,
    HealthDeviceRequest? device,
    int? startMs,
    int? startOffsetS,
    int? endMs,
    int? endOffsetS,
    int? count,
  }) {
    return StepsRecordRequest(
      hcId: hcId ?? this.hcId,
      dataOrigin: dataOrigin ?? this.dataOrigin,
      lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
      recordingMethod: recordingMethod ?? this.recordingMethod,
      device: device ?? this.device,
      startMs: startMs ?? this.startMs,
      startOffsetS: startOffsetS ?? this.startOffsetS,
      endMs: endMs ?? this.endMs,
      endOffsetS: endOffsetS ?? this.endOffsetS,
      count: count ?? this.count,
    );
  }

  StepsRecordRequest copyWithWrapped({
    Wrapped<String>? hcId,
    Wrapped<String>? dataOrigin,
    Wrapped<int>? lastModifiedMs,
    Wrapped<enums.RecordingMethodEnum>? recordingMethod,
    Wrapped<HealthDeviceRequest?>? device,
    Wrapped<int>? startMs,
    Wrapped<int?>? startOffsetS,
    Wrapped<int>? endMs,
    Wrapped<int?>? endOffsetS,
    Wrapped<int>? count,
  }) {
    return StepsRecordRequest(
      hcId: (hcId != null ? hcId.value : this.hcId),
      dataOrigin: (dataOrigin != null ? dataOrigin.value : this.dataOrigin),
      lastModifiedMs: (lastModifiedMs != null
          ? lastModifiedMs.value
          : this.lastModifiedMs),
      recordingMethod: (recordingMethod != null
          ? recordingMethod.value
          : this.recordingMethod),
      device: (device != null ? device.value : this.device),
      startMs: (startMs != null ? startMs.value : this.startMs),
      startOffsetS: (startOffsetS != null
          ? startOffsetS.value
          : this.startOffsetS),
      endMs: (endMs != null ? endMs.value : this.endMs),
      endOffsetS: (endOffsetS != null ? endOffsetS.value : this.endOffsetS),
      count: (count != null ? count.value : this.count),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Strategy {
  const Strategy({this.id, this.user, required this.stratCls, this.data});

  factory Strategy.fromJson(Map<String, dynamic> json) =>
      _$StrategyFromJson(json);

  static const toJsonFactory = _$StrategyToJson;
  Map<String, dynamic> toJson() => _$StrategyToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'user')
  final int? user;
  @JsonKey(
    name: 'strat_cls',
    toJson: stratClsEnumToJson,
    fromJson: stratClsEnumFromJson,
  )
  final enums.StratClsEnum stratCls;
  @JsonKey(name: 'data')
  final dynamic data;
  static const fromJsonFactory = _$StrategyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Strategy &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.user, user) ||
                const DeepCollectionEquality().equals(other.user, user)) &&
            (identical(other.stratCls, stratCls) ||
                const DeepCollectionEquality().equals(
                  other.stratCls,
                  stratCls,
                )) &&
            (identical(other.data, data) ||
                const DeepCollectionEquality().equals(other.data, data)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(user) ^
      const DeepCollectionEquality().hash(stratCls) ^
      const DeepCollectionEquality().hash(data) ^
      runtimeType.hashCode;
}

extension $StrategyExtension on Strategy {
  Strategy copyWith({
    int? id,
    int? user,
    enums.StratClsEnum? stratCls,
    dynamic data,
  }) {
    return Strategy(
      id: id ?? this.id,
      user: user ?? this.user,
      stratCls: stratCls ?? this.stratCls,
      data: data ?? this.data,
    );
  }

  Strategy copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<int?>? user,
    Wrapped<enums.StratClsEnum>? stratCls,
    Wrapped<dynamic>? data,
  }) {
    return Strategy(
      id: (id != null ? id.value : this.id),
      user: (user != null ? user.value : this.user),
      stratCls: (stratCls != null ? stratCls.value : this.stratCls),
      data: (data != null ? data.value : this.data),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class StrategyRequest {
  const StrategyRequest({required this.stratCls, this.data});

  factory StrategyRequest.fromJson(Map<String, dynamic> json) =>
      _$StrategyRequestFromJson(json);

  static const toJsonFactory = _$StrategyRequestToJson;
  Map<String, dynamic> toJson() => _$StrategyRequestToJson(this);

  @JsonKey(
    name: 'strat_cls',
    toJson: stratClsEnumToJson,
    fromJson: stratClsEnumFromJson,
  )
  final enums.StratClsEnum stratCls;
  @JsonKey(name: 'data')
  final dynamic data;
  static const fromJsonFactory = _$StrategyRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StrategyRequest &&
            (identical(other.stratCls, stratCls) ||
                const DeepCollectionEquality().equals(
                  other.stratCls,
                  stratCls,
                )) &&
            (identical(other.data, data) ||
                const DeepCollectionEquality().equals(other.data, data)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(stratCls) ^
      const DeepCollectionEquality().hash(data) ^
      runtimeType.hashCode;
}

extension $StrategyRequestExtension on StrategyRequest {
  StrategyRequest copyWith({enums.StratClsEnum? stratCls, dynamic data}) {
    return StrategyRequest(
      stratCls: stratCls ?? this.stratCls,
      data: data ?? this.data,
    );
  }

  StrategyRequest copyWithWrapped({
    Wrapped<enums.StratClsEnum>? stratCls,
    Wrapped<dynamic>? data,
  }) {
    return StrategyRequest(
      stratCls: (stratCls != null ? stratCls.value : this.stratCls),
      data: (data != null ? data.value : this.data),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class SystemEvent {
  const SystemEvent({
    this.id,
    this.createdAt,
    this.level,
    this.source,
    this.kind,
    this.message,
    this.details,
  });

  factory SystemEvent.fromJson(Map<String, dynamic> json) =>
      _$SystemEventFromJson(json);

  static const toJsonFactory = _$SystemEventToJson;
  Map<String, dynamic> toJson() => _$SystemEventToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @JsonKey(
    name: 'level',
    toJson: levelEnumNullableToJson,
    fromJson: levelEnumNullableFromJson,
  )
  final enums.LevelEnum? level;
  @JsonKey(name: 'source')
  final String? source;
  @JsonKey(name: 'kind')
  final String? kind;
  @JsonKey(name: 'message')
  final String? message;
  @JsonKey(name: 'details')
  final dynamic details;
  static const fromJsonFactory = _$SystemEventFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SystemEvent &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.createdAt, createdAt) ||
                const DeepCollectionEquality().equals(
                  other.createdAt,
                  createdAt,
                )) &&
            (identical(other.level, level) ||
                const DeepCollectionEquality().equals(other.level, level)) &&
            (identical(other.source, source) ||
                const DeepCollectionEquality().equals(other.source, source)) &&
            (identical(other.kind, kind) ||
                const DeepCollectionEquality().equals(other.kind, kind)) &&
            (identical(other.message, message) ||
                const DeepCollectionEquality().equals(
                  other.message,
                  message,
                )) &&
            (identical(other.details, details) ||
                const DeepCollectionEquality().equals(other.details, details)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(createdAt) ^
      const DeepCollectionEquality().hash(level) ^
      const DeepCollectionEquality().hash(source) ^
      const DeepCollectionEquality().hash(kind) ^
      const DeepCollectionEquality().hash(message) ^
      const DeepCollectionEquality().hash(details) ^
      runtimeType.hashCode;
}

extension $SystemEventExtension on SystemEvent {
  SystemEvent copyWith({
    int? id,
    DateTime? createdAt,
    enums.LevelEnum? level,
    String? source,
    String? kind,
    String? message,
    dynamic details,
  }) {
    return SystemEvent(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      level: level ?? this.level,
      source: source ?? this.source,
      kind: kind ?? this.kind,
      message: message ?? this.message,
      details: details ?? this.details,
    );
  }

  SystemEvent copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<DateTime?>? createdAt,
    Wrapped<enums.LevelEnum?>? level,
    Wrapped<String?>? source,
    Wrapped<String?>? kind,
    Wrapped<String?>? message,
    Wrapped<dynamic>? details,
  }) {
    return SystemEvent(
      id: (id != null ? id.value : this.id),
      createdAt: (createdAt != null ? createdAt.value : this.createdAt),
      level: (level != null ? level.value : this.level),
      source: (source != null ? source.value : this.source),
      kind: (kind != null ? kind.value : this.kind),
      message: (message != null ? message.value : this.message),
      details: (details != null ? details.value : this.details),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class TriggerScrapeLinkResult {
  const TriggerScrapeLinkResult({
    required this.status,
    this.updatesFound,
    this.message,
  });

  factory TriggerScrapeLinkResult.fromJson(Map<String, dynamic> json) =>
      _$TriggerScrapeLinkResultFromJson(json);

  static const toJsonFactory = _$TriggerScrapeLinkResultToJson;
  Map<String, dynamic> toJson() => _$TriggerScrapeLinkResultToJson(this);

  @JsonKey(name: 'status')
  final String status;
  @JsonKey(name: 'updates_found')
  final int? updatesFound;
  @JsonKey(name: 'message')
  final String? message;
  static const fromJsonFactory = _$TriggerScrapeLinkResultFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TriggerScrapeLinkResult &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)) &&
            (identical(other.updatesFound, updatesFound) ||
                const DeepCollectionEquality().equals(
                  other.updatesFound,
                  updatesFound,
                )) &&
            (identical(other.message, message) ||
                const DeepCollectionEquality().equals(other.message, message)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^
      const DeepCollectionEquality().hash(updatesFound) ^
      const DeepCollectionEquality().hash(message) ^
      runtimeType.hashCode;
}

extension $TriggerScrapeLinkResultExtension on TriggerScrapeLinkResult {
  TriggerScrapeLinkResult copyWith({
    String? status,
    int? updatesFound,
    String? message,
  }) {
    return TriggerScrapeLinkResult(
      status: status ?? this.status,
      updatesFound: updatesFound ?? this.updatesFound,
      message: message ?? this.message,
    );
  }

  TriggerScrapeLinkResult copyWithWrapped({
    Wrapped<String>? status,
    Wrapped<int?>? updatesFound,
    Wrapped<String?>? message,
  }) {
    return TriggerScrapeLinkResult(
      status: (status != null ? status.value : this.status),
      updatesFound: (updatesFound != null
          ? updatesFound.value
          : this.updatesFound),
      message: (message != null ? message.value : this.message),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class TriggerScrapeRequest {
  const TriggerScrapeRequest({this.linkId});

  factory TriggerScrapeRequest.fromJson(Map<String, dynamic> json) =>
      _$TriggerScrapeRequestFromJson(json);

  static const toJsonFactory = _$TriggerScrapeRequestToJson;
  Map<String, dynamic> toJson() => _$TriggerScrapeRequestToJson(this);

  @JsonKey(name: 'link_id')
  final int? linkId;
  static const fromJsonFactory = _$TriggerScrapeRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TriggerScrapeRequest &&
            (identical(other.linkId, linkId) ||
                const DeepCollectionEquality().equals(other.linkId, linkId)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(linkId) ^ runtimeType.hashCode;
}

extension $TriggerScrapeRequestExtension on TriggerScrapeRequest {
  TriggerScrapeRequest copyWith({int? linkId}) {
    return TriggerScrapeRequest(linkId: linkId ?? this.linkId);
  }

  TriggerScrapeRequest copyWithWrapped({Wrapped<int?>? linkId}) {
    return TriggerScrapeRequest(
      linkId: (linkId != null ? linkId.value : this.linkId),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class TriggerScrapeResponse {
  const TriggerScrapeResponse({
    required this.status,
    this.updatesFound,
    this.message,
    this.results,
  });

  factory TriggerScrapeResponse.fromJson(Map<String, dynamic> json) =>
      _$TriggerScrapeResponseFromJson(json);

  static const toJsonFactory = _$TriggerScrapeResponseToJson;
  Map<String, dynamic> toJson() => _$TriggerScrapeResponseToJson(this);

  @JsonKey(name: 'status')
  final String status;
  @JsonKey(name: 'updates_found')
  final int? updatesFound;
  @JsonKey(name: 'message')
  final String? message;
  @JsonKey(name: 'results')
  final Map<String, dynamic>? results;
  static const fromJsonFactory = _$TriggerScrapeResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TriggerScrapeResponse &&
            (identical(other.status, status) ||
                const DeepCollectionEquality().equals(other.status, status)) &&
            (identical(other.updatesFound, updatesFound) ||
                const DeepCollectionEquality().equals(
                  other.updatesFound,
                  updatesFound,
                )) &&
            (identical(other.message, message) ||
                const DeepCollectionEquality().equals(
                  other.message,
                  message,
                )) &&
            (identical(other.results, results) ||
                const DeepCollectionEquality().equals(other.results, results)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(status) ^
      const DeepCollectionEquality().hash(updatesFound) ^
      const DeepCollectionEquality().hash(message) ^
      const DeepCollectionEquality().hash(results) ^
      runtimeType.hashCode;
}

extension $TriggerScrapeResponseExtension on TriggerScrapeResponse {
  TriggerScrapeResponse copyWith({
    String? status,
    int? updatesFound,
    String? message,
    Map<String, dynamic>? results,
  }) {
    return TriggerScrapeResponse(
      status: status ?? this.status,
      updatesFound: updatesFound ?? this.updatesFound,
      message: message ?? this.message,
      results: results ?? this.results,
    );
  }

  TriggerScrapeResponse copyWithWrapped({
    Wrapped<String>? status,
    Wrapped<int?>? updatesFound,
    Wrapped<String?>? message,
    Wrapped<Map<String, dynamic>?>? results,
  }) {
    return TriggerScrapeResponse(
      status: (status != null ? status.value : this.status),
      updatesFound: (updatesFound != null
          ? updatesFound.value
          : this.updatesFound),
      message: (message != null ? message.value : this.message),
      results: (results != null ? results.value : this.results),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Update {
  const Update({
    this.id,
    this.link,
    this.title,
    this.description,
    this.itemUrl,
    this.createdAt,
  });

  factory Update.fromJson(Map<String, dynamic> json) => _$UpdateFromJson(json);

  static const toJsonFactory = _$UpdateToJson;
  Map<String, dynamic> toJson() => _$UpdateToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'link')
  final int? link;
  @JsonKey(name: 'title')
  final String? title;
  @JsonKey(name: 'description')
  final String? description;
  @JsonKey(name: 'item_url')
  final String? itemUrl;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  static const fromJsonFactory = _$UpdateFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Update &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.link, link) ||
                const DeepCollectionEquality().equals(other.link, link)) &&
            (identical(other.title, title) ||
                const DeepCollectionEquality().equals(other.title, title)) &&
            (identical(other.description, description) ||
                const DeepCollectionEquality().equals(
                  other.description,
                  description,
                )) &&
            (identical(other.itemUrl, itemUrl) ||
                const DeepCollectionEquality().equals(
                  other.itemUrl,
                  itemUrl,
                )) &&
            (identical(other.createdAt, createdAt) ||
                const DeepCollectionEquality().equals(
                  other.createdAt,
                  createdAt,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(link) ^
      const DeepCollectionEquality().hash(title) ^
      const DeepCollectionEquality().hash(description) ^
      const DeepCollectionEquality().hash(itemUrl) ^
      const DeepCollectionEquality().hash(createdAt) ^
      runtimeType.hashCode;
}

extension $UpdateExtension on Update {
  Update copyWith({
    int? id,
    int? link,
    String? title,
    String? description,
    String? itemUrl,
    DateTime? createdAt,
  }) {
    return Update(
      id: id ?? this.id,
      link: link ?? this.link,
      title: title ?? this.title,
      description: description ?? this.description,
      itemUrl: itemUrl ?? this.itemUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Update copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<int?>? link,
    Wrapped<String?>? title,
    Wrapped<String?>? description,
    Wrapped<String?>? itemUrl,
    Wrapped<DateTime?>? createdAt,
  }) {
    return Update(
      id: (id != null ? id.value : this.id),
      link: (link != null ? link.value : this.link),
      title: (title != null ? title.value : this.title),
      description: (description != null ? description.value : this.description),
      itemUrl: (itemUrl != null ? itemUrl.value : this.itemUrl),
      createdAt: (createdAt != null ? createdAt.value : this.createdAt),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UserCreation {
  const UserCreation({required this.username, required this.email, this.name});

  factory UserCreation.fromJson(Map<String, dynamic> json) =>
      _$UserCreationFromJson(json);

  static const toJsonFactory = _$UserCreationToJson;
  Map<String, dynamic> toJson() => _$UserCreationToJson(this);

  @JsonKey(name: 'username')
  final String username;
  @JsonKey(name: 'email')
  final String email;
  @JsonKey(name: 'name')
  final String? name;
  static const fromJsonFactory = _$UserCreationFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UserCreation &&
            (identical(other.username, username) ||
                const DeepCollectionEquality().equals(
                  other.username,
                  username,
                )) &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(username) ^
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(name) ^
      runtimeType.hashCode;
}

extension $UserCreationExtension on UserCreation {
  UserCreation copyWith({String? username, String? email, String? name}) {
    return UserCreation(
      username: username ?? this.username,
      email: email ?? this.email,
      name: name ?? this.name,
    );
  }

  UserCreation copyWithWrapped({
    Wrapped<String>? username,
    Wrapped<String>? email,
    Wrapped<String?>? name,
  }) {
    return UserCreation(
      username: (username != null ? username.value : this.username),
      email: (email != null ? email.value : this.email),
      name: (name != null ? name.value : this.name),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UserCreationRequest {
  const UserCreationRequest({
    required this.username,
    required this.email,
    this.name,
    this.password,
  });

  factory UserCreationRequest.fromJson(Map<String, dynamic> json) =>
      _$UserCreationRequestFromJson(json);

  static const toJsonFactory = _$UserCreationRequestToJson;
  Map<String, dynamic> toJson() => _$UserCreationRequestToJson(this);

  @JsonKey(name: 'username')
  final String username;
  @JsonKey(name: 'email')
  final String email;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'password')
  final String? password;
  static const fromJsonFactory = _$UserCreationRequestFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UserCreationRequest &&
            (identical(other.username, username) ||
                const DeepCollectionEquality().equals(
                  other.username,
                  username,
                )) &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(username) ^
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(password) ^
      runtimeType.hashCode;
}

extension $UserCreationRequestExtension on UserCreationRequest {
  UserCreationRequest copyWith({
    String? username,
    String? email,
    String? name,
    String? password,
  }) {
    return UserCreationRequest(
      username: username ?? this.username,
      email: email ?? this.email,
      name: name ?? this.name,
      password: password ?? this.password,
    );
  }

  UserCreationRequest copyWithWrapped({
    Wrapped<String>? username,
    Wrapped<String>? email,
    Wrapped<String?>? name,
    Wrapped<String?>? password,
  }) {
    return UserCreationRequest(
      username: (username != null ? username.value : this.username),
      email: (email != null ? email.value : this.email),
      name: (name != null ? name.value : this.name),
      password: (password != null ? password.value : this.password),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UserFullRead {
  const UserFullRead({
    this.id,
    this.name,
    required this.email,
    required this.username,
    this.isStaff,
    this.isSuperuser,
    this.dateCreated,
    this.dateModified,
    this.dateDeleted,
  });

  factory UserFullRead.fromJson(Map<String, dynamic> json) =>
      _$UserFullReadFromJson(json);

  static const toJsonFactory = _$UserFullReadToJson;
  Map<String, dynamic> toJson() => _$UserFullReadToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'email')
  final String email;
  @JsonKey(name: 'username')
  final String username;
  @JsonKey(name: 'is_staff')
  final bool? isStaff;
  @JsonKey(name: 'is_superuser')
  final bool? isSuperuser;
  @JsonKey(name: 'date_created')
  final DateTime? dateCreated;
  @JsonKey(name: 'date_modified')
  final DateTime? dateModified;
  @JsonKey(name: 'date_deleted')
  final DateTime? dateDeleted;
  static const fromJsonFactory = _$UserFullReadFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UserFullRead &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.username, username) ||
                const DeepCollectionEquality().equals(
                  other.username,
                  username,
                )) &&
            (identical(other.isStaff, isStaff) ||
                const DeepCollectionEquality().equals(
                  other.isStaff,
                  isStaff,
                )) &&
            (identical(other.isSuperuser, isSuperuser) ||
                const DeepCollectionEquality().equals(
                  other.isSuperuser,
                  isSuperuser,
                )) &&
            (identical(other.dateCreated, dateCreated) ||
                const DeepCollectionEquality().equals(
                  other.dateCreated,
                  dateCreated,
                )) &&
            (identical(other.dateModified, dateModified) ||
                const DeepCollectionEquality().equals(
                  other.dateModified,
                  dateModified,
                )) &&
            (identical(other.dateDeleted, dateDeleted) ||
                const DeepCollectionEquality().equals(
                  other.dateDeleted,
                  dateDeleted,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(username) ^
      const DeepCollectionEquality().hash(isStaff) ^
      const DeepCollectionEquality().hash(isSuperuser) ^
      const DeepCollectionEquality().hash(dateCreated) ^
      const DeepCollectionEquality().hash(dateModified) ^
      const DeepCollectionEquality().hash(dateDeleted) ^
      runtimeType.hashCode;
}

extension $UserFullReadExtension on UserFullRead {
  UserFullRead copyWith({
    int? id,
    String? name,
    String? email,
    String? username,
    bool? isStaff,
    bool? isSuperuser,
    DateTime? dateCreated,
    DateTime? dateModified,
    DateTime? dateDeleted,
  }) {
    return UserFullRead(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      username: username ?? this.username,
      isStaff: isStaff ?? this.isStaff,
      isSuperuser: isSuperuser ?? this.isSuperuser,
      dateCreated: dateCreated ?? this.dateCreated,
      dateModified: dateModified ?? this.dateModified,
      dateDeleted: dateDeleted ?? this.dateDeleted,
    );
  }

  UserFullRead copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<String?>? name,
    Wrapped<String>? email,
    Wrapped<String>? username,
    Wrapped<bool?>? isStaff,
    Wrapped<bool?>? isSuperuser,
    Wrapped<DateTime?>? dateCreated,
    Wrapped<DateTime?>? dateModified,
    Wrapped<DateTime?>? dateDeleted,
  }) {
    return UserFullRead(
      id: (id != null ? id.value : this.id),
      name: (name != null ? name.value : this.name),
      email: (email != null ? email.value : this.email),
      username: (username != null ? username.value : this.username),
      isStaff: (isStaff != null ? isStaff.value : this.isStaff),
      isSuperuser: (isSuperuser != null ? isSuperuser.value : this.isSuperuser),
      dateCreated: (dateCreated != null ? dateCreated.value : this.dateCreated),
      dateModified: (dateModified != null
          ? dateModified.value
          : this.dateModified),
      dateDeleted: (dateDeleted != null ? dateDeleted.value : this.dateDeleted),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UserMinimalRead {
  const UserMinimalRead({required this.username, this.dateCreated});

  factory UserMinimalRead.fromJson(Map<String, dynamic> json) =>
      _$UserMinimalReadFromJson(json);

  static const toJsonFactory = _$UserMinimalReadToJson;
  Map<String, dynamic> toJson() => _$UserMinimalReadToJson(this);

  @JsonKey(name: 'username')
  final String username;
  @JsonKey(name: 'date_created')
  final DateTime? dateCreated;
  static const fromJsonFactory = _$UserMinimalReadFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UserMinimalRead &&
            (identical(other.username, username) ||
                const DeepCollectionEquality().equals(
                  other.username,
                  username,
                )) &&
            (identical(other.dateCreated, dateCreated) ||
                const DeepCollectionEquality().equals(
                  other.dateCreated,
                  dateCreated,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(username) ^
      const DeepCollectionEquality().hash(dateCreated) ^
      runtimeType.hashCode;
}

extension $UserMinimalReadExtension on UserMinimalRead {
  UserMinimalRead copyWith({String? username, DateTime? dateCreated}) {
    return UserMinimalRead(
      username: username ?? this.username,
      dateCreated: dateCreated ?? this.dateCreated,
    );
  }

  UserMinimalRead copyWithWrapped({
    Wrapped<String>? username,
    Wrapped<DateTime?>? dateCreated,
  }) {
    return UserMinimalRead(
      username: (username != null ? username.value : this.username),
      dateCreated: (dateCreated != null ? dateCreated.value : this.dateCreated),
    );
  }
}

String? categoryEnumNullableToJson(enums.CategoryEnum? categoryEnum) {
  return categoryEnum?.value;
}

String? categoryEnumToJson(enums.CategoryEnum categoryEnum) {
  return categoryEnum.value;
}

enums.CategoryEnum categoryEnumFromJson(
  Object? categoryEnum, [
  enums.CategoryEnum? defaultValue,
]) {
  return enums.CategoryEnum.values.firstWhereOrNull(
        (e) => e.value == categoryEnum,
      ) ??
      defaultValue ??
      enums.CategoryEnum.swaggerGeneratedUnknown;
}

enums.CategoryEnum? categoryEnumNullableFromJson(
  Object? categoryEnum, [
  enums.CategoryEnum? defaultValue,
]) {
  if (categoryEnum == null) {
    return null;
  }
  return enums.CategoryEnum.values.firstWhereOrNull(
        (e) => e.value == categoryEnum,
      ) ??
      defaultValue;
}

String categoryEnumExplodedListToJson(List<enums.CategoryEnum>? categoryEnum) {
  return categoryEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> categoryEnumListToJson(List<enums.CategoryEnum>? categoryEnum) {
  if (categoryEnum == null) {
    return [];
  }

  return categoryEnum.map((e) => e.value!).toList();
}

List<enums.CategoryEnum> categoryEnumListFromJson(
  List? categoryEnum, [
  List<enums.CategoryEnum>? defaultValue,
]) {
  if (categoryEnum == null) {
    return defaultValue ?? [];
  }

  return categoryEnum.map((e) => categoryEnumFromJson(e.toString())).toList();
}

List<enums.CategoryEnum>? categoryEnumNullableListFromJson(
  List? categoryEnum, [
  List<enums.CategoryEnum>? defaultValue,
]) {
  if (categoryEnum == null) {
    return defaultValue;
  }

  return categoryEnum.map((e) => categoryEnumFromJson(e.toString())).toList();
}

String? healthAggregateMetricEnumNullableToJson(
  enums.HealthAggregateMetricEnum? healthAggregateMetricEnum,
) {
  return healthAggregateMetricEnum?.value;
}

String? healthAggregateMetricEnumToJson(
  enums.HealthAggregateMetricEnum healthAggregateMetricEnum,
) {
  return healthAggregateMetricEnum.value;
}

enums.HealthAggregateMetricEnum healthAggregateMetricEnumFromJson(
  Object? healthAggregateMetricEnum, [
  enums.HealthAggregateMetricEnum? defaultValue,
]) {
  return enums.HealthAggregateMetricEnum.values.firstWhereOrNull(
        (e) => e.value == healthAggregateMetricEnum,
      ) ??
      defaultValue ??
      enums.HealthAggregateMetricEnum.swaggerGeneratedUnknown;
}

enums.HealthAggregateMetricEnum? healthAggregateMetricEnumNullableFromJson(
  Object? healthAggregateMetricEnum, [
  enums.HealthAggregateMetricEnum? defaultValue,
]) {
  if (healthAggregateMetricEnum == null) {
    return null;
  }
  return enums.HealthAggregateMetricEnum.values.firstWhereOrNull(
        (e) => e.value == healthAggregateMetricEnum,
      ) ??
      defaultValue;
}

String healthAggregateMetricEnumExplodedListToJson(
  List<enums.HealthAggregateMetricEnum>? healthAggregateMetricEnum,
) {
  return healthAggregateMetricEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> healthAggregateMetricEnumListToJson(
  List<enums.HealthAggregateMetricEnum>? healthAggregateMetricEnum,
) {
  if (healthAggregateMetricEnum == null) {
    return [];
  }

  return healthAggregateMetricEnum.map((e) => e.value!).toList();
}

List<enums.HealthAggregateMetricEnum> healthAggregateMetricEnumListFromJson(
  List? healthAggregateMetricEnum, [
  List<enums.HealthAggregateMetricEnum>? defaultValue,
]) {
  if (healthAggregateMetricEnum == null) {
    return defaultValue ?? [];
  }

  return healthAggregateMetricEnum
      .map((e) => healthAggregateMetricEnumFromJson(e.toString()))
      .toList();
}

List<enums.HealthAggregateMetricEnum>?
healthAggregateMetricEnumNullableListFromJson(
  List? healthAggregateMetricEnum, [
  List<enums.HealthAggregateMetricEnum>? defaultValue,
]) {
  if (healthAggregateMetricEnum == null) {
    return defaultValue;
  }

  return healthAggregateMetricEnum
      .map((e) => healthAggregateMetricEnumFromJson(e.toString()))
      .toList();
}

String? healthDeviceTypeEnumNullableToJson(
  enums.HealthDeviceTypeEnum? healthDeviceTypeEnum,
) {
  return healthDeviceTypeEnum?.value;
}

String? healthDeviceTypeEnumToJson(
  enums.HealthDeviceTypeEnum healthDeviceTypeEnum,
) {
  return healthDeviceTypeEnum.value;
}

enums.HealthDeviceTypeEnum healthDeviceTypeEnumFromJson(
  Object? healthDeviceTypeEnum, [
  enums.HealthDeviceTypeEnum? defaultValue,
]) {
  return enums.HealthDeviceTypeEnum.values.firstWhereOrNull(
        (e) => e.value == healthDeviceTypeEnum,
      ) ??
      defaultValue ??
      enums.HealthDeviceTypeEnum.swaggerGeneratedUnknown;
}

enums.HealthDeviceTypeEnum? healthDeviceTypeEnumNullableFromJson(
  Object? healthDeviceTypeEnum, [
  enums.HealthDeviceTypeEnum? defaultValue,
]) {
  if (healthDeviceTypeEnum == null) {
    return null;
  }
  return enums.HealthDeviceTypeEnum.values.firstWhereOrNull(
        (e) => e.value == healthDeviceTypeEnum,
      ) ??
      defaultValue;
}

String healthDeviceTypeEnumExplodedListToJson(
  List<enums.HealthDeviceTypeEnum>? healthDeviceTypeEnum,
) {
  return healthDeviceTypeEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> healthDeviceTypeEnumListToJson(
  List<enums.HealthDeviceTypeEnum>? healthDeviceTypeEnum,
) {
  if (healthDeviceTypeEnum == null) {
    return [];
  }

  return healthDeviceTypeEnum.map((e) => e.value!).toList();
}

List<enums.HealthDeviceTypeEnum> healthDeviceTypeEnumListFromJson(
  List? healthDeviceTypeEnum, [
  List<enums.HealthDeviceTypeEnum>? defaultValue,
]) {
  if (healthDeviceTypeEnum == null) {
    return defaultValue ?? [];
  }

  return healthDeviceTypeEnum
      .map((e) => healthDeviceTypeEnumFromJson(e.toString()))
      .toList();
}

List<enums.HealthDeviceTypeEnum>? healthDeviceTypeEnumNullableListFromJson(
  List? healthDeviceTypeEnum, [
  List<enums.HealthDeviceTypeEnum>? defaultValue,
]) {
  if (healthDeviceTypeEnum == null) {
    return defaultValue;
  }

  return healthDeviceTypeEnum
      .map((e) => healthDeviceTypeEnumFromJson(e.toString()))
      .toList();
}

String? levelEnumNullableToJson(enums.LevelEnum? levelEnum) {
  return levelEnum?.value;
}

String? levelEnumToJson(enums.LevelEnum levelEnum) {
  return levelEnum.value;
}

enums.LevelEnum levelEnumFromJson(
  Object? levelEnum, [
  enums.LevelEnum? defaultValue,
]) {
  return enums.LevelEnum.values.firstWhereOrNull((e) => e.value == levelEnum) ??
      defaultValue ??
      enums.LevelEnum.swaggerGeneratedUnknown;
}

enums.LevelEnum? levelEnumNullableFromJson(
  Object? levelEnum, [
  enums.LevelEnum? defaultValue,
]) {
  if (levelEnum == null) {
    return null;
  }
  return enums.LevelEnum.values.firstWhereOrNull((e) => e.value == levelEnum) ??
      defaultValue;
}

String levelEnumExplodedListToJson(List<enums.LevelEnum>? levelEnum) {
  return levelEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> levelEnumListToJson(List<enums.LevelEnum>? levelEnum) {
  if (levelEnum == null) {
    return [];
  }

  return levelEnum.map((e) => e.value!).toList();
}

List<enums.LevelEnum> levelEnumListFromJson(
  List? levelEnum, [
  List<enums.LevelEnum>? defaultValue,
]) {
  if (levelEnum == null) {
    return defaultValue ?? [];
  }

  return levelEnum.map((e) => levelEnumFromJson(e.toString())).toList();
}

List<enums.LevelEnum>? levelEnumNullableListFromJson(
  List? levelEnum, [
  List<enums.LevelEnum>? defaultValue,
]) {
  if (levelEnum == null) {
    return defaultValue;
  }

  return levelEnum.map((e) => levelEnumFromJson(e.toString())).toList();
}

String? recordingMethodEnumNullableToJson(
  enums.RecordingMethodEnum? recordingMethodEnum,
) {
  return recordingMethodEnum?.value;
}

String? recordingMethodEnumToJson(
  enums.RecordingMethodEnum recordingMethodEnum,
) {
  return recordingMethodEnum.value;
}

enums.RecordingMethodEnum recordingMethodEnumFromJson(
  Object? recordingMethodEnum, [
  enums.RecordingMethodEnum? defaultValue,
]) {
  return enums.RecordingMethodEnum.values.firstWhereOrNull(
        (e) => e.value == recordingMethodEnum,
      ) ??
      defaultValue ??
      enums.RecordingMethodEnum.swaggerGeneratedUnknown;
}

enums.RecordingMethodEnum? recordingMethodEnumNullableFromJson(
  Object? recordingMethodEnum, [
  enums.RecordingMethodEnum? defaultValue,
]) {
  if (recordingMethodEnum == null) {
    return null;
  }
  return enums.RecordingMethodEnum.values.firstWhereOrNull(
        (e) => e.value == recordingMethodEnum,
      ) ??
      defaultValue;
}

String recordingMethodEnumExplodedListToJson(
  List<enums.RecordingMethodEnum>? recordingMethodEnum,
) {
  return recordingMethodEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> recordingMethodEnumListToJson(
  List<enums.RecordingMethodEnum>? recordingMethodEnum,
) {
  if (recordingMethodEnum == null) {
    return [];
  }

  return recordingMethodEnum.map((e) => e.value!).toList();
}

List<enums.RecordingMethodEnum> recordingMethodEnumListFromJson(
  List? recordingMethodEnum, [
  List<enums.RecordingMethodEnum>? defaultValue,
]) {
  if (recordingMethodEnum == null) {
    return defaultValue ?? [];
  }

  return recordingMethodEnum
      .map((e) => recordingMethodEnumFromJson(e.toString()))
      .toList();
}

List<enums.RecordingMethodEnum>? recordingMethodEnumNullableListFromJson(
  List? recordingMethodEnum, [
  List<enums.RecordingMethodEnum>? defaultValue,
]) {
  if (recordingMethodEnum == null) {
    return defaultValue;
  }

  return recordingMethodEnum
      .map((e) => recordingMethodEnumFromJson(e.toString()))
      .toList();
}

String? sleepStageEnumNullableToJson(enums.SleepStageEnum? sleepStageEnum) {
  return sleepStageEnum?.value;
}

String? sleepStageEnumToJson(enums.SleepStageEnum sleepStageEnum) {
  return sleepStageEnum.value;
}

enums.SleepStageEnum sleepStageEnumFromJson(
  Object? sleepStageEnum, [
  enums.SleepStageEnum? defaultValue,
]) {
  return enums.SleepStageEnum.values.firstWhereOrNull(
        (e) => e.value == sleepStageEnum,
      ) ??
      defaultValue ??
      enums.SleepStageEnum.swaggerGeneratedUnknown;
}

enums.SleepStageEnum? sleepStageEnumNullableFromJson(
  Object? sleepStageEnum, [
  enums.SleepStageEnum? defaultValue,
]) {
  if (sleepStageEnum == null) {
    return null;
  }
  return enums.SleepStageEnum.values.firstWhereOrNull(
        (e) => e.value == sleepStageEnum,
      ) ??
      defaultValue;
}

String sleepStageEnumExplodedListToJson(
  List<enums.SleepStageEnum>? sleepStageEnum,
) {
  return sleepStageEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> sleepStageEnumListToJson(
  List<enums.SleepStageEnum>? sleepStageEnum,
) {
  if (sleepStageEnum == null) {
    return [];
  }

  return sleepStageEnum.map((e) => e.value!).toList();
}

List<enums.SleepStageEnum> sleepStageEnumListFromJson(
  List? sleepStageEnum, [
  List<enums.SleepStageEnum>? defaultValue,
]) {
  if (sleepStageEnum == null) {
    return defaultValue ?? [];
  }

  return sleepStageEnum
      .map((e) => sleepStageEnumFromJson(e.toString()))
      .toList();
}

List<enums.SleepStageEnum>? sleepStageEnumNullableListFromJson(
  List? sleepStageEnum, [
  List<enums.SleepStageEnum>? defaultValue,
]) {
  if (sleepStageEnum == null) {
    return defaultValue;
  }

  return sleepStageEnum
      .map((e) => sleepStageEnumFromJson(e.toString()))
      .toList();
}

String? statusEnumNullableToJson(enums.StatusEnum? statusEnum) {
  return statusEnum?.value;
}

String? statusEnumToJson(enums.StatusEnum statusEnum) {
  return statusEnum.value;
}

enums.StatusEnum statusEnumFromJson(
  Object? statusEnum, [
  enums.StatusEnum? defaultValue,
]) {
  return enums.StatusEnum.values.firstWhereOrNull(
        (e) => e.value == statusEnum,
      ) ??
      defaultValue ??
      enums.StatusEnum.swaggerGeneratedUnknown;
}

enums.StatusEnum? statusEnumNullableFromJson(
  Object? statusEnum, [
  enums.StatusEnum? defaultValue,
]) {
  if (statusEnum == null) {
    return null;
  }
  return enums.StatusEnum.values.firstWhereOrNull(
        (e) => e.value == statusEnum,
      ) ??
      defaultValue;
}

String statusEnumExplodedListToJson(List<enums.StatusEnum>? statusEnum) {
  return statusEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> statusEnumListToJson(List<enums.StatusEnum>? statusEnum) {
  if (statusEnum == null) {
    return [];
  }

  return statusEnum.map((e) => e.value!).toList();
}

List<enums.StatusEnum> statusEnumListFromJson(
  List? statusEnum, [
  List<enums.StatusEnum>? defaultValue,
]) {
  if (statusEnum == null) {
    return defaultValue ?? [];
  }

  return statusEnum.map((e) => statusEnumFromJson(e.toString())).toList();
}

List<enums.StatusEnum>? statusEnumNullableListFromJson(
  List? statusEnum, [
  List<enums.StatusEnum>? defaultValue,
]) {
  if (statusEnum == null) {
    return defaultValue;
  }

  return statusEnum.map((e) => statusEnumFromJson(e.toString())).toList();
}

String? stratClsEnumNullableToJson(enums.StratClsEnum? stratClsEnum) {
  return stratClsEnum?.value;
}

String? stratClsEnumToJson(enums.StratClsEnum stratClsEnum) {
  return stratClsEnum.value;
}

enums.StratClsEnum stratClsEnumFromJson(
  Object? stratClsEnum, [
  enums.StratClsEnum? defaultValue,
]) {
  return enums.StratClsEnum.values.firstWhereOrNull(
        (e) => e.value == stratClsEnum,
      ) ??
      defaultValue ??
      enums.StratClsEnum.swaggerGeneratedUnknown;
}

enums.StratClsEnum? stratClsEnumNullableFromJson(
  Object? stratClsEnum, [
  enums.StratClsEnum? defaultValue,
]) {
  if (stratClsEnum == null) {
    return null;
  }
  return enums.StratClsEnum.values.firstWhereOrNull(
        (e) => e.value == stratClsEnum,
      ) ??
      defaultValue;
}

String stratClsEnumExplodedListToJson(List<enums.StratClsEnum>? stratClsEnum) {
  return stratClsEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> stratClsEnumListToJson(List<enums.StratClsEnum>? stratClsEnum) {
  if (stratClsEnum == null) {
    return [];
  }

  return stratClsEnum.map((e) => e.value!).toList();
}

List<enums.StratClsEnum> stratClsEnumListFromJson(
  List? stratClsEnum, [
  List<enums.StratClsEnum>? defaultValue,
]) {
  if (stratClsEnum == null) {
    return defaultValue ?? [];
  }

  return stratClsEnum.map((e) => stratClsEnumFromJson(e.toString())).toList();
}

List<enums.StratClsEnum>? stratClsEnumNullableListFromJson(
  List? stratClsEnum, [
  List<enums.StratClsEnum>? defaultValue,
]) {
  if (stratClsEnum == null) {
    return defaultValue;
  }

  return stratClsEnum.map((e) => stratClsEnumFromJson(e.toString())).toList();
}

String? transportEnumNullableToJson(enums.TransportEnum? transportEnum) {
  return transportEnum?.value;
}

String? transportEnumToJson(enums.TransportEnum transportEnum) {
  return transportEnum.value;
}

enums.TransportEnum transportEnumFromJson(
  Object? transportEnum, [
  enums.TransportEnum? defaultValue,
]) {
  return enums.TransportEnum.values.firstWhereOrNull(
        (e) => e.value == transportEnum,
      ) ??
      defaultValue ??
      enums.TransportEnum.swaggerGeneratedUnknown;
}

enums.TransportEnum? transportEnumNullableFromJson(
  Object? transportEnum, [
  enums.TransportEnum? defaultValue,
]) {
  if (transportEnum == null) {
    return null;
  }
  return enums.TransportEnum.values.firstWhereOrNull(
        (e) => e.value == transportEnum,
      ) ??
      defaultValue;
}

String transportEnumExplodedListToJson(
  List<enums.TransportEnum>? transportEnum,
) {
  return transportEnum?.map((e) => e.value!).join(',') ?? '';
}

List<String> transportEnumListToJson(List<enums.TransportEnum>? transportEnum) {
  if (transportEnum == null) {
    return [];
  }

  return transportEnum.map((e) => e.value!).toList();
}

List<enums.TransportEnum> transportEnumListFromJson(
  List? transportEnum, [
  List<enums.TransportEnum>? defaultValue,
]) {
  if (transportEnum == null) {
    return defaultValue ?? [];
  }

  return transportEnum.map((e) => transportEnumFromJson(e.toString())).toList();
}

List<enums.TransportEnum>? transportEnumNullableListFromJson(
  List? transportEnum, [
  List<enums.TransportEnum>? defaultValue,
]) {
  if (transportEnum == null) {
    return defaultValue;
  }

  return transportEnum.map((e) => transportEnumFromJson(e.toString())).toList();
}

// ignore: unused_element
String? _dateToJson(DateTime? date) {
  if (date == null) {
    return null;
  }

  final year = date.year.toString();
  final month = date.month < 10 ? '0${date.month}' : date.month.toString();
  final day = date.day < 10 ? '0${date.day}' : date.day.toString();

  return '$year-$month-$day';
}

class Wrapped<T> {
  final T value;
  const Wrapped.value(this.value);
}

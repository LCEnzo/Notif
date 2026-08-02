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
class ClientEvent {
  const ClientEvent({
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

  factory ClientEvent.fromJson(Map<String, dynamic> json) =>
      _$ClientEventFromJson(json);

  static const toJsonFactory = _$ClientEventToJson;
  Map<String, dynamic> toJson() => _$ClientEventToJson(this);

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
  static const fromJsonFactory = _$ClientEventFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ClientEvent &&
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

extension $ClientEventExtension on ClientEvent {
  ClientEvent copyWith({
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
    return ClientEvent(
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

  ClientEvent copyWithWrapped({
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
    return ClientEvent(
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
class PasswordResetConfirm {
  const PasswordResetConfirm({
    required this.email,
    required this.code,
    required this.newPassword,
  });

  factory PasswordResetConfirm.fromJson(Map<String, dynamic> json) =>
      _$PasswordResetConfirmFromJson(json);

  static const toJsonFactory = _$PasswordResetConfirmToJson;
  Map<String, dynamic> toJson() => _$PasswordResetConfirmToJson(this);

  @JsonKey(name: 'email')
  final String email;
  @JsonKey(name: 'code')
  final String code;
  @JsonKey(name: 'new_password')
  final String newPassword;
  static const fromJsonFactory = _$PasswordResetConfirmFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PasswordResetConfirm &&
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

extension $PasswordResetConfirmExtension on PasswordResetConfirm {
  PasswordResetConfirm copyWith({
    String? email,
    String? code,
    String? newPassword,
  }) {
    return PasswordResetConfirm(
      email: email ?? this.email,
      code: code ?? this.code,
      newPassword: newPassword ?? this.newPassword,
    );
  }

  PasswordResetConfirm copyWithWrapped({
    Wrapped<String>? email,
    Wrapped<String>? code,
    Wrapped<String>? newPassword,
  }) {
    return PasswordResetConfirm(
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
class PatchedLink {
  const PatchedLink({
    this.id,
    this.name,
    this.url,
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

  factory PatchedLink.fromJson(Map<String, dynamic> json) =>
      _$PatchedLinkFromJson(json);

  static const toJsonFactory = _$PatchedLinkToJson;
  Map<String, dynamic> toJson() => _$PatchedLinkToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'url')
  final String? url;
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
  static const fromJsonFactory = _$PatchedLinkFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PatchedLink &&
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

extension $PatchedLinkExtension on PatchedLink {
  PatchedLink copyWith({
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
    return PatchedLink(
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

  PatchedLink copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<String?>? name,
    Wrapped<String?>? url,
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
    return PatchedLink(
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
class PatchedNotification {
  const PatchedNotification({this.id, this.update, this.status, this.readAt});

  factory PatchedNotification.fromJson(Map<String, dynamic> json) =>
      _$PatchedNotificationFromJson(json);

  static const toJsonFactory = _$PatchedNotificationToJson;
  Map<String, dynamic> toJson() => _$PatchedNotificationToJson(this);

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
  static const fromJsonFactory = _$PatchedNotificationFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PatchedNotification &&
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

extension $PatchedNotificationExtension on PatchedNotification {
  PatchedNotification copyWith({
    int? id,
    Update? update,
    enums.StatusEnum? status,
    DateTime? readAt,
  }) {
    return PatchedNotification(
      id: id ?? this.id,
      update: update ?? this.update,
      status: status ?? this.status,
      readAt: readAt ?? this.readAt,
    );
  }

  PatchedNotification copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<Update?>? update,
    Wrapped<enums.StatusEnum?>? status,
    Wrapped<DateTime?>? readAt,
  }) {
    return PatchedNotification(
      id: (id != null ? id.value : this.id),
      update: (update != null ? update.value : this.update),
      status: (status != null ? status.value : this.status),
      readAt: (readAt != null ? readAt.value : this.readAt),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PatchedStrategy {
  const PatchedStrategy({this.id, this.data, this.stratCls, this.owner});

  factory PatchedStrategy.fromJson(Map<String, dynamic> json) =>
      _$PatchedStrategyFromJson(json);

  static const toJsonFactory = _$PatchedStrategyToJson;
  Map<String, dynamic> toJson() => _$PatchedStrategyToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'data')
  final dynamic data;
  @JsonKey(
    name: 'strat_cls',
    toJson: stratClsEnumNullableToJson,
    fromJson: stratClsEnumNullableFromJson,
  )
  final enums.StratClsEnum? stratCls;
  @JsonKey(name: 'owner')
  final int? owner;
  static const fromJsonFactory = _$PatchedStrategyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PatchedStrategy &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.data, data) ||
                const DeepCollectionEquality().equals(other.data, data)) &&
            (identical(other.stratCls, stratCls) ||
                const DeepCollectionEquality().equals(
                  other.stratCls,
                  stratCls,
                )) &&
            (identical(other.owner, owner) ||
                const DeepCollectionEquality().equals(other.owner, owner)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(data) ^
      const DeepCollectionEquality().hash(stratCls) ^
      const DeepCollectionEquality().hash(owner) ^
      runtimeType.hashCode;
}

extension $PatchedStrategyExtension on PatchedStrategy {
  PatchedStrategy copyWith({
    int? id,
    dynamic data,
    enums.StratClsEnum? stratCls,
    int? owner,
  }) {
    return PatchedStrategy(
      id: id ?? this.id,
      data: data ?? this.data,
      stratCls: stratCls ?? this.stratCls,
      owner: owner ?? this.owner,
    );
  }

  PatchedStrategy copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<dynamic>? data,
    Wrapped<enums.StratClsEnum?>? stratCls,
    Wrapped<int?>? owner,
  }) {
    return PatchedStrategy(
      id: (id != null ? id.value : this.id),
      data: (data != null ? data.value : this.data),
      stratCls: (stratCls != null ? stratCls.value : this.stratCls),
      owner: (owner != null ? owner.value : this.owner),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PatchedUserCreation {
  const PatchedUserCreation({
    this.username,
    this.email,
    this.name,
    this.password,
  });

  factory PatchedUserCreation.fromJson(Map<String, dynamic> json) =>
      _$PatchedUserCreationFromJson(json);

  static const toJsonFactory = _$PatchedUserCreationToJson;
  Map<String, dynamic> toJson() => _$PatchedUserCreationToJson(this);

  @JsonKey(name: 'username')
  final String? username;
  @JsonKey(name: 'email')
  final String? email;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'password')
  final String? password;
  static const fromJsonFactory = _$PatchedUserCreationFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PatchedUserCreation &&
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

extension $PatchedUserCreationExtension on PatchedUserCreation {
  PatchedUserCreation copyWith({
    String? username,
    String? email,
    String? name,
    String? password,
  }) {
    return PatchedUserCreation(
      username: username ?? this.username,
      email: email ?? this.email,
      name: name ?? this.name,
      password: password ?? this.password,
    );
  }

  PatchedUserCreation copyWithWrapped({
    Wrapped<String?>? username,
    Wrapped<String?>? email,
    Wrapped<String?>? name,
    Wrapped<String?>? password,
  }) {
    return PatchedUserCreation(
      username: (username != null ? username.value : this.username),
      email: (email != null ? email.value : this.email),
      name: (name != null ? name.value : this.name),
      password: (password != null ? password.value : this.password),
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
class Strategy {
  const Strategy({this.id, this.data, required this.stratCls, this.owner});

  factory Strategy.fromJson(Map<String, dynamic> json) =>
      _$StrategyFromJson(json);

  static const toJsonFactory = _$StrategyToJson;
  Map<String, dynamic> toJson() => _$StrategyToJson(this);

  @JsonKey(name: 'id')
  final int? id;
  @JsonKey(name: 'data')
  final dynamic data;
  @JsonKey(
    name: 'strat_cls',
    toJson: stratClsEnumToJson,
    fromJson: stratClsEnumFromJson,
  )
  final enums.StratClsEnum stratCls;
  @JsonKey(name: 'owner')
  final int? owner;
  static const fromJsonFactory = _$StrategyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Strategy &&
            (identical(other.id, id) ||
                const DeepCollectionEquality().equals(other.id, id)) &&
            (identical(other.data, data) ||
                const DeepCollectionEquality().equals(other.data, data)) &&
            (identical(other.stratCls, stratCls) ||
                const DeepCollectionEquality().equals(
                  other.stratCls,
                  stratCls,
                )) &&
            (identical(other.owner, owner) ||
                const DeepCollectionEquality().equals(other.owner, owner)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(id) ^
      const DeepCollectionEquality().hash(data) ^
      const DeepCollectionEquality().hash(stratCls) ^
      const DeepCollectionEquality().hash(owner) ^
      runtimeType.hashCode;
}

extension $StrategyExtension on Strategy {
  Strategy copyWith({
    int? id,
    dynamic data,
    enums.StratClsEnum? stratCls,
    int? owner,
  }) {
    return Strategy(
      id: id ?? this.id,
      data: data ?? this.data,
      stratCls: stratCls ?? this.stratCls,
      owner: owner ?? this.owner,
    );
  }

  Strategy copyWithWrapped({
    Wrapped<int?>? id,
    Wrapped<dynamic>? data,
    Wrapped<enums.StratClsEnum>? stratCls,
    Wrapped<int?>? owner,
  }) {
    return Strategy(
      id: (id != null ? id.value : this.id),
      data: (data != null ? data.value : this.data),
      stratCls: (stratCls != null ? stratCls.value : this.stratCls),
      owner: (owner != null ? owner.value : this.owner),
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
  const UserCreation({
    required this.username,
    required this.email,
    this.name,
    required this.password,
  });

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
  @JsonKey(name: 'password')
  final String password;
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

extension $UserCreationExtension on UserCreation {
  UserCreation copyWith({
    String? username,
    String? email,
    String? name,
    String? password,
  }) {
    return UserCreation(
      username: username ?? this.username,
      email: email ?? this.email,
      name: name ?? this.name,
      password: password ?? this.password,
    );
  }

  UserCreation copyWithWrapped({
    Wrapped<String>? username,
    Wrapped<String>? email,
    Wrapped<String?>? name,
    Wrapped<String>? password,
  }) {
    return UserCreation(
      username: (username != null ? username.value : this.username),
      email: (email != null ? email.value : this.email),
      name: (name != null ? name.value : this.name),
      password: (password != null ? password.value : this.password),
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

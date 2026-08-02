// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'openapi.swagger.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CaddyAccessLogResponse _$CaddyAccessLogResponseFromJson(
  Map<String, dynamic> json,
) => CaddyAccessLogResponse(
  configuredPath: json['configured_path'] as String?,
  results:
      (json['results'] as List<dynamic>?)?.map((e) => e as Object).toList() ??
      [],
);

Map<String, dynamic> _$CaddyAccessLogResponseToJson(
  CaddyAccessLogResponse instance,
) => <String, dynamic>{
  'configured_path': instance.configuredPath,
  'results': instance.results,
};

ClientEvent _$ClientEventFromJson(Map<String, dynamic> json) => ClientEvent(
  category: categoryEnumFromJson(json['category']),
  route: json['route'] as String?,
  endpoint: json['endpoint'] as String?,
  requestId: json['request_id'] as String?,
  contractPath: json['contract_path'] as String?,
  expected: json['expected'] as String?,
  actual: json['actual'] as String?,
  appVersion: json['app_version'] as String?,
  gitHash: json['git_hash'] as String?,
  browser: json['browser'] as String?,
  message: json['message'] as String?,
  stack: json['stack'] as String?,
);

Map<String, dynamic> _$ClientEventToJson(ClientEvent instance) =>
    <String, dynamic>{
      'category': categoryEnumToJson(instance.category),
      'route': instance.route,
      'endpoint': instance.endpoint,
      'request_id': instance.requestId,
      'contract_path': instance.contractPath,
      'expected': instance.expected,
      'actual': instance.actual,
      'app_version': instance.appVersion,
      'git_hash': instance.gitHash,
      'browser': instance.browser,
      'message': instance.message,
      'stack': instance.stack,
    };

ClientEventAccepted _$ClientEventAcceptedFromJson(Map<String, dynamic> json) =>
    ClientEventAccepted(status: json['status'] as String);

Map<String, dynamic> _$ClientEventAcceptedToJson(
  ClientEventAccepted instance,
) => <String, dynamic>{'status': instance.status};

DeviceSession _$DeviceSessionFromJson(Map<String, dynamic> json) =>
    DeviceSession(
      publicId: json['public_id'] as String?,
      deviceLabel: json['device_label'] as String?,
      transport: transportEnumNullableFromJson(json['transport']),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      lastUsedAt: json['last_used_at'] == null
          ? null
          : DateTime.parse(json['last_used_at'] as String),
      ip: json['ip'] as String?,
      userAgent: json['user_agent'] as String?,
      current: json['current'] as bool?,
    );

Map<String, dynamic> _$DeviceSessionToJson(DeviceSession instance) =>
    <String, dynamic>{
      'public_id': instance.publicId,
      'device_label': instance.deviceLabel,
      'transport': transportEnumNullableToJson(instance.transport),
      'created_at': instance.createdAt?.toIso8601String(),
      'last_used_at': instance.lastUsedAt?.toIso8601String(),
      'ip': instance.ip,
      'user_agent': instance.userAgent,
      'current': instance.current,
    };

HealthCheckResponse _$HealthCheckResponseFromJson(Map<String, dynamic> json) =>
    HealthCheckResponse(status: json['status'] as String);

Map<String, dynamic> _$HealthCheckResponseToJson(
  HealthCheckResponse instance,
) => <String, dynamic>{'status': instance.status};

Link _$LinkFromJson(Map<String, dynamic> json) => Link(
  id: (json['id'] as num?)?.toInt(),
  name: json['name'] as String,
  url: json['url'] as String,
  user: (json['user'] as num?)?.toInt(),
  strategy: (json['strategy'] as num?)?.toInt(),
  lastScraped: json['last_scraped'] == null
      ? null
      : DateTime.parse(json['last_scraped'] as String),
  scrapeIntervalMinutes: (json['scrape_interval_minutes'] as num?)?.toInt(),
  nextScrapeAt: json['next_scrape_at'] == null
      ? null
      : DateTime.parse(json['next_scrape_at'] as String),
  scrapeDisabled: json['scrape_disabled'] as bool?,
  scrapeFailureCount: (json['scrape_failure_count'] as num?)?.toInt(),
  lastScrapeError: json['last_scrape_error'] as String?,
  comparisonInfo: json['comparison_info'] as String?,
);

Map<String, dynamic> _$LinkToJson(Link instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'url': instance.url,
  'user': instance.user,
  'strategy': instance.strategy,
  'last_scraped': instance.lastScraped?.toIso8601String(),
  'scrape_interval_minutes': instance.scrapeIntervalMinutes,
  'next_scrape_at': instance.nextScrapeAt?.toIso8601String(),
  'scrape_disabled': instance.scrapeDisabled,
  'scrape_failure_count': instance.scrapeFailureCount,
  'last_scrape_error': instance.lastScrapeError,
  'comparison_info': instance.comparisonInfo,
};

LoginRequest _$LoginRequestFromJson(Map<String, dynamic> json) => LoginRequest(
  username: json['username'] as String,
  password: json['password'] as String?,
  transport: transportEnumFromJson(json['transport']),
  deviceLabel: json['device_label'] as String?,
);

Map<String, dynamic> _$LoginRequestToJson(LoginRequest instance) =>
    <String, dynamic>{
      'username': instance.username,
      'password': instance.password,
      'transport': transportEnumToJson(instance.transport),
      'device_label': instance.deviceLabel,
    };

LoginResponse _$LoginResponseFromJson(Map<String, dynamic> json) =>
    LoginResponse(
      transport: transportEnumFromJson(json['transport']),
      publicId: json['public_id'] as String,
      token: json['token'] as String?,
    );

Map<String, dynamic> _$LoginResponseToJson(LoginResponse instance) =>
    <String, dynamic>{
      'transport': transportEnumToJson(instance.transport),
      'public_id': instance.publicId,
      'token': instance.token,
    };

Notification _$NotificationFromJson(Map<String, dynamic> json) => Notification(
  id: (json['id'] as num?)?.toInt(),
  update: json['update'] == null
      ? null
      : Update.fromJson(json['update'] as Map<String, dynamic>),
  status: statusEnumNullableFromJson(json['status']),
  readAt: json['read_at'] == null
      ? null
      : DateTime.parse(json['read_at'] as String),
);

Map<String, dynamic> _$NotificationToJson(Notification instance) =>
    <String, dynamic>{
      'id': instance.id,
      'update': instance.update?.toJson(),
      'status': statusEnumNullableToJson(instance.status),
      'read_at': instance.readAt?.toIso8601String(),
    };

PaginatedLinkList _$PaginatedLinkListFromJson(Map<String, dynamic> json) =>
    PaginatedLinkList(
      count: (json['count'] as num).toInt(),
      next: json['next'] as String?,
      previous: json['previous'] as String?,
      results:
          (json['results'] as List<dynamic>?)
              ?.map((e) => Link.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$PaginatedLinkListToJson(PaginatedLinkList instance) =>
    <String, dynamic>{
      'count': instance.count,
      'next': instance.next,
      'previous': instance.previous,
      'results': instance.results.map((e) => e.toJson()).toList(),
    };

PaginatedNotificationList _$PaginatedNotificationListFromJson(
  Map<String, dynamic> json,
) => PaginatedNotificationList(
  count: (json['count'] as num).toInt(),
  next: json['next'] as String?,
  previous: json['previous'] as String?,
  results:
      (json['results'] as List<dynamic>?)
          ?.map((e) => Notification.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$PaginatedNotificationListToJson(
  PaginatedNotificationList instance,
) => <String, dynamic>{
  'count': instance.count,
  'next': instance.next,
  'previous': instance.previous,
  'results': instance.results.map((e) => e.toJson()).toList(),
};

PaginatedSystemEventList _$PaginatedSystemEventListFromJson(
  Map<String, dynamic> json,
) => PaginatedSystemEventList(
  count: (json['count'] as num).toInt(),
  next: json['next'] as String?,
  previous: json['previous'] as String?,
  results:
      (json['results'] as List<dynamic>?)
          ?.map((e) => SystemEvent.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$PaginatedSystemEventListToJson(
  PaginatedSystemEventList instance,
) => <String, dynamic>{
  'count': instance.count,
  'next': instance.next,
  'previous': instance.previous,
  'results': instance.results.map((e) => e.toJson()).toList(),
};

PasswordResetConfirm _$PasswordResetConfirmFromJson(
  Map<String, dynamic> json,
) => PasswordResetConfirm(
  email: json['email'] as String,
  code: json['code'] as String,
  newPassword: json['new_password'] as String,
);

Map<String, dynamic> _$PasswordResetConfirmToJson(
  PasswordResetConfirm instance,
) => <String, dynamic>{
  'email': instance.email,
  'code': instance.code,
  'new_password': instance.newPassword,
};

PasswordResetRequest _$PasswordResetRequestFromJson(
  Map<String, dynamic> json,
) => PasswordResetRequest(email: json['email'] as String);

Map<String, dynamic> _$PasswordResetRequestToJson(
  PasswordResetRequest instance,
) => <String, dynamic>{'email': instance.email};

PatchedLink _$PatchedLinkFromJson(Map<String, dynamic> json) => PatchedLink(
  id: (json['id'] as num?)?.toInt(),
  name: json['name'] as String?,
  url: json['url'] as String?,
  user: (json['user'] as num?)?.toInt(),
  strategy: (json['strategy'] as num?)?.toInt(),
  lastScraped: json['last_scraped'] == null
      ? null
      : DateTime.parse(json['last_scraped'] as String),
  scrapeIntervalMinutes: (json['scrape_interval_minutes'] as num?)?.toInt(),
  nextScrapeAt: json['next_scrape_at'] == null
      ? null
      : DateTime.parse(json['next_scrape_at'] as String),
  scrapeDisabled: json['scrape_disabled'] as bool?,
  scrapeFailureCount: (json['scrape_failure_count'] as num?)?.toInt(),
  lastScrapeError: json['last_scrape_error'] as String?,
  comparisonInfo: json['comparison_info'] as String?,
);

Map<String, dynamic> _$PatchedLinkToJson(PatchedLink instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'url': instance.url,
      'user': instance.user,
      'strategy': instance.strategy,
      'last_scraped': instance.lastScraped?.toIso8601String(),
      'scrape_interval_minutes': instance.scrapeIntervalMinutes,
      'next_scrape_at': instance.nextScrapeAt?.toIso8601String(),
      'scrape_disabled': instance.scrapeDisabled,
      'scrape_failure_count': instance.scrapeFailureCount,
      'last_scrape_error': instance.lastScrapeError,
      'comparison_info': instance.comparisonInfo,
    };

PatchedNotification _$PatchedNotificationFromJson(Map<String, dynamic> json) =>
    PatchedNotification(
      id: (json['id'] as num?)?.toInt(),
      update: json['update'] == null
          ? null
          : Update.fromJson(json['update'] as Map<String, dynamic>),
      status: statusEnumNullableFromJson(json['status']),
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String),
    );

Map<String, dynamic> _$PatchedNotificationToJson(
  PatchedNotification instance,
) => <String, dynamic>{
  'id': instance.id,
  'update': instance.update?.toJson(),
  'status': statusEnumNullableToJson(instance.status),
  'read_at': instance.readAt?.toIso8601String(),
};

PatchedStrategy _$PatchedStrategyFromJson(Map<String, dynamic> json) =>
    PatchedStrategy(
      id: (json['id'] as num?)?.toInt(),
      data: json['data'],
      stratCls: stratClsEnumNullableFromJson(json['strat_cls']),
    );

Map<String, dynamic> _$PatchedStrategyToJson(PatchedStrategy instance) =>
    <String, dynamic>{
      'id': instance.id,
      'data': instance.data,
      'strat_cls': stratClsEnumNullableToJson(instance.stratCls),
    };

PatchedUserCreation _$PatchedUserCreationFromJson(Map<String, dynamic> json) =>
    PatchedUserCreation(
      username: json['username'] as String?,
      email: json['email'] as String?,
      name: json['name'] as String?,
      password: json['password'] as String?,
    );

Map<String, dynamic> _$PatchedUserCreationToJson(
  PatchedUserCreation instance,
) => <String, dynamic>{
  'username': instance.username,
  'email': instance.email,
  'name': instance.name,
  'password': instance.password,
};

SessionRevokeResponse _$SessionRevokeResponseFromJson(
  Map<String, dynamic> json,
) => SessionRevokeResponse(
  status: json['status'] as String,
  revoked: (json['revoked'] as num).toInt(),
);

Map<String, dynamic> _$SessionRevokeResponseToJson(
  SessionRevokeResponse instance,
) => <String, dynamic>{'status': instance.status, 'revoked': instance.revoked};

StatusCheckResponse _$StatusCheckResponseFromJson(Map<String, dynamic> json) =>
    StatusCheckResponse(
      status: json['status'] as String,
      db: json['db'] as String,
      version: json['version'] as String,
      commit: json['commit'] as String,
      environment: json['environment'] as String,
    );

Map<String, dynamic> _$StatusCheckResponseToJson(
  StatusCheckResponse instance,
) => <String, dynamic>{
  'status': instance.status,
  'db': instance.db,
  'version': instance.version,
  'commit': instance.commit,
  'environment': instance.environment,
};

StatusResponse _$StatusResponseFromJson(Map<String, dynamic> json) =>
    StatusResponse(status: json['status'] as String);

Map<String, dynamic> _$StatusResponseToJson(StatusResponse instance) =>
    <String, dynamic>{'status': instance.status};

Strategy _$StrategyFromJson(Map<String, dynamic> json) => Strategy(
  id: (json['id'] as num?)?.toInt(),
  data: json['data'],
  stratCls: stratClsEnumFromJson(json['strat_cls']),
);

Map<String, dynamic> _$StrategyToJson(Strategy instance) => <String, dynamic>{
  'id': instance.id,
  'data': instance.data,
  'strat_cls': stratClsEnumToJson(instance.stratCls),
};

SystemEvent _$SystemEventFromJson(Map<String, dynamic> json) => SystemEvent(
  id: (json['id'] as num?)?.toInt(),
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  level: levelEnumNullableFromJson(json['level']),
  source: json['source'] as String?,
  kind: json['kind'] as String?,
  message: json['message'] as String?,
  details: json['details'],
);

Map<String, dynamic> _$SystemEventToJson(SystemEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'created_at': instance.createdAt?.toIso8601String(),
      'level': levelEnumNullableToJson(instance.level),
      'source': instance.source,
      'kind': instance.kind,
      'message': instance.message,
      'details': instance.details,
    };

TriggerScrapeLinkResult _$TriggerScrapeLinkResultFromJson(
  Map<String, dynamic> json,
) => TriggerScrapeLinkResult(
  status: json['status'] as String,
  updatesFound: (json['updates_found'] as num?)?.toInt(),
  message: json['message'] as String?,
);

Map<String, dynamic> _$TriggerScrapeLinkResultToJson(
  TriggerScrapeLinkResult instance,
) => <String, dynamic>{
  'status': instance.status,
  'updates_found': instance.updatesFound,
  'message': instance.message,
};

TriggerScrapeRequest _$TriggerScrapeRequestFromJson(
  Map<String, dynamic> json,
) => TriggerScrapeRequest(linkId: (json['link_id'] as num?)?.toInt());

Map<String, dynamic> _$TriggerScrapeRequestToJson(
  TriggerScrapeRequest instance,
) => <String, dynamic>{'link_id': instance.linkId};

TriggerScrapeResponse _$TriggerScrapeResponseFromJson(
  Map<String, dynamic> json,
) => TriggerScrapeResponse(
  status: json['status'] as String,
  updatesFound: (json['updates_found'] as num?)?.toInt(),
  message: json['message'] as String?,
  results: json['results'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$TriggerScrapeResponseToJson(
  TriggerScrapeResponse instance,
) => <String, dynamic>{
  'status': instance.status,
  'updates_found': instance.updatesFound,
  'message': instance.message,
  'results': instance.results,
};

Update _$UpdateFromJson(Map<String, dynamic> json) => Update(
  id: (json['id'] as num?)?.toInt(),
  link: (json['link'] as num?)?.toInt(),
  title: json['title'] as String?,
  description: json['description'] as String?,
  itemUrl: json['item_url'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$UpdateToJson(Update instance) => <String, dynamic>{
  'id': instance.id,
  'link': instance.link,
  'title': instance.title,
  'description': instance.description,
  'item_url': instance.itemUrl,
  'created_at': instance.createdAt?.toIso8601String(),
};

UserCreation _$UserCreationFromJson(Map<String, dynamic> json) => UserCreation(
  username: json['username'] as String,
  email: json['email'] as String,
  name: json['name'] as String?,
  password: json['password'] as String,
);

Map<String, dynamic> _$UserCreationToJson(UserCreation instance) =>
    <String, dynamic>{
      'username': instance.username,
      'email': instance.email,
      'name': instance.name,
      'password': instance.password,
    };

UserMinimalRead _$UserMinimalReadFromJson(Map<String, dynamic> json) =>
    UserMinimalRead(
      username: json['username'] as String,
      dateCreated: json['date_created'] == null
          ? null
          : DateTime.parse(json['date_created'] as String),
    );

Map<String, dynamic> _$UserMinimalReadToJson(UserMinimalRead instance) =>
    <String, dynamic>{
      'username': instance.username,
      'date_created': instance.dateCreated?.toIso8601String(),
    };

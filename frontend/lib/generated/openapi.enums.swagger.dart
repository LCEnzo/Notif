// coverage:ignore-file
// ignore_for_file: type=lint

import 'package:json_annotation/json_annotation.dart';
import 'package:collection/collection.dart';

enum CategoryEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('network_unavailable')
  networkUnavailable('network_unavailable'),
  @JsonValue('timeout')
  timeout('timeout'),
  @JsonValue('unauthorized')
  unauthorized('unauthorized'),
  @JsonValue('forbidden')
  forbidden('forbidden'),
  @JsonValue('validation_failed')
  validationFailed('validation_failed'),
  @JsonValue('contract_violation')
  contractViolation('contract_violation'),
  @JsonValue('corrupt_local_state')
  corruptLocalState('corrupt_local_state'),
  @JsonValue('source_blocked_degraded')
  sourceBlockedDegraded('source_blocked_degraded'),
  @JsonValue('server_error')
  serverError('server_error'),
  @JsonValue('unexpected_failure')
  unexpectedFailure('unexpected_failure');

  final String? value;

  const CategoryEnum(this.value);
}

enum LevelEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('debug')
  debug('debug'),
  @JsonValue('info')
  info('info'),
  @JsonValue('warning')
  warning('warning'),
  @JsonValue('error')
  error('error'),
  @JsonValue('critical')
  critical('critical');

  final String? value;

  const LevelEnum(this.value);
}

enum StatusEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('unread')
  unread('unread'),
  @JsonValue('read')
  read('read'),
  @JsonValue('dismissed')
  dismissed('dismissed');

  final String? value;

  const StatusEnum(this.value);
}

enum StratClsEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('GeneralSelectorStrategy')
  generalselectorstrategy('GeneralSelectorStrategy'),
  @JsonValue('SBSVThreadmarksStrategy')
  sbsvthreadmarksstrategy('SBSVThreadmarksStrategy'),
  @JsonValue('QQAlertsStrategy')
  qqalertsstrategy('QQAlertsStrategy'),
  @JsonValue('KemonoFavouritesStrategy')
  kemonofavouritesstrategy('KemonoFavouritesStrategy'),
  @JsonValue('FeedStrategy')
  feedstrategy('FeedStrategy');

  final String? value;

  const StratClsEnum(this.value);
}

enum TransportEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('cookie')
  cookie('cookie'),
  @JsonValue('bearer')
  bearer('bearer');

  final String? value;

  const TransportEnum(this.value);
}

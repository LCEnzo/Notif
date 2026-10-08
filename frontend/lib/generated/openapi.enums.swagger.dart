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

enum HealthAggregateMetricEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('steps_count_total')
  stepsCountTotal('steps_count_total'),
  @JsonValue('sleep_duration_total')
  sleepDurationTotal('sleep_duration_total');

  final String? value;

  const HealthAggregateMetricEnum(this.value);
}

enum HealthDeviceTypeEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('unknown')
  unknown('unknown'),
  @JsonValue('watch')
  watch('watch'),
  @JsonValue('phone')
  phone('phone'),
  @JsonValue('scale')
  scale('scale'),
  @JsonValue('ring')
  ring('ring'),
  @JsonValue('head_mounted')
  headMounted('head_mounted'),
  @JsonValue('fitness_band')
  fitnessBand('fitness_band'),
  @JsonValue('chest_strap')
  chestStrap('chest_strap'),
  @JsonValue('smart_display')
  smartDisplay('smart_display');

  final String? value;

  const HealthDeviceTypeEnum(this.value);
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

enum RecordingMethodEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('unknown')
  unknown('unknown'),
  @JsonValue('actively_recorded')
  activelyRecorded('actively_recorded'),
  @JsonValue('automatically_recorded')
  automaticallyRecorded('automatically_recorded'),
  @JsonValue('manual_entry')
  manualEntry('manual_entry');

  final String? value;

  const RecordingMethodEnum(this.value);
}

enum SleepStageEnum {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('unknown')
  unknown('unknown'),
  @JsonValue('awake')
  awake('awake'),
  @JsonValue('sleeping')
  sleeping('sleeping'),
  @JsonValue('out_of_bed')
  outOfBed('out_of_bed'),
  @JsonValue('light')
  light('light'),
  @JsonValue('deep')
  deep('deep'),
  @JsonValue('rem')
  rem('rem'),
  @JsonValue('awake_in_bed')
  awakeInBed('awake_in_bed');

  final String? value;

  const SleepStageEnum(this.value);
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

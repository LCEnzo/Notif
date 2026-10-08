/// Read-only access to Android Health Connect for Notif.
///
/// The Kotlin side maps every Health Connect integer constant to a name, and
/// every failure to an [HcErrorCode]; nothing here returns null for "failed".
library;

export 'src/bridge.dart';
export 'src/errors.dart';
export 'src/models.dart';

import 'package:notif/services/persistence.dart';

/// Stand-in for the platform keystore. Keeps secure-store behaviour testable
/// without a plugin, while still routing through the same interface the app
/// uses in production.
class InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

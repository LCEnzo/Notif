import 'package:web/web.dart' as web;

/// Parse one cookie out of `document.cookie`.
///
/// `document.cookie` is a single `name=value; name=value` string with no API
/// for lookup, so parsing it by hand is the only option. Only non-HttpOnly
/// cookies appear here, which is exactly the point: `csrftoken` shows up,
/// `notif_session` never does.
String? readBrowserCookieImpl(String name) {
  final jar = web.document.cookie;
  if (jar.isEmpty) {
    return null;
  }

  for (final entry in jar.split(';')) {
    final separator = entry.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    if (entry.substring(0, separator).trim() != name) {
      continue;
    }
    final value = entry.substring(separator + 1).trim();
    return value.isEmpty ? null : Uri.decodeComponent(value);
  }

  return null;
}

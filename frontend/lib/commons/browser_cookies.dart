import 'package:notif/commons/browser_cookies_stub.dart'
    if (dart.library.js_interop) 'package:notif/commons/browser_cookies_web.dart';

/// The value of a readable (non-HttpOnly) cookie, or null off the web.
///
/// Only ever used for `csrftoken`: the session cookie is HttpOnly by design and
/// is deliberately unreadable from here.
String? readBrowserCookie(String name) => readBrowserCookieImpl(name);

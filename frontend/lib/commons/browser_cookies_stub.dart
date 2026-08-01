/// Off the web there is no cookie jar the app can read; native auth is a bearer
/// header held in the keystore.
String? readBrowserCookieImpl(String name) => null;

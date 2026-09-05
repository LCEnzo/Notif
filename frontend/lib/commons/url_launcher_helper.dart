import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Schemes the app will hand to the OS launcher.
///
/// Notification `item_url`s are controlled by scraped sites, so they can
/// carry arbitrary schemes (`intent://`, `tel:`, `javascript:`, custom app
/// schemes). Launching those without a user-visible confirmation can fire
/// deep links into other apps or be abused as phishing, so only plain web
/// and mail links are ever launched.
const Set<String> _uriSchemeWhitelist = {'http', 'https', 'mailto'};

Future<void> openUriSafely(
  BuildContext context,
  Uri uri, {
  bool newTab = false,
}) async {
  if (!_uriSchemeWhitelist.contains(uri.scheme.toLowerCase())) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cannot open ${uri.scheme}: links from here'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final bool launched;
  try {
    launched = await launchUrl(
      uri,
      webOnlyWindowName: newTab ? '_blank' : null,
    );
  } on Exception catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Launcher error: $e'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  if (launched) return;
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Could not open $uri'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

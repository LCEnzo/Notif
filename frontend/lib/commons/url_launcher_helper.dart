import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openUriSafely(
  BuildContext context,
  Uri uri, {
  bool newTab = false,
}) async {
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

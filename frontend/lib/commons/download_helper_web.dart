import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void saveBytesAsFileImpl({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final blob = web.Blob(
    <JSAny>[data.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..rel = 'noopener';
    anchor.click();
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

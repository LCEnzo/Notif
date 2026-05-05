import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';

void saveBytesAsFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) {
  saveBytesAsFileImpl(bytes: bytes, filename: filename, mimeType: mimeType);
}

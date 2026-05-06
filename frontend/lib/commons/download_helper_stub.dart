void saveBytesAsFileImpl({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) {
  throw UnsupportedError('File downloads are only implemented for web builds.');
}

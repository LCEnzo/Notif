class DownloadUnsupportedException implements Exception {
  const DownloadUnsupportedException(this.message);

  final String message;

  @override
  String toString() => message;
}

void saveBytesAsFileImpl({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) {
  throw const DownloadUnsupportedException(
    'File downloads are only implemented for web builds.',
  );
}

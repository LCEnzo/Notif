import 'dart:convert';

import 'package:notif/services/health/ingest_items.dart';

/// One request body, ready to send as-is.
class IngestBatch {
  const IngestBatch({
    required this.body,
    required this.items,
    required this.byteLength,
    required this.itemCost,
  });

  final String body;
  final List<IngestItem> items;

  /// UTF-8 length of [body].
  final int byteLength;

  /// What the batch counts against the item cap: records, deletions and
  /// window hours.
  final int itemCost;
}

class PackedBatches {
  const PackedBatches({required this.batches, required this.oversized});

  final List<IngestBatch> batches;

  /// Items that cannot fit even in a batch of their own; never sent.
  final List<IngestItem> oversized;
}

/// Packs [items], in order, into as few bodies as fit under both caps. Every
/// body carries [coverageStartMs]. The byte count is exact: bodies are built
/// from the items' own encodings, and each is checked against its UTF-8
/// length before it is returned.
PackedBatches packBatches(
  Iterable<IngestItem> items, {
  required int? coverageStartMs,
  int maxItems = IngestLimits.maxItems,
  int maxBytes = IngestLimits.maxBytes,
}) {
  final prefix = '{"coverage_start_ms":${jsonEncode(coverageStartMs)}';
  // Both ASCII, so their length is their byte count.
  final emptyBytes = prefix.length + '}'.length;
  int listOverhead(IngestList list) => ',"${list.key}":['.length + ']'.length;

  final batches = <IngestBatch>[];
  final oversized = <IngestItem>[];
  var open = <IngestList, List<IngestItem>>{};
  var openBytes = emptyBytes;
  var openCost = 0;

  void flush() {
    if (openCost == 0 && open.isEmpty) return;
    final body = StringBuffer(prefix);
    final ordered = <IngestItem>[];
    for (final list in IngestList.values) {
      final entries = open[list];
      if (entries == null || entries.isEmpty) continue;
      body
        ..write(',"${list.key}":[')
        ..writeAll(entries.map((item) => item.encoded), ',')
        ..write(']');
      ordered.addAll(entries);
    }
    body.write('}');
    final text = body.toString();
    final actual = utf8.encode(text).length;
    if (actual != openBytes) {
      throw StateError(
        'health batch size miscounted: counted $openBytes, encoded $actual',
      );
    }
    batches.add(
      IngestBatch(
        body: text,
        items: ordered,
        byteLength: actual,
        itemCost: openCost,
      ),
    );
    open = {};
    openBytes = emptyBytes;
    openCost = 0;
  }

  for (final item in items) {
    final alone = emptyBytes + listOverhead(item.list) + item.encodedBytes;
    if (item.cost > maxItems || alone > maxBytes) {
      oversized.add(item);
      continue;
    }
    int added() => (open[item.list]?.isNotEmpty ?? false)
        ? ','.length + item.encodedBytes
        : listOverhead(item.list) + item.encodedBytes;
    if (openCost + item.cost > maxItems || openBytes + added() > maxBytes) {
      flush();
    }
    openBytes += added();
    openCost += item.cost;
    (open[item.list] ??= []).add(item);
  }
  flush();
  return PackedBatches(batches: batches, oversized: oversized);
}

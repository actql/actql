///|
fn github_read_collection_units(
  value : @shape.CollectionConstructionExtent,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
// Both original native stringify calls precede the HTTP byte check. The
// installed Source always uses all states, no labels and no since; its only
// variable Text inputs are the admitted node ID (256) and cursor (1024).
// The fixed forest below co-counts every original request alternative's keys,
// first/number spellings, nulls and empty labels. Query quantities come from
// the SAME Catalog literals/fragments, never a second GraphQL document table.
fn github_read_request_inventory() -> @execution.PreparationRepresentationUnits? {
  let fixed = "{\"query\":\"\",\"variables\":{\"id\":\"\",\"first\":100,\"after\":\"\",\"number\":2147483647,\"states\":null,\"labels\":[],\"since\":null}}"
  let inner = fixed.length() +
    @catalog.source_read_query_units() +
    6 * (256 + 1024)
  let outer = "{\"body\":\"\"}".length() + 6 * inner
  // Each forest has <=32 nodes/depth4, including the exported body wrapper.
  // UTF8 at most triples a UTF16 bound; the writer owns old/new builders too.
  guard @encode.text_writer_construction_inventory(3 * inner, 32, 4)
    is Some(request) &&
    @encode.text_writer_construction_inventory(3 * outer, 32, 4)
    is Some(exported) else {
    return None
  }
  Some({
    record_headers: request.record_headers + exported.record_headers,
    reference_slots: request.reference_slots + exported.reference_slots,
    scalar_words: request.scalar_words + exported.scalar_words,
    owned_utf16_units: request.owned_utf16_units +
    exported.owned_utf16_units +
    inner.to_int64() +
    outer.to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
// These are the existing installed limits in their original units, followed
// by the largest ACTUAL owned body extent. This quantity does not parse,
// construct a request, change any rejection bound or issue capacity. The
// SAME RowRun must grow to the returned quantity before every projection.
#export_name("githubSourceReadConstructionCapacity")
pub fn github_source_read_construction_capacity(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  pages : Int,
  max_subjects : Int,
  response_bytes : Int,
  header_bytes : Int,
) -> @execution.ExecutionCapacity? {
  if max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_rows < 1 ||
    pages < 1 ||
    max_subjects < 1 ||
    max_depth > 2147483643 ||
    response_bytes < 0 ||
    response_bytes > max_bytes || header_bytes < 1 || header_bytes > 2147483647 / 12 {
    return None
  }
  let bytes = Int::max(1, response_bytes)
  let nodes = Int::min(max_nodes, bytes)
  guard @execution.checked_preparation_add_product(
      0L,
      pages.to_int64(),
      bytes.to_int64(),
    )
    is Some(total_bytes) &&
    @execution.checked_preparation_add_product(
      0L,
      pages.to_int64(),
      nodes.to_int64(),
    )
    is Some(total_nodes) &&
    total_bytes <= (2147483647L - 1024L) / 6L else {
    return None
  }
  // The global JS row/subject checks happen AFTER a current native page is
  // constructed. Retained accepted rows and one offending full page coexist.
  let rows = Int64::min(2L * max_rows.to_int64(), total_bytes)
  let subjects = Int64::min(2L * max_subjects.to_int64(), total_bytes)
  // Key/value strings are not duplicated by native typed getters. Their
  // backing survives the parser through the row/subject/continuation owner.
  // Co-count the Issue+PullRequest row alternatives:16H39R21W per row includes
  // their nine Some carriers and two original continuation+progress records.
  // Comment rows are smaller; original subjects add1H4R1W each.
  guard @shape.collection_construction_extent({
      records: 16L * rows + subjects + 10L * pages.to_int64(),
      record_references: 39L * rows + 4L * subjects + 32L * pages.to_int64(),
      record_words: 21L * rows + subjects + 24L * pages.to_int64(),
      // Native labels/assignees, their original pending cursor histories,
      // page rows/progress/subjects and JS accumulated row/page arrays.
      reference_arrays: 4L * rows + 5L * pages.to_int64() + 8L,
      reference_items: total_nodes +
      2L * rows * pages.to_int64() +
      4L * rows +
      2L * subjects +
      6L * pages.to_int64(),
      scalar_arrays: 1L,
      scalar_items: rows,
      maps: 2L,
      map_entries: pages.to_int64(),
    })
    is Some(typed) &&
    github_read_request_inventory() is Some(request) else {
    return None
  }
  // Source parser and indexed admission of ONE actual current response.
  // Completed page/failed-prefix material remains separately retained above;
  // a second response decoder never runs concurrently inside this Reader.
  guard @source.json_construction_extent(
      bytes,
      nodes,
      max_depth,
      normalize_keys=true,
    )
    is Some(parser) &&
    @decode.admission_construction_inventory(
      nodes,
      nodes,
      nodes,
      nodes,
      Int::min(nodes, max_depth),
    )
    is Some(index) else {
    return None
  }
  // A finished native page borrows its row Strings, then emits JSON before
  // Host JSON.parse and consumePage's JSON.stringify/Source parse. The whole
  // accumulated original response payload bounds text, including nested-page
  // strings. Fixed row keys/decimal identities fit512 units per row;6 bounds
  // JSON escaping without assuming ASCII. This is a constructor bound BEFORE
  // the unchanged later maxRowsWireBytes refusal, never a substituted cap.
  // Rate-limit/error JSON also exports the original declared header values.
  // Their SAME physical HTTPS Owner supplies header_bytes before any call;
  // an empty body cannot stand in for that independently bounded Text input.
  guard @execution.checked_preparation_add_product(
      1024L + 512L * rows + 6L * header_bytes.to_int64(),
      6L,
      total_bytes,
    )
    is Some(wire) &&
    wire <= 2147483647L &&
    @execution.checked_preparation_add_product(
      32L + 64L * rows,
      4L,
      total_nodes,
    )
    is Some(output_nodes) &&
    output_nodes <= 2147483647L else {
    return None
  }
  guard @encode.text_writer_construction_inventory(
      wire.to_int(),
      output_nodes.to_int(),
      max_depth + 4,
    )
    is Some(writer) &&
    @source.json_construction_extent(
      wire.to_int(),
      output_nodes.to_int(),
      max_depth + 4,
      normalize_keys=true,
    )
    is Some(output) else {
    return None
  }
  // The retained native state/prefix never depends on codec.close as physical
  // ACK. Responses themselves belong to the shared native Reader inventory.
  // Original request/export Strings can remain attached to every response.
  guard @execution.compose_preparation_representation([
      github_read_collection_units(typed),
      {
        record_headers: 2L * total_nodes + 4L * pages.to_int64(),
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: total_bytes + pages.to_int64() * header_bytes.to_int64() +
        pages.to_int64() * request.owned_utf16_units +
        2L * pages.to_int64() * 1024L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      request,
      {
        record_headers: parser.record_headers +
        index.indexed.record_headers +
        index.keys.record_headers +
        index.ancestry.record_headers +
        index.controls.record_headers,
        reference_slots: parser.reference_slots +
        index.indexed.reference_slots +
        index.keys.reference_slots +
        index.ancestry.reference_slots +
        index.controls.reference_slots,
        scalar_words: parser.scalar_words +
        index.indexed.scalar_words +
        index.keys.scalar_words +
        index.ancestry.scalar_words +
        index.controls.scalar_words,
        owned_utf16_units: parser.owned_utf16_units + bytes.to_int64(),
        owned_wire_bytes: 0L,
      },
      {
        // Native writer + original Host stringify, with their returned wire
        // and JS parsed tree simultaneously held before consumePage returns.
        // The Source constructor also overbounds that plain JSON tree forest.
        record_headers: 2L * writer.record_headers + 2L * output.record_headers,
        reference_slots: 2L * writer.reference_slots +
        2L * output.reference_slots,
        scalar_words: 2L * writer.scalar_words + 2L * output.scalar_words,
        owned_utf16_units: 2L * writer.owned_utf16_units +
        2L * output.owned_utf16_units +
        2L * wire,
        owned_wire_bytes: wire,
      },
    ])
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

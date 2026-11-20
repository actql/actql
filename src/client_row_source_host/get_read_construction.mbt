///|
fn get_read_limits_valid(limits : RowSourceGetReadLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_path_bytes > 0 &&
  limits.max_query_pairs >= 0 &&
  limits.max_query_value_units > 0 &&
  limits.max_header_name_bytes > 0 &&
  limits.max_header_value_bytes > 0
}

///|
/// Original preserving parser/raw copy/index plus closed-shape projections.
/// The input String stays with its existing Source declaration holder. The
/// Host's UTF8 input Bytes and Core's independent original copy coexist here.
/// Quantity DATA must be reserved by that SAME Source initializer BEFORE
/// encoding/admission; this function issues no reservation or read permission.
pub fn row_source_get_read_construction_inventory(
  limits : RowSourceGetReadLimits,
) -> @execution.PreparationRepresentationUnits? {
  guard get_read_limits_valid(limits) &&
    relation_document_raw_construction_inventory({
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_rows: 0,
    })
    is Some(parsed) &&
    @decode.closed_object_field_construction_extent(Some(5), 5, 0L)
    is Some(root) &&
    @decode.closed_object_field_construction_extent(Some(2), 2, 1L)
    is Some(nested) &&
    // At most one later wrong-kind/key/scalar read can fail. Successful
    // root/page/header views above coexist with that bounded failed prefix.
    // Allowed fields are never substituted for an invalid supplied width.
    @decode.closed_object_field_construction_extent(
      Some(limits.max_nodes),
      5,
      limits.max_depth.to_int64(),
    )
    is Some(refusal) &&
    @decode.issue_construction_extent(limits.max_depth) is Some(issue) &&
    @shape.collection_construction_extent({
      records: limits.max_query_pairs.to_int64(),
      record_references: 2L * limits.max_query_pairs.to_int64(),
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: limits.max_query_pairs.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(query) else {
    return None
  }
  let q = limits.max_query_pairs.to_int64()
  let lookups = 9L + 3L * q
  let texts = 5L + 2L * q
  // Each lookup/element_at: original get Some(Int), map closure, copied
  // Cursor(tree/usage/preparation borrowed), returned Some(Cursor):4H5R4W.
  // text returns Ok(String) borrowing parser storage. array_length and
  // unicode_scalar_count contribute bounded scalar Some, not per-character
  // containers. All character scans use direct original UTF16 indexing.
  let decoder_reads : @execution.PreparationRepresentationUnits = {
    record_headers: 4L * lookups + texts + (q + 1L) + (q + 1L) + 2L,
    reference_slots: 5L * lookups + texts,
    scalar_words: 4L * lookups + texts + 2L * (q + 1L) + 2L * (q + 1L) + 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let utf8 = @scalar.utf8_length_admission_construction_units()
  @execution.compose_preparation_representation([
    parsed,
    relation_construction_collection_units(root),
    relation_construction_collection_units(nested),
    relation_construction_collection_units(nested),
    relation_construction_collection_units(refusal),
    relation_construction_collection_units(issue),
    relation_construction_collection_units(query),
    decoder_reads,
    // Bridge limits record+Some:2H1R8W; retained Read:1H9R8W (keep
    // its original bound words alongside the incoming bridge/call frame).
    // Cursor Some:1H1R; optional page/header tuples+Some:4H5R1W.
    // Success and failed stop/Err controls coexist in the full constructor
    // allowance:3H3R2W. Metadata Tuple5+Ok:2H2R4W; its path borrows
    // the parser and the other fields are scalar DATA. Do not exchange
    // reference slots for apparently spare scalar words in this inventory.
    {
      record_headers: 13L,
      reference_slots: 21L,
      scalar_words: 23L,
      owned_utf16_units: 0L,
      owned_wire_bytes: limits.max_bytes.to_int64(),
    },
    {
      record_headers: 3L * utf8.0,
      reference_slots: 3L * utf8.1,
      scalar_words: 3L * utf8.2,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// SAME checked read -> page -> detached public Tuple4. Both sets of vectors
/// and intermediate growth remain live in this peak; no GC credit or new
/// cursor allowance is inferred. Strings borrow their original read/progress
/// holder, except the bounded positive Int page-size decimal (at most10units).
/// Host target encoding/copies remain its separate existing domain recipe.
pub fn row_source_get_page_construction_inventory(
  read : RowSourceGetRead,
) -> @execution.PreparationRepresentationUnits? {
  if !physical_equal(read.origin, projected_json_page_origin) {
    return None
  }
  let q = read.query.length().to_int64() +
    (if read.page_size is Some(_) { 1L } else { 0L }) +
    (if read.cursor_parameter is Some(_) { 1L } else { 0L })
  let headers = 1L + (if read.version_header is Some(_) { 1L } else { 0L })
  guard q <= read.limits.max_query_pairs.to_int64() &&
    @shape.collection_construction_extent({
      // Two preserved scalar-count checks of a present opaque cursor add
      // two scalar Some records4W; no cursor String is copied or normalized.
      records: 12L,
      record_references: 11L,
      record_words: 9L,
      // Two outer query/header arrays before AND after the Tuple4 copy.
      // Each pair is its own two-reference Array, also copied once.
      reference_arrays: 4L + 2L * (q + headers),
      reference_items: 6L * (q + headers),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(vectors) else {
    return None
  }
  @execution.compose_preparation_representation([
    relation_construction_collection_units(vectors),
    {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: if read.page_size is Some(_) {
        10L
      } else {
        0L
      },
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// Existing shared byte Owner only. Failed/live constructors retain this full
/// logical peak; no successful-return/GC observation reduces it here.
pub fn row_source_get_read_construction_capacity(
  limits : RowSourceGetReadLimits,
) -> @execution.ExecutionCapacity? {
  guard row_source_get_read_construction_inventory(limits) is Some(units) &&
    @execution.preparation_representation_cost(units) is Some(bytes) else {
    return None
  }
  @execution.execution_capacity(bytes, bytes)
}

///|
/// This is the same admitted read's complete Core page/frame quantity. The
/// caller must compose it with the still-live read and Host transport recipe
/// on their SAME reservation; returning DATA acknowledges no cleanup.
pub fn row_source_get_page_construction_capacity(
  read : RowSourceGetRead,
) -> @execution.ExecutionCapacity? {
  guard row_source_get_page_construction_inventory(read) is Some(units) &&
    @execution.preparation_representation_cost(units) is Some(bytes) else {
    return None
  }
  @execution.execution_capacity(bytes, bytes)
}

///|
/// The existing Reader enters one request at a time. Its Host-only transport
/// construction overlaps the largest retained/execution page/frame demand,
/// while every parsed read stays on the separate SAME Source initializer.
/// No per-source page sum, new tariff, reservation or permission is issued.
pub fn row_source_get_request_construction_capacity(
  transport : @execution.ExecutionCapacity,
  pages : Array[@execution.ExecutionCapacity],
) -> @execution.ExecutionCapacity? {
  if pages.is_empty() {
    return None
  }
  let mut retained = 0L
  let mut execution = 0L
  for page in pages {
    retained = Int64::max(
      retained,
      @execution.execution_capacity_retained_bytes(page),
    )
    execution = Int64::max(
      execution,
      @execution.execution_capacity_execution_bytes(page),
    )
  }
  guard @execution.execution_capacity(retained, execution) is Some(peak) else {
    return None
  }
  @execution.add_execution_capacity(transport, peak)
}

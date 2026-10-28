///|
/// Selected JSON-page reader representation. Inputs are rejection bounds,
/// never Ledger limits, permission, reservations or runtime heap measurements.
/// The original acquisition still reserves this declaration on its B parent.
pub fn installed_source_reader_policy() -> Array[Int] {
  let preparation = @publication_host.client_standard_program_preparation_limits()
  let values = @publication_host.client_standard_values_sequence_limits()
  [
    preparation.checking.input.tree.max_string_bytes,
    preparation.checking.compilation.structure.bindings,
    values.max_cells / values.max_rows,
  ]
}

///|
/// One response's Source-owned non-ASCII parser, exact indexed admission and
/// key-normalization workspace. The original received Bytes are borrowed;
/// parse_json_bytes owns a separate decoded String. No ASCII eligibility or
/// string-value normalization is inferred, and no capacity is granted here.
fn installed_source_response_workspace(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @source.json_literal_construction_extent(bytes, nodes, depth)
    is Some(literal) &&
    scalar_snapshot_name_normalization_layout(bytes) is Some(normalization) else {
    return None
  }
  // Reuse ONLY the decoder's structural families. Each category is separately
  // bounded by all parsed nodes; simultaneous objects+arrays deliberately
  // overcount. These are constructor bounds, not facts from the ASCII scan.
  // Its parser/text/ASCII-control inventories are not consumed below.
  let indexed = closed_values_source_inventories({
    input_bytes: bytes,
    node_upper: nodes,
    objects: nodes,
    arrays: nodes,
    fields_upper: nodes,
    quoted_tokens: 0,
    quoted_utf16_units: 0,
    longest_quoted_utf16: 0,
    longest_atom_utf16: 0,
    depth_upper: Int::min(nodes, depth),
  })
  let source : @execution.PreparationRepresentationUnits = {
    record_headers: literal.record_headers,
    reference_slots: literal.reference_slots,
    scalar_words: literal.scalar_words,
    owned_utf16_units: literal.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  // Unicode 16's pinned <=4-scalar recursive expansion gives <=8 UTF16
  // units per decoded key unit. Sum all normalized key output with the
  // non-normalizing tree bound, even if old text would already be unrooted.
  // The separate one-key normalization workspace includes scalar arrays,
  // stable ordering, builder, LF passes and bounded recursive controls.
  let input_and_keys : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + nodes.to_int64(),
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 9L * bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  @execution.compose_preparation_representation([
    source,
    indexed.indexed_additional,
    indexed.key_admission_peak,
    indexed.decoder_ancestry_peak,
    indexed.decoder_controls_peak,
    normalization,
    input_and_keys,
  ])
}

///|
pub fn installed_json_source_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
) -> @execution.ExecutionCapacity? {
  // Same field order as the installed JSON reader's immutable limits view.
  // response/total/nodes/depth/rows/totalRows/pages/pageSize/cursor/identity/
  // target/valueNodes/valueText/rowWire/rowNodes/rowDepth.
  if limits.length() != 16 || columns < 1 || secret_bytes < 1 {
    return None
  }
  for value in limits {
    if value < 1 {
      return None
    }
  }
  let response = limits[0].to_int64()
  let total = limits[1].to_int64()
  let rows = limits[4].to_int64()
  let ids = limits[5].to_int64()
  let pages = limits[6].to_int64()
  let cursors = pages
  let originals = pages + 1L
  let fields = columns.to_int64()
  // Charge/retain the original received body before a total-byte refusal.
  // One offending response overlaps the admitted total; no new request is
  // allowed after it. The response inventory includes that same original.
  guard @execution.checked_preparation_add_product(total, response, 1L)
    is Some(raw) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      0L,
      ids,
      limits[9].to_int64(),
    )
    is Some(id_text) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      id_text,
      cursors,
      limits[8].to_int64(),
    )
    is Some(text) else {
    return None
  }
  // The exact use CID is retained by each received response; credential text
  // stays only in the original per-read binding, never in provider rows.
  guard @execution.checked_preparation_add_product(text, originals, 71L)
    is Some(text) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      text,
      secret_bytes.to_int64(),
      1L,
    )
    is Some(text) else {
    return None
  }
  // Source-owned reader frame, handle/custody/binding envelopes, captured
  // methods and callback environments, provider invocation context/limits,
  // prepared reader/state, two projected-name vectors and two live Sets.
  // Original installation/schema/Account/Journal backing remains borrowed.
  // The same reader retains one optional direct sequence reference in its
  // existing frame until original read/binding retirement; no child Owner.
  let common_fields = 35L + 4L + 1L + 3L + 3L + 21L + 6L + 2L + 2L
  let provider_fields = 5L + 5L + 6L + 3L + 18L + 16L + 5L + 6L + 8L + 4L
  let closures = 13L
  // One resolver-close carrier (six fields), its original binding field and
  // four joined callback environments. The same FD remains with its existing
  // file Owner; these are managed control records, not a physical FD price.
  let resolver_headers = 5L
  let resolver_slots = 11L
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 39L + resolver_headers + 3L * originals,
    reference_slots: common_fields +
    provider_fields +
    closures +
    resolver_slots +
    4L +
    2L * fields +
    9L * originals +
    2L * ids +
    2L * cursors,
    scalar_words: 20L + 3L * originals + ids + cursors,
    owned_utf16_units: text,
    owned_wire_bytes: raw,
  }
  // Provider projection, admitted values and the parsed output row page
  // coexist with the Source/indexed workspace below. JSON-node pricing comes
  // from B's shared
  // fold, not another provider-specific byte tariff.
  guard @execution.checked_preparation_add_product(
      limits[2].to_int64(),
      limits[14].to_int64(),
      1L,
    )
    is Some(nodes) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      nodes,
      limits[11].to_int64(),
      1L,
    )
    is Some(nodes) else {
    return None
  }
  guard @execution.checked_preparation_add_product(nodes, rows, fields)
    is Some(nodes) else {
    return None
  }
  // Current raw decode, provider row wire, parsed-row serialization, target
  // encoding and literal admission text are distinct live work buffers.
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: 20L,
    reference_slots: 3L +
    18L +
    3L +
    18L +
    5L +
    6L +
    2L +
    1L +
    6L +
    4L +
    4L +
    15L,
    scalar_words: 12L,
    owned_utf16_units: response +
    3L * limits[13].to_int64() +
    limits[10].to_int64() +
    limits[12].to_int64(),
    owned_wire_bytes: response + limits[13].to_int64(),
  }
  guard installed_source_response_workspace(limits[0], limits[2], limits[3])
    is Some(response_workspace) &&
    @execution.compose_preparation_representation([
      workspace, response_workspace,
    ])
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: nodes,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

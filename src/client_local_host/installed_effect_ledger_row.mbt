///|
// The original one-row Ledger call retains its existing complete controls.
// These quantities select only the classes constructed by its closed methods;
// no returned buffer, Entry or Receipt is released by selecting this frame.
fn installed_effect_ledger_row_workspace(
  kind : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
  response_bytes : Int,
) -> Int64? {
  if (
      kind != "entry" &&
      kind != "response" &&
      kind != "receipt" &&
      kind != "quantity"
    ) ||
    response_bytes < 1 ||
    response_bytes > 1000000 {
    return None
  }
  guard installed_effect_ledger_family_workspace(
      [1],
      100000,
      bytes,
      nodes,
      depth,
    )
    is Some(entry) else {
    return None
  }
  // SQL input/native row and Buffer.from, including the collision branch's
  // Buffer.from(input), coexist with the caller's independently owned physical
  // response. Existing per-row controls retain those three receiver buffers.
  // Keep another full three-buffer constructor envelope here; it is scratch,
  // not a return of the original retained floor.
  // Fixed carriers: input/return/SQL row and validation records, four query
  // results and transaction/hash frames; four tiny query/argument Arrays.
  guard @shape.collection_construction_extent({
      records: 16L,
      record_references: 72L,
      record_words: 24L,
      reference_arrays: 4L,
      reference_items: 24L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(fixed) &&
    @execution.preparation_representation_cost({
      record_headers: fixed.record_headers,
      reference_slots: fixed.reference_slots,
      scalar_words: fixed.scalar_words,
      // Four received CID fields and digest plus all three hash templates,
      // their UTF8 conversions and the final hex digest. SQL bounds each
      // selected text field before materialization, including refused input.
      owned_utf16_units: 4L * 71L + 64L + 143L + 143L + 4L + 64L,
      owned_wire_bytes: 3L * response_bytes.to_int64() + 143L + 143L + 4L + 64L,
    })
    is Some(physical) &&
    @execution.checked_preparation_add_product(entry, physical, 1L)
    is Some(workspace) else {
    return None
  }
  Some(workspace)
}

///|
// The scan owns no forest. Its fixed cursor is prepaid on the original
// operation control, before entering either the scan or its eventual parser.
fn installed_effect_receipt_codec_capacity(
  wire : String,
  nodes : Int,
  depth : Int,
  receipt_wire : Bool,
) -> @execution.ExecutionCapacity? {
  if nodes < 1 || nodes > 4096 || depth < 1 || depth > 32 {
    return None
  }
  let bytes = match @scalar.admit_utf8_length(wire, 1000000) {
    Ok(bytes) => bytes
    Err(_) => return None
  }
  if bytes < 1 {
    return None
  }
  let observed = installed_effect_dependency_wire_geometry(
    wire,
    1000000,
    nodes,
    depth,
    _ => true,
  )
  // Keep the old conservative family when this lexical scan itself refuses.
  // The actual semantic parser remains the only admission and still runs once.
  guard observed is Some(geometry) else {
    return standard_create_saved_receipt_capacity(bytes, nodes, depth)
  }
  // The issuer emits eleven literal Receipt fields around the exact ordered
  // typed outcome. Sealing adds its self-CID. Admission retains its candidate
  // while regenerating the expected Receipt; the unchanged four/six-family
  // tariff below already covers their simultaneous parsers/writers/forests.
  // Receiving a complete Receipt is conservatively allowed another envelope,
  // rather than subtracting its existing fields from the observed census.
  let envelope_nodes = 12
  let bound_nodes = geometry.node_upper + envelope_nodes
  let _ = receipt_wire
  let keys = "credential_use_ciddispatch_entry_cideffect_member_preview_cideffect_preview_cidhttp_status_coderesponse_byte_countresponse_physical_sha256row_preview_cidtyped_outcometyped_outcome_cidversionreceipt_cid"
  let envelope_bytes = keys.length() +
    7 * 71 +
    64 +
    20 +
    "actql-effect-row-outcome-receipt/0.1".length() +
    7 * 12 +
    2
  guard @execution.checked_preparation_add_product(
      bytes.to_int64(),
      envelope_bytes.to_int64(),
      1L,
    )
    is Some(bound_bytes) &&
    bound_bytes <= 2147483647L else {
    return None
  }
  standard_create_saved_receipt_capacity(
    bound_bytes.to_int(),
    bound_nodes,
    depth,
  )
}

///|
// SQL's same read transaction supplies the actual bounded entry_json UTF16
// total before allocating its history. Three Arrays (native rows, materialized
// rows, typed Entries) and their possible growth, both SQL row carriers,
// validateStored carrier, flat typed Entry/Options and every text backing are
// temporary until this outer constructor returns. Never deduplicate by CID.
fn installed_effect_ledger_history_workspace(
  count : Int,
  wire_units : Int64,
) -> Int64? {
  if count < 0 || count > 100000 || wire_units < 0L {
    return None
  }
  let n = count.to_int64()
  guard @shape.collection_construction_extent({
      records: 26L * n,
      record_references: 30L * n,
      record_words: 26L * n,
      reference_arrays: 3L,
      reference_items: 6L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(history) &&
    @execution.checked_preparation_add_product(
      20L * 71L * n + 76L * n,
      wire_units,
      3L,
    )
    is Some(text) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: history.record_headers,
    reference_slots: history.reference_slots,
    scalar_words: history.scalar_words,
    owned_utf16_units: text,
    // A malformed UTF16 database String can require three UTF8 bytes per
    // code unit before physicalDigest/semantic admission rejects it.
    owned_wire_bytes: 3L * wire_units,
  })
}

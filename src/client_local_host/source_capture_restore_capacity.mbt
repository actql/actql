///|
// Fixed construction of the sizing reports themselves, before any represented
// descriptor/row storage is admitted. Conservative call-expanded packet:
// - co-held raw-parser/key and object/array admission endpoint reports;
// - canonical normalizer, hash/text writer and append-capacity reports;
// - retained/temporary Unit records, two/eight-item composition arrays,
//   checked arithmetic/Some/Result carriers and the final two-scalar quote.
// Source identity arrays and occurrence decimal strings share these fixed
// controls. These contain counts only, not input text/trees. The policy-bounded loop
// keeps only its current reports and aggregate, never a history of quotes.
// 512H/2048R/2048W deliberately co-counts sequential helper alternatives.
// The original Ledger must admit this temporary debit; it is not a grant.
let source_capture_restore_quote_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 512L,
    reference_slots: 2048L,
    scalar_words: 2048L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
// Constructor DATA for the existing saved-capture receiver. It describes no
// database query, native/broad executor, new grant or separate Ledger. Input
// strings remain borrowed from the original authenticated custody.
fn source_capture_restore_json_units(
  units : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  // Whole Input recovery has no Query descriptor to parse. Empty refused row
  // wires likewise allocate no parser/admission tree.
  if units == 0 {
    return Some({
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
  }
  guard units >= 0 &&
    @execution.checked_preparation_add_product(0L, units.to_int64(), 3L)
    is Some(bytes) &&
    bytes <= 2147483647L else {
    return None
  }
  // UTF8 is at most three bytes per UTF16 unit. The retained-row preflight
  // checks its node/depth ceilings before Json allocation. Descriptor Json
  // precedes canonical admission, so its raw String length bounds both.
  let nodes = Int::max(1, Int::min(units, max_nodes))
  let depth = Int::min(nodes, max_depth)
  guard @decode.preserving_json_admission_construction_inventory(
      bytes.to_int(),
      nodes,
      depth,
    )
    is Some(value) else {
    return None
  }
  Some({
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: value.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn source_capture_restoration_capacity(
  descriptor : String,
  rows : Array[String],
  original_input : (String, String, Array[String])?,
  input_policy? : @row_source_host.RowInputLimits,
  input_columns? : Int,
  original_capacity? : (Int64, Int64),
) -> @execution.ExecutionCapacity? {
  let max_rows = input_policy.map(value => value.max_rows).unwrap_or(100)
  let wire = input_policy
    .map(value => value.wire)
    .unwrap_or_else(source_capture_wire)
  let decode : @execution.RetainedRowDecodeLimits = match input_policy {
    Some(value) =>
      {
        max_bytes: value.wire.max_bytes,
        max_nodes: value.wire.max_nodes,
        max_depth: value.wire.max_depth,
        max_text_bytes: value.wire.max_bytes,
      }
    None => source_capture_decode()
  }
  // Existing refusal paths precede Json/row allocation. Sizing does not
  // replace their original InvalidDescriptor/BindingMismatch/InputLimit.
  let descriptor_units = if descriptor.length() > 8192 {
    0
  } else {
    descriptor.length()
  }
  let count = if descriptor.length() > 8192 || rows.length() > max_rows {
    0
  } else {
    rows.length()
  }
  // Capture/receipt/readmission/import/output/port records and their original
  // closures, refs, typed return/failure carriers. Four stream/buffer/budget
  // groups and bounded schema/order arrays coexist until the import returns.
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 128L,
    reference_slots: 384L,
    scalar_words: 256L,
    // Two verification receipts and their retained/import/capture joins;
    // digest/hex scratch is separately owned by the writer inventories.
    owned_utf16_units: 6L * 71L,
    owned_wire_bytes: 0L,
  }
  let mut retained = controls
  let mut total_units = 0L
  let mut total_nodes = 0L
  let mut largest = 0
  for index in 0..<count {
    let row = rows[index]
    // An oversized borrowed String is refused by the byte preflight before
    // Json allocation; its original failure still comes from that decoder.
    let units = if row.length() > decode.max_bytes { 0 } else { row.length() }
    guard source_capture_restore_json_units(
        units,
        decode.max_nodes,
        decode.max_depth,
      )
      is Some(value) &&
      @execution.compose_preparation_representation([retained, value])
      is Some(next) &&
      @execution.checked_preparation_add_product(
        total_units,
        units.to_int64(),
        1L,
      )
      is Some(next_units) &&
      @execution.checked_preparation_add_product(
        total_nodes,
        Int::min(units, decode.max_nodes).to_int64(),
        1L,
      )
      is Some(next_nodes) else {
      return None
    }
    // The final receiving Value tree is conservatively bounded by its entire
    // preserving Json/admission constructor. This is an explicit overbound,
    // not a claim that the parser/index remains live after return.
    retained = next
    total_units = next_units
    total_nodes = next_nodes
    largest = Int::max(largest, units)
  }
  let row_count = count.to_int64()
  // Original rows.copy plus receiving/verification row and presence arrays,
  // including append growth. Field slots are bounded by the row node count;
  // four schema/order arrays use the actual constructor column bound.
  guard @execution.checked_preparation_add_product(
      8L * row_count,
      total_nodes,
      4L,
    )
    is Some(array_items) &&
    @execution.checked_preparation_add_product(
      array_items,
      input_columns.unwrap_or(wire.max_columns).to_int64(),
      4L,
    )
    is Some(array_items) &&
    @execution.preparation_array_representation(
      6L + 4L * row_count,
      array_items,
      true,
    )
    is Some(arrays) &&
    @execution.compose_preparation_representation([retained, arrays])
    is Some(retained) &&
    source_capture_restore_json_units(
      descriptor_units,
      Int::max(1, descriptor_units),
      Int::max(1, descriptor_units),
    )
    is Some(descriptor_work) &&
    source_capture_restore_json_units(
      largest,
      decode.max_nodes,
      decode.max_depth,
    )
    is Some(row_work) else {
    return None
  }
  // Descriptor normalization is not an ASCII assumption: its raw Json and
  // resulting canonical tree overlap. Two full parser/admission majorants
  // conservatively cover those smaller closed trees/maps. The canonical
  // Owner separately supplies one normalizer peak and all retained outputs.
  guard scalar_snapshot_name_normalization_layout(descriptor_units)
    is Some(normalization) &&
    @canonical.nfc_lf_retained_output_units(descriptor_units.to_int64())
    is Some(normalized_text) else {
    return None
  }
  let normalized : @execution.PreparationRepresentationUnits = {
    record_headers: descriptor_units.to_int64(),
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: normalized_text,
    owned_wire_bytes: 0L,
  }
  // Strings escape by <=6 units per input unit; a numeric atom emits <=25
  // units and its punctuation consumes input too. 32U+2R bounds the encoded
  // forest, capped by the existing writer's checked byte ceiling. No policy
  // ceiling is preallocated by the actual writer.
  guard @execution.checked_preparation_add_product(
      2L * row_count,
      total_units,
      32L,
    )
    is Some(encoded) else {
    return None
  }
  let bytes = Int64::min(encoded, wire.max_bytes.to_int64()).to_int()
  let nodes = Int64::min(total_nodes + 1L, wire.max_nodes.to_int64()).to_int()
  let depth = Int::min(Int::max(1, largest), decode.max_depth)
  guard @encode.hash_writer_construction_inventory(nodes, depth) is Some(hash) &&
    @encode.text_writer_construction_inventory(bytes, Int::max(1, nodes), depth)
    is Some(text) else {
    return None
  }
  let writer : @execution.PreparationRepresentationUnits = {
    record_headers: hash.record_headers + text.record_headers,
    reference_slots: hash.reference_slots + text.reference_slots,
    scalar_words: hash.scalar_words + text.scalar_words,
    owned_utf16_units: hash.owned_utf16_units + text.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  }
  // Retained-content verification and completed-output import each keep its
  // own stream/writer. The finished first reader still overlaps the second.
  // Current-row Json/index/decoder overlaps both complete Value inventories.
  guard @execution.compose_preparation_representation([
      controls, descriptor_work, descriptor_work, normalization, normalized, row_work,
      writer, writer,
    ])
    is Some(workspace) else {
    return None
  }
  let (original_retained, original_execution) = match original_input {
    None => (0L, 0L)
    Some(_) =>
      match original_capacity {
        Some(value) => value
        None => return None
      }
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    // One final imported Value forest, the first reader's complete forest,
    // and one in-flight decoded row use the existing Value-node slot owner.
    retained_nodes: total_nodes,
    workspace_nodes: total_nodes +
    Int::min(largest, decode.max_nodes).to_int64(),
    retained_bytes: original_retained,
    workspace_bytes: original_execution - original_retained,
  })
}

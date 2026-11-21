///|
pub fn local_import_start_retention_capacity(
  limits : LocalImportLimits,
) -> Int64? {
  local_import_retention_capacity({
    max_rows: 0,
    values: { ..limits.values, max_nodes: 0, max_text_bytes: 0, },
    wire: { ..limits.wire, max_bytes: 0, max_nodes: 0, },
    row: { ..limits.row, max_bytes: 1, max_nodes: 0, max_text_bytes: 0, },
    max_batch_bytes: 1,
  })
}

///|
// The default copies the previous wire-based bound. Presence-aware consumers
// can supply an independently bounded retained row inventory without changing
// the decoder's complete wire extent. Each bridge keeps its own prefix.
pub fn local_import_next_retention_extent(
  limits : LocalImportLimits,
  rows : Int64,
  nodes : Int64,
  text : Int64,
  wire_bytes : Int64,
  pending_value_nodes? : Int64? = None,
  pending_value_text? : Int64? = None,
) -> (Int64, Int64, Int64, Int64)? {
  let max_rows = limits.max_rows.to_int64()
  let max_nodes = limits.values.max_nodes.to_int64()
  let max_text = limits.values.max_text_bytes.to_int64()
  let value_nodes = pending_value_nodes.unwrap_or(wire_bytes)
  let value_text = pending_value_text.unwrap_or(wire_bytes)
  guard rows >= 0L &&
    rows <= max_rows &&
    nodes >= 0L &&
    nodes <= max_nodes &&
    text >= 0L &&
    text <= max_text &&
    wire_bytes >= 0L &&
    value_nodes >= 0L &&
    value_text >= 0L else {
    return None
  }
  let next_rows = rows + Int64::min(1L, max_rows - rows)
  let next_nodes = nodes + Int64::min(value_nodes, max_nodes - nodes)
  let next_text = text + Int64::min(value_text, max_text - text)
  guard local_import_start_retention_capacity(limits) is Some(start) &&
    local_import_retention_capacity({
      max_rows: next_rows.to_int(),
      values: {
        ..limits.values,
        max_nodes: next_nodes.to_int(),
        max_text_bytes: next_text.to_int(),
      },
      // Every parser node, text byte and provisional reference is bounded by
      // this complete UTF-8 row. These are funding extents only; append still
      // receives all original parser, wire and cumulative admission limits.
      wire: {
        ..limits.wire,
        max_bytes: Int64::min(limits.wire.max_bytes.to_int64(), wire_bytes).to_int(),
        max_nodes: Int64::min(limits.wire.max_nodes.to_int64(), wire_bytes).to_int(),
      },
      row: {
        ..limits.row,
        max_bytes: Int64::max(
          1L,
          Int64::min(limits.row.max_bytes.to_int64(), wire_bytes),
        ).to_int(),
        max_nodes: Int64::min(limits.row.max_nodes.to_int64(), wire_bytes).to_int(),
        max_text_bytes: Int64::min(
          limits.row.max_text_bytes.to_int64(),
          wire_bytes,
        ).to_int(),
      },
      max_batch_bytes: Int64::max(
        1L,
        Int64::min(limits.max_batch_bytes.to_int64(), wire_bytes),
      ).to_int(),
    })
    is Some(quoted) &&
    quoted >= start else {
    return None
  }
  Some((next_rows, next_nodes, next_text, quoted - start))
}

///|
/// Per-port growth counters and the before-decode closure are allocated only
/// for the certified materializing route. The original importer limits remain
/// the semantic admission policy.
pub fn local_materializing_import_start_capacity(
  limits : LocalImportLimits,
) -> Int64? {
  local_import_start_retention_capacity(limits).bind(start => {
    @execution.preparation_representation_cost({
      record_headers: 9L,
      reference_slots: 12L,
      scalar_words: 12L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).bind(controls => {
      @execution.checked_preparation_add_product(start, controls, 1L)
    })
  })
}

///|
/// Empty Store reservation is quota, not file preallocation. Keep all row
/// authority/reference and depth/column backing; fund actual file and batch
/// bytes before the existing export writer emits them.
pub fn local_materializing_export_start_capacity(
  limits : LocalExportLimits,
) -> Int64? {
  guard local_export_retention_capacity(limits) is Some(_) else { return None }
  local_export_retention_capacity({
    ..limits,
    wire: { ..limits.wire, max_bytes: 0, },
    max_batch_bytes: 1,
  }).bind(start => {
    @execution.preparation_representation_cost({
      record_headers: 14L,
      reference_slots: 48L,
      scalar_words: 16L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).bind(controls => {
      @execution.checked_preparation_add_product(start, controls, 1L)
    })
  })
}

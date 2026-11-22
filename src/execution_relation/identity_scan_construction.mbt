///|
fn identity_scan_capacity(
  units : PreparationRepresentationUnits,
) -> ExecutionCapacity? {
  preparation_execution_capacity({
    retained: units,
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// Retained DATA of one completed export after its scan/writers have returned.
/// The original completed output, Values and field-name Text stay borrowed at
/// their existing owner. Only the new receipt, summaries, indexes and identity
/// Strings are counted here. This invokes no current/Reference callback and
/// re-encodes, hashes or admits no row. The optional logical body is separate.
pub fn completed_relation_export_retained_capacity(
  receipt : CompletedRelationExportReceipt,
) -> ExecutionCapacity? {
  completed_relation_export_retained_units(
    receipt,
    include_reference_index=true,
  ).bind(identity_scan_capacity)
}

///|
fn completed_relation_export_retained_units(
  receipt : CompletedRelationExportReceipt,
  include_reference_index~ : Bool,
) -> PreparationRepresentationUnits? {
  if receipt.rows.source is None || receipt.rows.binding {
    return None
  }
  let summary = receipt.measurement
  let scalar_slots = summary.column_rows.capacity().to_int64() +
    summary.column_bytes.capacity().to_int64() +
    summary.column_nodes.capacity().to_int64() +
    summary.column_max_value_bytes.capacity().to_int64() +
    summary.column_null_rows.capacity().to_int64() +
    summary.column_admitted_depths.capacity().to_int64()
  guard @shape.reference_array_retained_extent(
      2L,
      receipt.fields.capacity().to_int64() +
      receipt.schema.field_names.capacity().to_int64(),
    )
    is Some(names) &&
    @shape.reference_array_retained_extent(6L, 0L) is Some(scalars) else {
    return None
  }
  // Relation/row receipt, original export identity, content/usage, logical
  // identity, schema, summaries, original-source Some and four owned Texts.
  let mut h = 13L + names.record_headers + scalars.record_headers
  let mut r = 28L + names.reference_slots + scalars.reference_slots
  let mut w = 20L + names.scalar_words + scalars.scalar_words + scalar_slots
  if receipt.rows.references is Some(references) {
    if !references.complete || references.revoked {
      return None
    }
    // Keep the existing conservative original-reference index envelope.
    // It is a live child of this receipt, not disposable scan/writer scratch.
    // Its bounded slot census avoids walking Source rows or reissuing refs.
    if include_reference_index {
      let live = references.workspace.live.to_int64()
      guard @shape.collection_construction_extent({
          records: 3L + live,
          record_references: 4L + live,
          record_words: 6L + live,
          reference_arrays: live + 1L,
          reference_items: live,
          scalar_arrays: 0L,
          scalar_items: 0L,
          maps: 0L,
          map_entries: 0L,
        })
        is Some(index) else {
        return None
      }
      h += index.record_headers
      r += index.reference_slots
      w += index.scalar_words
    }
  }
  Some({
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: receipt.rows.content.cid.length().to_int64() +
    receipt.logical.cid.length().to_int64() +
    receipt.schema.cid.length().to_int64() +
    receipt.schema.wire.length().to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
/// Survivors of the same finished Named Result preparation and its receipt.
/// The caller has separately backed the sorted row indexes and reference
/// collector. Names and schema are shared by the stream and the receipt;
/// their actual backing is counted in the receipt once. No callback is run.
pub fn completed_result_export_retained_metadata_capacity(
  preparation : CompletedResultRelationExportPreparation,
  receipt : CompletedRelationExportReceipt,
) -> ExecutionCapacity? {
  guard preparation.closed &&
    !preparation.advancing &&
    preparation.rows.closed &&
    preparation.metadata is None &&
    preparation.rows.mapping_input is None &&
    preparation.rows.comparison.tree is NoRowComparison &&
    preparation.stream is Some(stream) &&
    stream.source is None &&
    !stream.reading &&
    stream.pending_row is None &&
    stream.references is None &&
    stream.budget.retention is None &&
    stream.budget.row_scratch_start is None &&
    stream.schema is Some(schema) &&
    receipt.rows.source is Some(source) &&
    physical_equal(preparation.rows.source, source) &&
    physical_equal(stream.export_identity, receipt.rows.export_identity) &&
    physical_equal(stream.rows.names, receipt.fields) &&
    physical_equal(schema, receipt.schema) &&
    completed_relation_export_retained_units(
      receipt,
      include_reference_index=false,
    )
    is Some(received) else {
    return None
  }
  let columns = stream.rows.columns.map(columns => columns.capacity().to_int64())
  let cells = stream.order.columns.length().to_int64()
  let order_slots = stream.order.columns.capacity().to_int64()
  // Empty arrays: five on the completed Result-view preparation, six
  // replacements for the moved measurement arrays, and two closed writers'
  // frame arrays. Order has reference slots; the projected columns have
  // scalar backing. The receipt already owns both shared name arrays.
  guard @shape.reference_array_retained_extent(14L, order_slots) is Some(refs) &&
    @shape.reference_array_retained_extent(
      if columns is Some(_) {
        1L
      } else {
        0L
      },
      0L,
    )
    is Some(scalars) else {
    return None
  }
  // Fixed retained controls: preparation, Result view, stream, projected
  // rows, order, value budget, mapping Ref, comparison and charge cursors,
  // original Options and two closed Writer records. Successful hash finish
  // clears each sink and frame backing; no hash or output buffer survives.
  identity_scan_capacity({
    record_headers: received.record_headers +
    24L +
    refs.record_headers +
    scalars.record_headers +
    cells,
    reference_slots: received.reference_slots +
    72L +
    refs.reference_slots +
    scalars.reference_slots +
    cells,
    scalar_words: received.scalar_words +
    80L +
    refs.scalar_words +
    scalars.scalar_words +
    columns.unwrap_or(0L) +
    cells,
    owned_utf16_units: received.owned_utf16_units,
    owned_wire_bytes: received.owned_wire_bytes,
  })
}

///|
/// Before starting the incremental metadata mode: copy only the actual owned
/// name array and create empty preparation/control/summary arrays. Schema,
/// writer, row and value materialization occur in later original transitions.
/// This reads immutable table metadata, not current authority or output values.
pub fn completed_relation_identity_scan_start_construction_capacity(
  source : CompletedOutput,
  retain_body? : Bool = false,
  producer_input? : ProducerRead? = None,
) -> ExecutionCapacity? {
  guard source.table is Some(table) else { return None }
  if producer_input is Some(read) && read.bound.projection is Some(_) {
    return None
  }
  let width = producer_input
    .map(read => @schema.field_count(read.schema).to_int64())
    .unwrap_or(IndexedRows::column_count(table).to_int64())
  completed_export_metadata_start_capacity(width, retain_body)
}

///|
fn completed_export_metadata_start_capacity(
  width : Int64,
  retain_body : Bool,
) -> ExecutionCapacity? {
  guard @shape.collection_construction_extent({
      records: 28L,
      record_references: 63L,
      record_words: 65L,
      reference_arrays: if retain_body {
        4L
      } else {
        3L
      },
      reference_items: width + (if retain_body { 1L } else { 0L }),
      scalar_arrays: 6L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(start) else {
    return None
  }
  identity_scan_capacity({
    record_headers: start.record_headers,
    reference_slots: start.reference_slots,
    scalar_words: start.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// Actual order/name/summary backing plus one next column. Policy maxima
// validate these arrays but never allocate policy-sized storage here.
fn completed_export_metadata_next_inventory(
  value : CompletedOutputExportPreparation,
) -> PreparationRepresentationUnits? {
  guard !value.closed && value.rows is Some(rows) else { return None }
  let width = rows.names.capacity().to_int64()
  let order = value.order_cursor.columns.capacity().to_int64()
  let names = value.names.capacity().to_int64()
  let scalar_slots = value.column_rows.capacity().to_int64() +
    value.column_bytes.capacity().to_int64() +
    value.column_nodes.capacity().to_int64() +
    value.column_max_value_bytes.capacity().to_int64() +
    value.column_null_rows.capacity().to_int64() +
    value.column_admitted_depths.capacity().to_int64()
  guard @shape.collection_construction_extent({
      // Scan/preparation/rows/order, comparator/text charge, both workspaces,
      // ValueBudget and fixed option/transition/receipt carriers. Column tuples
      // retain their original names; no string/value body is copied here.
      records: 28L + order + 1L,
      record_references: 63L + order + 1L,
      record_words: 65L + order + 1L,
      reference_arrays: 3L,
      reference_items: width + order + names + 3L,
      scalar_arrays: 6L,
      scalar_items: scalar_slots + 6L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(arrays) else {
    return None
  }
  let mut h = arrays.record_headers
  let mut r = arrays.reference_slots
  let mut w = arrays.scalar_words
  let mut t = 0L
  let mut b = 0L
  if value.schema_cursor is Some(cursor) {
    guard relation_schema_identity_next_inventory(cursor) is Some(schema) else {
      return None
    }
    h += schema.record_headers
    r += schema.reference_slots
    w += schema.scalar_words
    t += schema.owned_utf16_units
    b += schema.owned_wire_bytes
  } else if value.schema_identity is Some(identity) {
    h += 4L
    r += 4L + identity.field_names.capacity().to_int64()
    w += 5L
    t += identity.wire.length().to_int64() + identity.cid.length().to_int64()
  } else if value.phase == 2 && value.schema_limits is Some(_) {
    // This transition creates empty sinks and a one-frame contract cursor.
    guard @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
      @encode.text_writer_construction_inventory(0, 1, 0) is Some(text) else {
      return None
    }
    h += 12L + hash.record_headers + text.record_headers
    r += 30L + hash.reference_slots + text.reference_slots
    w += 20L + hash.scalar_words + text.scalar_words
    t += hash.owned_utf16_units + text.owned_utf16_units
    b += hash.owned_wire_bytes
  }
  if value.phase >= 2 && value.schema_cursor is None {
    let buffered = @encode.buffered_hash_writer_start_construction_inventory()
    // Stream construction emits only the fixed logical wrapper before yield.
    guard @encode.hash_writer_live_key_inventory(5, 2) is Some(hash) else {
      return None
    }
    h += buffered.record_headers + hash.record_headers
    r += buffered.reference_slots + hash.reference_slots
    w += buffered.scalar_words + hash.scalar_words
    t += buffered.owned_utf16_units + hash.owned_utf16_units + 32L
    b += buffered.owned_wire_bytes + hash.owned_wire_bytes
  }
  Some({
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: t,
    owned_wire_bytes: b,
  })
}

///|
/// Before ONE transition of the same scan. Observe charged writer/cursor/
/// array cells without traversing values or building another row/document.
/// The original caller grows backing before advancing; this DATA grants none.
pub fn completed_relation_identity_scan_next_construction_capacity(
  value : CompletedRelationIdentityScan,
) -> ExecutionCapacity? {
  if value.closed || value.advancing {
    return None
  }
  identity_scan_next_capacity(value)
}

///|
// Same private owner during its latched advance. This numerical inventory
// invokes no callback and exports no reusable current or Resource proof.
fn identity_scan_next_capacity(
  value : CompletedRelationIdentityScan,
) -> ExecutionCapacity? {
  if value.preparation is Some(preparation) {
    guard completed_export_metadata_next_inventory(preparation) is Some(units) else {
      return None
    }
    return identity_scan_add_retained_body_capacity(value, units)
  }
  guard value.stream is Some(stream) &&
    stream.logical_writer is Some(logical) &&
    @encode.buffered_hash_writer_next_construction_inventory(
      stream.writer,
      @admitted.wire_emit_fragment_byte_bound(),
      value.fragment_peak,
      3,
      2,
    )
    is Some(buffered) &&
    @encode.hash_writer_next_construction_inventory(logical, 3, 2) is Some(hash) else {
    return None
  }
  let width = stream.order.columns.capacity().to_int64()
  guard @shape.collection_construction_extent({
      records: width,
      record_references: width,
      record_words: width,
      reference_arrays: 3L,
      reference_items: 3L * width,
      scalar_arrays: 6L,
      scalar_items: 6L * width,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(arrays) else {
    return None
  }
  // Stream/Scan, receipt/measurement and scalar/key/phase/finish carriers.
  let mut h = 24L +
    buffered.record_headers +
    hash.record_headers +
    arrays.record_headers
  let mut r = 63L +
    buffered.reference_slots +
    hash.reference_slots +
    arrays.reference_slots
  let mut w = 49L +
    buffered.scalar_words +
    hash.scalar_words +
    arrays.scalar_words
  let mut t = buffered.owned_utf16_units + hash.owned_utf16_units
  let b = buffered.owned_wire_bytes + hash.owned_wire_bytes
  if stream.schema is Some(schema) {
    h += 4L
    r += 4L + schema.field_names.capacity().to_int64()
    w += 5L
    t += schema.wire.length().to_int64() + schema.cid.length().to_int64()
  }
  let cursor = match value.phase {
    MeasureWire(CapturedWire(cursor), _)
    | EmitPayload(CapturedWire(cursor))
    | EmitLogical(CapturedWire(cursor)) =>
      @admitted.wire_emit_next_construction_inventory(cursor)
    _ => Some(@admitted.wire_emit_start_construction_inventory())
  }
  guard cursor is Some(cursor) else { return None }
  h += cursor.record_headers
  r += cursor.reference_slots
  w += cursor.scalar_words
  t += cursor.owned_utf16_units
  match value.phase {
    MeasureName(measure) | MeasureCell(measure) => {
      let frames = measure.frames.capacity().to_int64() + 2L
      guard @shape.collection_construction_extent({
          records: 1L + frames,
          record_references: 2L + 2L * frames,
          record_words: 1L + 3L * frames,
          reference_arrays: 1L,
          reference_items: frames,
          scalar_arrays: 0L,
          scalar_items: 0L,
          maps: 0L,
          map_entries: 0L,
        })
        is Some(measurement) else {
        return None
      }
      h += measurement.record_headers
      r += measurement.reference_slots
      w += measurement.scalar_words
    }
    MeasureWire(_, writer) => {
      guard @encode.writer_next_frame_construction_extent(writer, 3, 2)
        is Some(measurement) else {
        return None
      }
      h += measurement.record_headers + 2L
      r += measurement.reference_slots
      w += measurement.scalar_words + 4L
    }
    _ => ()
  }
  if stream.references is Some(references) {
    // Each actual reserved metadata slot holds at most one row/column Array
    // or one optional original reference. Include one next transition; neither
    // this census nor its policy limit is a physical reference grant.
    let live = references.workspace.live.to_int64() + 1L
    guard @shape.collection_construction_extent({
        records: 2L + live,
        record_references: 2L + live,
        record_words: 3L + live,
        reference_arrays: live + 1L,
        reference_items: live,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 0L,
        map_entries: 0L,
      })
      is Some(retained) else {
      return None
    }
    h += retained.record_headers
    r += retained.reference_slots
    w += retained.scalar_words
  }
  identity_scan_add_retained_body_capacity(value, {
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: t,
    owned_wire_bytes: b,
  })
}

///|
// Optional body storage is actual emitted Text, not the maximum file/policy.
// Existing collection geometry covers the growing fragments Array. Four live
// UTF-16 copies conservatively cover fragments, joining buffer growth and the
// final String before fragments are cut; the writer's next fragment is already
// bounded by its original emitter. This changes no physical tariff or limit.
fn identity_scan_add_retained_body_capacity(
  value : CompletedRelationIdentityScan,
  base : PreparationRepresentationUnits,
) -> ExecutionCapacity? {
  guard value.retained_body is Some(parts) else {
    return identity_scan_capacity(base)
  }
  identity_scan_body_capacity(
    base,
    parts.capacity().to_int64(),
    value.retained_body_units,
  )
}

///|
fn identity_scan_body_capacity(
  base : PreparationRepresentationUnits,
  parts_capacity : Int64,
  retained_units : Int64,
) -> ExecutionCapacity? {
  guard @shape.collection_construction_extent({
      records: 4L,
      record_references: 8L,
      record_words: 4L,
      reference_arrays: 1L,
      reference_items: parts_capacity + 3L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(storage) else {
    return None
  }
  let text = retained_units +
    @admitted.wire_emit_fragment_byte_bound().to_int64() +
    3L
  identity_scan_capacity({
    record_headers: base.record_headers + storage.record_headers,
    reference_slots: base.reference_slots + storage.reference_slots,
    scalar_words: base.scalar_words + storage.scalar_words,
    owned_utf16_units: base.owned_utf16_units + 4L * text,
    owned_wire_bytes: base.owned_wire_bytes,
  })
}

///|
/// Only the additional optional body storage, beside a caller's already
/// funded legacy input/identity envelope. This avoids charging that existing
/// scan envelope twice when extending the SAME original Read.
pub fn completed_relation_identity_body_start_construction_capacity() -> ExecutionCapacity? {
  identity_scan_body_capacity(
    {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    1L,
    27L,
  )
}

///|
/// Additional retained body demand for this original scan's next step only.
pub fn completed_relation_identity_scan_body_next_construction_capacity(
  value : CompletedRelationIdentityScan,
) -> ExecutionCapacity? {
  if value.closed || value.advancing || value.retained_body is None {
    return None
  }
  identity_scan_add_retained_body_capacity(value, {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Live checked Result metadata while its stream is reading. The sorted row
/// indexes and reference collector remain on their existing reservations.
/// The two active writers and per-row frames are quoted separately.
pub fn completed_result_export_open_metadata_capacity(
  preparation : CompletedResultRelationExportPreparation,
  stream : CompletedOutputExport,
) -> ExecutionCapacity? {
  guard preparation.closed &&
    !preparation.advancing &&
    preparation.rows.closed &&
    preparation.metadata is None &&
    preparation.rows.mapping_input is None &&
    preparation.rows.comparison.tree is NoRowComparison &&
    preparation.stream.map(original => physical_equal(original, stream)) ==
    Some(true) &&
    stream.source is Some(source) &&
    !stream.reading &&
    stream.pending_row is None &&
    stream.budget.retention is None &&
    stream.budget.row_scratch_start is None &&
    physical_equal(preparation.rows.source, source) &&
    stream.schema is Some(schema) else {
    return None
  }
  let order = stream.order.columns
  let scalars = stream.column_rows.capacity().to_int64() +
    stream.column_bytes.capacity().to_int64() +
    stream.column_nodes.capacity().to_int64() +
    stream.column_max_value_bytes.capacity().to_int64() +
    stream.column_null_rows.capacity().to_int64() +
    stream.column_admitted_depths.capacity().to_int64()
  let columns = stream.rows.columns.map(columns => columns.capacity().to_int64())
  // Five empty view Arrays, one order Array and two separate name Arrays.
  guard @shape.reference_array_retained_extent(
      8L,
      order.capacity().to_int64() +
      stream.rows.names.capacity().to_int64() +
      schema.field_names.capacity().to_int64(),
    )
    is Some(refs) &&
    @shape.reference_array_retained_extent(
      6L + (if columns is Some(_) { 1L } else { 0L }),
      0L,
    )
    is Some(scalar_arrays) else {
    return None
  }
  let entries = order.length().to_int64()
  // Preparation, finished view and stream controls, schema identity and its
  // Strings, value budget, original Options and comparison/charge records.
  // Order tuples borrow the original field Text.
  preparation_representation_cost({
    record_headers: 26L +
    refs.record_headers +
    scalar_arrays.record_headers +
    entries,
    reference_slots: 74L +
    refs.reference_slots +
    scalar_arrays.reference_slots +
    entries,
    scalar_words: 85L +
    refs.scalar_words +
    scalar_arrays.scalar_words +
    entries +
    scalars +
    columns.unwrap_or(0L),
    owned_utf16_units: schema.cid.length().to_int64() +
    schema.wire.length().to_int64(),
    owned_wire_bytes: 0L,
  }).bind(bytes => execution_capacity(0L, bytes))
}

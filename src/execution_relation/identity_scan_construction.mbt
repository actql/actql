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
/// Before starting the incremental metadata mode: copy only the actual owned
/// name array and create empty preparation/control/summary arrays. Schema,
/// writer, row and value materialization occur in later original transitions.
/// This reads immutable table metadata, not current authority or output values.
pub fn completed_relation_identity_scan_start_construction_capacity(
  source : CompletedOutput,
  retain_body? : Bool = false,
) -> ExecutionCapacity? {
  guard source.table is Some(table) else { return None }
  let width = IndexedRows::column_count(table).to_int64()
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
  guard @shape.collection_construction_extent({
      records: 4L,
      record_references: 8L,
      record_words: 4L,
      reference_arrays: 1L,
      reference_items: parts.capacity().to_int64() + 3L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(storage) else {
    return None
  }
  let text = value.retained_body_units +
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

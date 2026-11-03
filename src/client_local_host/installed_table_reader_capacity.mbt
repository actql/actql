///|
/// The Local Table process first decodes an announced UTF8 body with native
/// JSON.parse, then snapshots it. Shape refusal happens AFTER that first tree
/// exists, so maxNodes cannot bound its constructor. Every JSON value/field
/// occurrence and decoded UTF16 unit is bounded instead by the SAME checked
/// announced byte count. This is constructor DATA, not a received-byte ticket,
/// a row admission, a new limit, a physical-stop observation or a reservation.
fn installed_table_body_construction_inventory(
  body_bytes : Int,
  max_depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  if body_bytes < 1 || max_depth < 1 {
    return None
  }
  guard @source.json_tree_retained_construction_extent(
      body_bytes,
      body_bytes - 1,
      body_bytes,
      0,
      body_bytes.to_int64(),
      keep_spans=false,
    )
    is Some(tree) else {
    return None
  }
  let parsed : @execution.PreparationRepresentationUnits = {
    record_headers: tree.record_headers,
    reference_slots: tree.reference_slots,
    scalar_words: tree.scalar_words,
    owned_utf16_units: tree.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  // snapshot borrows the original scalar/key String bodies unchanged. Keep
  // its complete structural envelope without pricing those bodies twice.
  let snapshot = { ..parsed, owned_utf16_units: 0L, }
  // The rejecting recursive call can coexist with the last admitted ancestor.
  // Per live frame: frame + original property descriptor (2H), six original
  // item/proto/result/property/key/child roots plus descriptor.value (7R), and
  // depth/array/index/count + descriptor's three property flags (7W). The
  // same parents Set uses the shared growing Map envelope, not another tariff.
  let depth = Int64::min(body_bytes.to_int64(), max_depth.to_int64() + 2L)
  guard @shape.collection_construction_extent({
      records: 2L * depth,
      record_references: 7L * depth,
      record_words: 7L * depth,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: depth,
    })
    is Some(ancestry) else {
    return None
  }
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: ancestry.record_headers,
    reference_slots: ancestry.reference_slots,
    scalar_words: ancestry.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Original raw Buffer + decoded String, decoder/options, one scalar
  // JSON.stringify String and one decimal-index String (6H). A scalar string
  // escapes to at most six code units per original unit plus quotes; finite
  // binary64 text fits the existing Host writer's 25-unit envelope. An array
  // index bounded by a positive Int needs at most ten decimal units. These
  // temporaries coexist with BOTH trees; no NFC or value coercion occurs.
  let bytes = body_bytes.to_int64()
  let scalar_text = Int64::max(6L * bytes + 2L, 25L)
  let wire_and_text : @execution.PreparationRepresentationUnits = {
    record_headers: 6L,
    reference_slots: 2L,
    scalar_words: 1L,
    owned_utf16_units: bytes + scalar_text + 10L,
    owned_wire_bytes: bytes,
  }
  @execution.compose_preparation_representation([
    parsed, snapshot, controls, wire_and_text,
  ])
}

///|
/// Retain the complete original body-construction peak alongside all previous
/// response/material/failed-child backing. The actual reader may drop it only
/// through its original retirement; no new body or callback proves that an
/// earlier one was physically returned. The caller must back quotation's fixed
/// controls BEFORE entry and call the SAME RowRun grow BEFORE allocation.
pub fn installed_table_source_body_capacity(
  previous : @execution.ExecutionCapacity,
  body_bytes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  guard installed_table_body_construction_inventory(body_bytes, max_depth)
    is Some(inventory) &&
    @execution.preparation_representation_cost(inventory) is Some(bytes) &&
    @execution.execution_capacity(bytes, bytes) is Some(body) else {
    return None
  }
  @execution.add_execution_capacity(previous, body)
}

///|
/// Existing common reader/RowRun controls plus the selected Table reader's
/// original stop/signal/handle and callback frame. Profile constructor DATA
/// comes from the SAME checked installation, not scalar capacity inputs. The
/// three outbound stages (payload snapshot, envelope preflight, send encoding)
/// conservatively keep their full original profile peaks live simultaneously.
pub fn installed_table_source_reader_capacity(
  columns : Int,
  profile : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  if columns < 1 {
    return None
  }
  let shared = installed_source_reader_fixed_retention_inventory()
  // Table shared reader environment1H20R8W, thirteen original helper/
  // handle/final-charge closures13H13R, four-method handle1H4R and original
  // stop-controller/signal2H1R. Factory environment1H9R1W, its original
  // record/methods3H5R and the pending physical callback view1H6R stay live.
  // Count that shared factory envelope per selected reader conservatively;
  // equal callback/source identity never discounts a concurrent reader.
  let reader : @execution.PreparationRepresentationUnits = {
    record_headers: 22L,
    reference_slots: 58L + 2L * columns.to_int64(),
    scalar_words: 9L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Factory's SAME managed-reader Set: one bounded original entry is
  // charged to EACH selected reader. The shared growth Map recipe covers
  // the entry/backing; no separate allocator or logical live-slot cap.
  guard @shape.map_construction_extent(1L, 1L) is Some(handles) else {
    return None
  }
  let held : @execution.PreparationRepresentationUnits = {
    record_headers: handles.record_headers,
    reference_slots: handles.reference_slots,
    scalar_words: handles.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([shared, reader, held])
    is Some(retained) else {
    return None
  }
  let collection = @shape.collection_construction_quotation_extent()
  let quote : @execution.PreparationRepresentationUnits = {
    record_headers: collection.record_headers,
    reference_slots: collection.reference_slots,
    scalar_words: collection.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      installed_source_reader_control_inventory(),
      quote,
    ])
    is Some(workspace) &&
    @execution.preparation_execution_capacity({
      retained,
      workspace,
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(base) else {
    return None
  }
  let peak = @execution.execution_capacity_execution_bytes(profile)
  guard @execution.execution_capacity_inventory(
      [{ unit: @execution.QuotedBytes, count: peak, copies: 3, }],
      [{ unit: @execution.QuotedBytes, count: peak, copies: 3, }],
      @execution.SeparateDimensions,
    )
    is Some(outbound) else {
    return None
  }
  @execution.add_execution_capacity(base, outbound)
}

///|
/// A complete native body bounds its projected JSON output before stringify.
/// Per original wire byte: at most six escaped text units plus a finite
/// number's 25 units and one punctuation unit. Keep the output String and
/// BOTH original Host/decoder Buffers; Common alone admits the actual rows.
pub fn installed_table_source_serialization_capacity(
  previous : @execution.ExecutionCapacity,
  original_body_bytes : Int,
) -> @execution.ExecutionCapacity? {
  if original_body_bytes < 1 {
    return None
  }
  let upper = 32L * original_body_bytes.to_int64() + 2L
  let output : @execution.PreparationRepresentationUnits = {
    record_headers: 3L,
    reference_slots: 2L,
    scalar_words: 2L,
    owned_utf16_units: upper,
    owned_wire_bytes: 2L * upper,
  }
  guard @execution.preparation_representation_cost(output) is Some(peak) &&
    @execution.execution_capacity(peak, peak) is Some(capacity) else {
    return None
  }
  @execution.add_execution_capacity(previous, capacity)
}

///|
/// The SAME Catalog snapshot's at-most-two three-field publication records.
/// Records count SQL rows, NOT business Table rows. Original UTF8 text, the
/// receipt/request trees and canonical hash views coexist. This quotes DATA
/// only; the original Source caller funds its fixed length-probe controls
/// before entry and grows its SAME RowRun before fetching/decoding payloads.
pub fn installed_table_source_record_capacity(
  previous : @execution.ExecutionCapacity,
  bytes : Int,
  records : Int,
) -> @execution.ExecutionCapacity? {
  if bytes < 0 || records < 0 || records > 2 || (records == 0 && bytes != 0) {
    return None
  }
  let count = records.to_int64()
  guard @shape.collection_construction_extent({
      // Original tuples and their three original String headers per record.
      records: 4L * count,
      record_references: 3L * count,
      record_words: 0L,
      // fetchmany(2) owns its bounded growing result, including spare/old
      // backing. Its scalar length rows belong to the prior fixed prelude.
      reference_arrays: 1L,
      reference_items: 2L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(original) else {
    return None
  }
  let text : @execution.PreparationRepresentationUnits = {
    record_headers: original.record_headers,
    reference_slots: original.reference_slots,
    scalar_words: original.scalar_words,
    owned_utf16_units: bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  // Zero/two records refuse before JSON. Empty invalid text also creates no
  // successful tree. Preserve their real tuple/control holdings nonetheless.
  let inventory = if records == 1 && bytes > 0 {
    guard @source.json_tree_retained_construction_extent(
        bytes,
        bytes - 1,
        bytes,
        0,
        bytes.to_int64(),
        keep_spans=false,
      )
      is Some(tree) else {
      return None
    }
    let decoded : @execution.PreparationRepresentationUnits = {
      record_headers: tree.record_headers,
      reference_slots: tree.reference_slots,
      scalar_words: tree.scalar_words,
      owned_utf16_units: tree.owned_utf16_units,
      owned_wire_bytes: 0L,
    }
    // Aggregate wire bytes bound BOTH original JSON inputs. Keep a second
    // complete structural envelope for filtered identity views and bounded
    // traversal/sort/failed-prefix alternatives, borrowing scalar text once.
    let views = { ..decoded, owned_utf16_units: 0L, }
    match
      @execution.compose_preparation_representation([text, decoded, views]) {
      Some(value) => value
      None => return None
    }
  } else {
    text
  }
  guard @execution.preparation_representation_cost(inventory) is Some(cost) &&
    @execution.execution_capacity(cost, cost) is Some(record) &&
    @execution.add_execution_capacity(previous, record) is Some(held) else {
    return None
  }
  if records != 1 || bytes == 0 {
    return Some(held)
  }
  // The existing two canonical identity computations own distinct output
  // String/encoded-Bytes views. Reuse their shared serializer quantity rather
  // than introducing another byte tariff or treating equal content as free.
  guard installed_table_source_serialization_capacity(held, bytes)
    is Some(receipt) else {
    return None
  }
  installed_table_source_serialization_capacity(receipt, bytes)
}

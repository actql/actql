///|
// Read-only variable workspace on the existing original Request capacity.
// No new Ledger, permission, serialized token or Host-wide quota is issued.
priv struct ClientRequestResultReadBudget {
  mut base_retention : Int64
  mut base_execution : Int64
  mut schema_cost : Int64
  max_row : Int
  max_nodes : Int
  mut window : Int
  mut row_units : Int
}

///|
fn result_read_data_cost(nodes : Int64, text : Int64, wire : Int64) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 4L * nodes,
    reference_slots: 8L * nodes,
    scalar_words: 4L * nodes,
    owned_utf16_units: text,
    owned_wire_bytes: wire,
  })
}

///|
fn result_read_window_cost(bytes : Int) -> Int64? {
  @execution.preparation_representation_cost({
    // Conservative common representation demand, including fragmented
    // immutable text, concatenation/flattening and its outgoing encoding.
    record_headers: bytes.to_int64(),
    reference_slots: bytes.to_int64(),
    scalar_words: 0L,
    owned_utf16_units: 2L * bytes.to_int64(),
    owned_wire_bytes: bytes.to_int64(),
  })
}

///|
/// The same READ Request has already paid its Common fixed controls. Reserve
/// only its next original metadata/frame/output work, not its policy maxima.
/// The caller supplies actual retained schema units and bounded payload extent.
pub fn[I] reserve_request_result_read(
  owner : ClientRequestPreparation[I],
  input : I,
  max_row : Int,
  frame : Int,
  schema_units : Int,
  max_nodes : Int,
  desired_window : Int,
) -> Result[Int, ClientRequestPreparationIssue] {
  guard owner.phase == Open &&
    owner.result_read is None &&
    !result_read_metadata_active(owner) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if max_row < 1 ||
    frame < 1 ||
    schema_units < 0 ||
    max_nodes < 1 ||
    desired_window < 1 {
    return Err(Policy)
  }
  let old = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  let schema = match
    result_read_data_cost(
      Int::min(schema_units, max_nodes).to_int64(),
      4L * schema_units.to_int64(),
      schema_units.to_int64(),
    ) {
    Some(value) => value
    None => return Err(Policy)
  }
  let frames = match
    @execution.preparation_representation_cost({
      record_headers: frame.to_int64(),
      reference_slots: frame.to_int64(),
      scalar_words: 0L,
      owned_utf16_units: 2L * max_row.to_int64() + frame.to_int64(),
      owned_wire_bytes: max_row.to_int64() + Int::min(frame, 65536).to_int64(),
    }) {
    Some(value) => value
    None => return Err(Policy)
  }
  // Original metadata, partial raw row, decoded frame and physical FD backing
  // coexist. The later row high-water grow precedes canonical parse/encoding.
  let base_r = old.0 + schema + frames
  let base_e = old.1 + schema + frames
  let limits = @resources.ledger_limits(owner.ledger)
  let usage = @resources.ledger_usage(owner.ledger)
  let available_r = limits.retained_bytes -
    usage.held_bytes -
    (usage.reserved_retention_bytes - old.0)
  let available_e = limits.execution_bytes -
    (usage.reserved_execution_bytes - old.1)
  let per_byte = result_read_window_cost(1).unwrap()
  let row_units = Int::min(32, max_row)
  let first_row = match
    result_read_data_cost(
      Int::min(row_units, max_nodes).to_int64(),
      6L * row_units.to_int64(),
      2L * row_units.to_int64(),
    ) {
    Some(value) => value
    None => return Err(Policy)
  }
  let spare = Int64::min(
    available_r - base_r - first_row,
    available_e - base_e - first_row,
  )
  // A real minimum grow remains authoritative even when no spare window fits.
  let window = if spare < per_byte {
    1
  } else {
    Int64::min(desired_window.to_int64(), spare / per_byte).to_int()
  }
  let output = result_read_window_cost(window).unwrap()
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    base_r + output + first_row,
    base_e + output + first_row,
  )
  owner.phase = Open
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      owner.result_read = Some({
        base_retention: base_r,
        base_execution: base_e,
        schema_cost: schema,
        max_row,
        max_nodes,
        window,
        row_units,
      })
      owner.phase = ResultRead
      Ok(window)
    }
  }
}

///|
/// Observe only the original bounded raw wire's code-unit extent. Geometric
/// growth, before its first parse/serialization, avoids a Resource call per row.
pub fn[I] grow_request_result_read_row(
  owner : ClientRequestPreparation[I],
  input : I,
  units : Int,
) -> Result[(Int, Int), ClientRequestPreparationIssue] {
  guard owner.phase == ResultRead &&
    owner.result_read is Some(read) &&
    !result_read_metadata_active(owner) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if units < 0 || units > read.max_row {
    return Err(Policy)
  }
  if units <= read.row_units {
    return Ok((read.row_units, read.window))
  }
  let high = Int::min(
    read.max_row,
    Int::max(
      units,
      if read.row_units > read.max_row / 2 {
        read.max_row
      } else {
        Int::max(32, read.row_units * 2)
      },
    ),
  )
  let row = match
    result_read_data_cost(
      Int::min(high, read.max_nodes).to_int64(),
      6L * high.to_int64(),
      2L * high.to_int64(),
    ) {
    Some(value) => value
    None => return Err(Policy)
  }
  let old = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  let limits = @resources.ledger_limits(owner.ledger)
  let usage = @resources.ledger_usage(owner.ledger)
  let spare = Int64::min(
    limits.retained_bytes -
    usage.held_bytes -
    (usage.reserved_retention_bytes - old.0) -
    read.base_retention -
    row,
    limits.execution_bytes -
    (usage.reserved_execution_bytes - old.1) -
    read.base_execution -
    row,
  )
  // The caller has flushed/disposed its old staged text before this boundary.
  // Prefer a smaller real window over a policy-sized whole-result allocation.
  let window = if spare < result_read_window_cost(1).unwrap() {
    1
  } else {
    Int64::min(
      read.window.to_int64(),
      spare / result_read_window_cost(1).unwrap(),
    ).to_int()
  }
  let output = result_read_window_cost(window).unwrap()
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    Int64::max(old.0, read.base_retention + output + row),
    Int64::max(old.1, read.base_execution + output + row),
  )
  owner.phase = ResultRead
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      read.row_units = high
      read.window = window
      Ok((high, window))
    }
  }
}

///|
/// The same serializer has finished its schema constructor. Replace its decode
/// peak by actual immutable representation observations; the Store's distinct
/// schema wire/fields remain on their existing metadata role.
pub fn[I] reconcile_request_result_read_serializer(
  owner : ClientRequestPreparation[I],
  input : I,
  serializer : @publication.ResultDeliverySerializer,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ResultRead &&
    owner.result_read is Some(read) &&
    !result_read_metadata_active(owner) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let extent = match
    @publication.result_delivery_serializer_extent(serializer) {
    Ok(value) => value
    Err(_) => return Err(Policy)
  }
  let tree = extent.schema
  let retained = match
    @execution.preparation_representation_cost({
      record_headers: 2L +
      3L * tree.nodes +
      tree.strings +
      tree.arrays +
      tree.objects +
      2L * tree.object_backing_slots,
      reference_slots: 8L +
      2L * tree.nodes +
      tree.array_backing_slots +
      3L * tree.object_backing_slots +
      extent.field_backing_slots,
      scalar_words: 6L + 2L * tree.nodes,
      owned_utf16_units: tree.text_utf16_units + extent.field_text_utf16_units,
      owned_wire_bytes: 0L,
    }) {
    Some(value) => value
    None => return Err(Policy)
  }
  if retained > read.schema_cost {
    return Err(Policy)
  }
  let old = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  let delta = read.schema_cost - retained
  owner.phase = Selecting
  let result = @resources.reconcile_working_preparation_phase(
    owner.capacity,
    input,
    old.0 - delta,
    old.1 - delta,
  )
  owner.phase = ResultRead
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      read.schema_cost = retained
      read.base_retention -= delta
      read.base_execution -= delta
      Ok(())
    }
  }
}

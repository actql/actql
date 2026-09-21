///|
/// Exact process-local read of one admitted Local input occurrence. This is
/// neither a producer completion nor a substitute for an imported result.
struct SuppliedRelationRead {
  identity : ProducerBindingIdentity
  receiver : @lower.BoundPrepared
  input_index : Int
  rows : CapturedRows
  available : () -> Bool
}

///|
/// Bind immutable captured rows to their exact checked Local input position.
/// The Host owns the liveness predicate and may only narrow access over time.
pub fn prepare_supplied_relation_read(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  rows : CapturedRows,
  available : () -> Bool,
) -> Result[SuppliedRelationRead, ProducerReadIssue] {
  if !available() {
    return Err(ProducerUnavailable)
  }
  if !physical_equal(captured_owner(rows), receiver) {
    return Err(ForeignReceiver)
  }
  guard captured_origin(rows) is SuppliedInput(actual) &&
    actual == input_index &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(receiver),
      @pipeline.Input(input_index),
    )
    is Some(schema) &&
    physical_equal(schema, captured_schema(rows)) else {
    return Err(InvalidProjection)
  }
  Ok({
    identity: { input_index, carrier: None, supplied: Some(rows), },
    receiver,
    input_index,
    rows,
    available,
  })
}

///|
pub fn supplied_relation_read_receiver(
  value : SuppliedRelationRead,
) -> @lower.BoundPrepared {
  value.receiver
}

///|
pub fn supplied_relation_read_input_index(value : SuppliedRelationRead) -> Int {
  value.input_index
}

///|
pub fn supplied_relation_read_available(value : SuppliedRelationRead) -> Bool {
  (value.available)()
}

///|
pub fn supplied_relation_read_same_binding(
  left : SuppliedRelationRead,
  right : SuppliedRelationRead,
) -> Bool {
  physical_equal(left.identity, right.identity) &&
  physical_equal(left.receiver, right.receiver) &&
  left.input_index == right.input_index
}

///|
pub fn supplied_relation_read_matches_input(
  value : SuppliedRelationRead,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> Bool {
  physical_equal(value.receiver, receiver) &&
  value.input_index == input_index &&
  supplied_relation_read_available(value)
}

///|
pub fn supplied_relation_read_matches_operation_input(
  value : SuppliedRelationRead,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  edge_index : Int,
) -> Bool {
  if !physical_equal(value.receiver, receiver) ||
    !supplied_relation_read_available(value) {
    return false
  }
  let prepared = @lower.bound_preparation(receiver)
  guard @lower.node_at(prepared, consumer_step) is Some(node) &&
    @lower.node_input_target(node, edge_index) is Some(@pipeline.Input(index)) else {
    return false
  }
  value.input_index == index
}

///|
pub fn supplied_relation_read_schema(
  value : SuppliedRelationRead,
) -> @schema.Schema {
  captured_schema(value.rows)
}

///|
pub fn supplied_relation_read_row_count(value : SuppliedRelationRead) -> Int {
  captured_row_count(value.rows)
}

///|
pub fn supplied_relation_read_cell(
  value : SuppliedRelationRead,
  row : Int,
  column : Int,
) -> @admitted.Value? {
  if supplied_relation_read_available(value) {
    captured_cell(value.rows, row, column)
  } else {
    None
  }
}

///|
pub fn supplied_relation_read_checked_cell(
  value : SuppliedRelationRead,
  row : Int,
  column : Int,
  limits : @admitted.Limits,
) -> @admitted.CheckedValue? {
  let schema = supplied_relation_read_schema(value)
  guard @schema.field_at(schema, column) is Some(field) &&
    supplied_relation_read_cell(value, row, column) is Some(cell) else {
    return None
  }
  @admitted.recheck_runtime_value(cell, field.contract, limits)
}

///|
fn supplied_relation_read_identity(
  value : SuppliedRelationRead,
) -> ProducerBindingIdentity {
  value.identity
}

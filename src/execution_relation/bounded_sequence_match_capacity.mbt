///|
// The selected bounded matcher borrows original flat Relation cells for key,
// identity and clock comparisons. Predicate inputs are borrowed bindings; only
// predicates whose EVERY intermediate is an inline Number/Bool/Null use this
// recipe. Events conversion and recursive/constructing predicates keep legacy
// capacity. No logical row/value/work or match limit is changed here.
fn bounded_sequence_match_constructor_nodes(
  generated : GeneratedSequence,
) -> Int? {
  guard generated_sequence_step_count(generated) == 1 &&
    generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_at(generated, 0)
    is Some(@lower.SequenceMatchStep(kernel)) &&
    !@lower.sequence_match_uses_timestamp(kernel) else {
    return None
  }
  let prepared = @lower.bound_preparation(generated_sequence_owner(generated))
  guard @lower.node_at(prepared, step) is Some(node) &&
    @lower.node_input_count(node) == 1 &&
    @lower.node_input_target(node, 0) is Some(target) &&
    @lower.preparation_carrier_at(prepared, target).map(value => {
      @carrier.kind(value)
    }) ==
    Some(@carrier.RelationKind) &&
    @lower.preparation_schema_at(prepared, target) is Some(input) &&
    @schema.lookup(input, @lower.sequence_match_time(kernel)) is Some(clock) &&
    clock.shape is @contract.Number else {
    return None
  }
  for field in 0..<@schema.field_count(input) {
    match @schema.field_at(input, field).unwrap().contract.shape {
      @contract.Number | @contract.Boolean | @contract.Text(_) => ()
      _ => return None
    }
  }
  let output = @lower.sequence_match_output_schema(kernel)
  for field in 0..<@schema.field_count(output) {
    match @schema.field_at(output, field).unwrap().contract.shape {
      @contract.Number | @contract.Boolean | @contract.Text(_) => ()
      _ => return None
    }
  }
  let mut nodes = Some(0)
  for pattern in 0..<@lower.sequence_match_pattern_count(kernel) {
    guard @lower.sequence_match_predicate(kernel, pattern) is Some(predicate) else {
      return None
    }
    nodes = bounded_alias_node_sum(
      nodes,
      bounded_inline_condition_nodes(predicate, false, 0),
      0,
    )
    if nodes is None {
      return None
    }
  }
  match nodes {
    Some(value) if value > 0 => nodes
    _ => None
  }
}

///|
/// Original bounded Sequence constructor DATA, not execution/authority evidence.
/// Output is not attached to generated.working, so its complete retained DATA
/// and all metadata roots remain prepaid. Only an input forest/measurement body
/// that this matcher never constructs is absent from the scratch recipe.
pub fn generated_bounded_sequence_match_capacity(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
  max_workspace_slots : Int,
) -> ExecutionCapacity? {
  guard max_workspace_slots >= 0 &&
    limits.max_frames >= 0 &&
    limits.max_work > 0 &&
    limits.rows.max_rows >= 0 &&
    limits.rows.operation_entries >= 0 &&
    bounded_sequence_match_constructor_nodes(generated) is Some(nodes) else {
    return None
  }
  // The record policy bounds matcher arrays, partial positions, comparison
  // cursors and predicate input slots. Predicate execution receives only the
  // REMAINING slots; its workspace cannot overlap a second full slot ceiling.
  let workspace = Int::max(limits.rows.operation_entries, max_workspace_slots)
  let selected = {
    ..limits,
    rows: { ..limits.rows, operation_entries: workspace, },
  }
  guard generated_sequence_capacity_with_roots(
      generated,
      selected,
      measurement,
      limits.rows.retained_entries.to_int64() +
      limits.rows.metadata_entries.to_int64(),
      limits.rows.metadata_entries.to_int64(),
      true,
      borrowed_input_values=true,
      bounded_measurement=true,
    )
    is Some(base) &&
    // All primitive predicate continuations borrow names/cells and can hold
    // at most one scalar result per original expression node. Keep the full
    // existing frame/depth/metadata slot terms and this independent value set.
    execution_capacity_inventory_add(
      base.execution_bytes,
      ValueNodeSlots,
      nodes.to_int64(),
      1,
    )
    is Some(execution) else {
    return None
  }
  execution_capacity(
    base.retained_bytes,
    Int64::max(base.retained_bytes, execution),
  )
}

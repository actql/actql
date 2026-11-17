///|
/// The direct ranking constructor borrows flat admitted input cells. Its
/// record/sort/fusion arrays, name/port maps and stepped recheck cursors all
/// share the original workspace-slot guard before allocation. It constructs
/// neither a decoded input forest nor a canonical measurement body. Retain
/// complete output DATA, fragment, metadata, frame and depth allowances.
pub fn generated_bounded_ranking_capacity(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
  max_workspace_slots : Int,
) -> ExecutionCapacity? {
  guard generated_sequence_step_count(generated) == 1 &&
    generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_at(generated, 0) is Some(@lower.VectorStep(_)) &&
    max_workspace_slots >= 0 &&
    limits.max_frames >= 0 &&
    limits.max_work > 0 &&
    limits.rows.operation_entries >= 0 else {
    return None
  }
  let prepared = @lower.bound_preparation(generated_sequence_owner(generated))
  guard @lower.node_at(prepared, step) is Some(node) &&
    @lower.operation(node) == "VEC.merge_rankings" &&
    @lower.node_input_count(node) > 0 else {
    return None
  }
  for port in -1..<@lower.node_input_count(node) {
    let target = if port < 0 {
      Some(@pipeline.Step(step))
    } else {
      @lower.node_input_target(node, port)
    }
    guard target.bind(target => @lower.preparation_schema_at(prepared, target))
      is Some(schema) else {
      return None
    }
    for field in 0..<@schema.field_count(schema) {
      match @schema.field_at(schema, field).unwrap().contract.shape {
        @contract.Number | @contract.Boolean | @contract.Text(_) => ()
        _ => return None
      }
    }
  }
  let selected = {
    ..limits,
    rows: {
      ..limits.rows,
      operation_entries: Int::max(
        limits.rows.operation_entries,
        max_workspace_slots,
      ),
    },
  }
  generated_sequence_capacity_with_roots(
    generated,
    selected,
    measurement,
    limits.rows.retained_entries.to_int64() +
    limits.rows.metadata_entries.to_int64(),
    limits.rows.metadata_entries.to_int64(),
    true,
    borrowed_input_values=true,
    bounded_measurement=true,
  ).bind(value => {
    execution_capacity(
      value.retained_bytes,
      Int64::max(value.retained_bytes, value.execution_bytes),
    )
  })
}

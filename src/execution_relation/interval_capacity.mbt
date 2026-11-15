///|
fn bounded_interval_scalar_schema(schema : @schema.Schema) -> Bool {
  if !@schema.all_fields_required(schema) {
    return false
  }
  for field in 0..<@schema.field_count(schema) {
    if !json_leaf_representation_contract(
        @schema.field_at(schema, field).unwrap().contract,
      ) {
      return false
    }
  }
  true
}

///|
/// Only the existing bounded Interval constructor borrows these original flat
/// cells. Its four clock arrays, maps, pending rows, comparisons and stepped
/// recheck cursors all reserve the same complete operation workspace. The full
/// output DATA and retained metadata stay prepaid and coexist with that scratch.
/// Recursive/reference/presence-bearing input declines this recipe so the
/// registered provider keeps its existing conservative quote and lifecycle.
pub fn generated_bounded_interval_capacity(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
  workspace_slots : Int,
) -> ExecutionCapacity? {
  if workspace_slots < 0 || limits.rows.operation_entries < workspace_slots {
    return None
  }
  guard generated_sequence_step_count(generated) == 1 &&
    generated_sequence_step_at(generated, 0)
    is Some(@lower.IntervalJoinStep(kernel)) &&
    generated_sequence_step_index_at(generated, 0) is Some(step) else {
    return None
  }
  guard generated_sequence_capacity(generated, limits, measurement)
    is Some(ordinary) else {
    return None
  }
  let owner = @lower.bound_preparation(
    @lower.sequence_owner(generated.sequence),
  )
  guard @lower.preparation_schema_at(owner, @pipeline.Step(step))
    is Some(output) else {
    return None
  }
  if !bounded_interval_scalar_schema(output) ||
    !bounded_interval_scalar_schema(
      @lower.interval_join_input_schema(kernel, true),
    ) ||
    !bounded_interval_scalar_schema(
      @lower.interval_join_input_schema(kernel, false),
    ) ||
    generated.contexts.any(context => {
      capacity_uses_fragment_step(generated, @lower.kernel_step(context.kernel))
    }) {
    return None
  }
  // The original admitted output is not attached to a metered-growth owner.
  // Retain its FULL old DATA/roots quote, including nullable output padding.
  // No copied input forest or canonical measurement body is constructed.
  execution_capacity_inventory(
    [{ unit: QuotedBytes, count: ordinary.retained_bytes, copies: 1, }],
    [
      {
        unit: CursorRootSlots,
        count: limits.rows.operation_entries.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: limits.rows.metadata_entries.to_int64(),
        copies: 1,
      },
      { unit: CursorRootSlots, count: limits.max_frames.to_int64(), copies: 1, },
      {
        unit: CursorRootSlots,
        count: measurement.max_depth.to_int64(),
        copies: 1,
      },
    ],
    RetainedAlongsideExecution,
  )
}

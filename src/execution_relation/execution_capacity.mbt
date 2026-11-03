///|
/// Logical retained/workspace allowance per value-node slot, not measured RSS.
/// The row-policy necessary bound and actual capacity calculator share this unit.
pub fn execution_capacity_node_bytes() -> Int64 {
  256L
}

///|
/// Host-private capacity allowances for the existing bounded row executor, not
/// measured heap/RSS or a replacement for any selected logical budget.
pub struct ExecutionCapacity {
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
pub fn execution_capacity(
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> ExecutionCapacity? {
  if retained_bytes < 0L || execution_bytes < retained_bytes {
    None
  } else {
    Some({ retained_bytes, execution_bytes, })
  }
}

///|
pub fn execution_capacity_retained_bytes(value : ExecutionCapacity) -> Int64 {
  value.retained_bytes
}

///|
pub fn execution_capacity_execution_bytes(value : ExecutionCapacity) -> Int64 {
  value.execution_bytes
}

///|
/// A selected sequence keeps the original context inventory for exact owner
/// validation, but only its selected operations can allocate fragment state.
fn capacity_uses_fragment_step(
  generated : GeneratedSequence,
  step : Int,
) -> Bool {
  if generated.selected_steps is None && generated.selected_prefix_end is None {
    return true
  }
  for index in 0..<generated_sequence_step_count(generated) {
    if generated_sequence_step_index_at(generated, index) == Some(step) {
      return true
    }
  }
  false
}

///|
pub fn generated_sequence_capacity(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
) -> ExecutionCapacity? {
  generated_sequence_capacity_with_roots(
    generated,
    limits,
    measurement,
    limits.rows.retained_entries.to_int64() +
    limits.rows.metadata_entries.to_int64(),
    limits.rows.metadata_entries.to_int64(),
  )
}

///|
/// Constructor-specific recipe for bounded Values, Append and binding-row
/// providers; not a claim about arbitrary executors of the same kernel.
/// The bounded single-operation constructors use an operation workspace, not
/// the legacy sequence wiring/table store. Their completed port retains exact
/// schema names and input identities. Keep a second metadata occurrence in
/// scratch; all operation, DATA, measurement and fragment allowances stay intact.
pub fn generated_bounded_sequence_capacity(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
) -> ExecutionCapacity? {
  guard generated.selected_steps is Some([step]) &&
    generated_sequence_step_at(generated, 0) is Some(operation) else {
    return generated_sequence_capacity(generated, limits, measurement)
  }
  match operation {
    @lower.ValuesStep(_) | @lower.AppendStep(_) | @lower.RowStep(_) => ()
    _ => return generated_sequence_capacity(generated, limits, measurement)
  }
  let prepared = @lower.bound_preparation(
    @lower.sequence_owner(generated.sequence),
  )
  guard @lower.node_at(prepared, step) is Some(node) &&
    completion_preparation_schema(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return generated_sequence_capacity(generated, limits, measurement)
  }
  let roots = @schema.field_count(schema).to_int64() +
    @lower.node_input_count(node).to_int64()
  generated_sequence_capacity_with_roots(
    generated, limits, measurement, roots, roots,
  )
}

///|
fn generated_sequence_capacity_with_roots(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
  retained_roots : Int64,
  metadata_scratch : Int64,
) -> ExecutionCapacity? {
  let rows = limits.rows
  if rows.retained_entries < 0 || rows.metadata_entries < 0 {
    return None
  }
  guard execution_capacity_inventory_bytes([
      { unit: CursorRootSlots, count: retained_roots, copies: 1, },
      {
        unit: ValueNodeSlots,
        count: rows.output_values.max_nodes.to_int64(),
        copies: 1,
      },
      {
        unit: DecodedTextBytes,
        count: rows.output_values.max_text_bytes.to_int64(),
        copies: 1,
      },
    ])
    is Some(retained) &&
    execution_capacity_inventory_bytes([
      {
        unit: CursorRootSlots,
        count: rows.operation_entries.to_int64(),
        copies: 1,
      },
      { unit: CursorRootSlots, count: metadata_scratch, copies: 1, },
      { unit: CursorRootSlots, count: limits.max_frames.to_int64(), copies: 1, },
      {
        unit: ValueNodeSlots,
        count: rows.input_values.max_nodes.to_int64(),
        copies: 1,
      },
      {
        unit: ValueNodeSlots,
        count: rows.output_values.max_nodes.to_int64(),
        copies: 1,
      },
      {
        unit: ValueNodeSlots,
        count: measurement.max_nodes.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: measurement.max_depth.to_int64(),
        copies: 1,
      },
      {
        unit: DecodedTextBytes,
        count: rows.input_values.max_text_bytes.to_int64(),
        copies: 1,
      },
      {
        unit: DecodedTextBytes,
        count: rows.output_values.max_text_bytes.to_int64(),
        copies: 1,
      },
      {
        unit: CanonicalWireBytes,
        count: measurement.max_bytes.to_int64(),
        copies: 1,
      },
    ])
    is Some(scratch) else {
    return None
  }
  // Fragments execute serially; their selected live-value and physical traversal
  // ceilings bound the transient frame/root allowance. Never lower those ceilings
  // to manufacture a fitting candidate, or use elapsed time as logical work.
  let mut fragment_peak = 0L
  for context in generated.contexts {
    if !capacity_uses_fragment_step(
        generated,
        @lower.kernel_step(context.kernel),
      ) {
      continue
    }
    let live = context.limits.max_live_value_bytes
    let physical = context.physical
    if live < 0L ||
      physical.max_body_nodes < 0 ||
      physical.max_body_bytes < 0 ||
      physical.max_body_depth < 0 {
      return None
    }
    guard execution_capacity_inventory_bytes([
        {
          unit: ValueNodeSlots,
          count: physical.max_body_nodes.to_int64(),
          copies: 1,
        },
        {
          unit: CursorRootSlots,
          count: physical.max_body_depth.to_int64(),
          copies: 1,
        },
        {
          unit: CanonicalWireBytes,
          count: physical.max_body_bytes.to_int64(),
          copies: 1,
        },
        // The existing live-byte envelope allows at most one node/root and
        // its wire allowance per logical byte; no observed-row reduction.
        { unit: ValueNodeSlots, count: live, copies: 1, },
        { unit: CanonicalWireBytes, count: live, copies: 1, },
      ])
      is Some(required) else {
      return None
    }
    if required > fragment_peak {
      fragment_peak = required
    }
  }
  guard execution_capacity_inventory_bytes([
      { unit: QuotedBytes, count: scratch, copies: 1, },
      { unit: QuotedBytes, count: fragment_peak, copies: 1, },
    ])
    is Some(execution) else {
    return None
  }
  // Preserve the original separate dimensions of this sequence quote. The
  // enclosing domain declares which retained components coexist at execution.
  Some({ retained_bytes: retained, execution_bytes: execution, })
}

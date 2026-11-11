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
    false,
  )
}

///|
// Immediate scalar cells are borrowed without an input tree conversion. The
// bounded reader still charges every original logical occurrence; temporary
// row arrays and expression roots remain with their existing workspace owner.
fn bounded_immediate_binding_schema(schema : @schema.Schema) -> Bool {
  if !@schema.all_fields_required(schema) {
    return false
  }
  for index in 0..<@schema.field_count(schema) {
    match @schema.field_at(schema, index).unwrap().contract.shape {
      @contract.Number | @contract.Boolean => ()
      _ => return false
    }
  }
  true
}

///|
// The bounded direct COUNT/COUNT_IF reader borrows required immediate cells,
// including nullable scalars. Its sorter/group/aggregate cursors are charged
// to operation_entries; it does not construct a separate input value forest.
// Resolving a direct field and testing NULL/Bool use the same bounded cursor.
// Keep recursive/text/presence and expression aggregates on the full recipe.
fn bounded_count_group_borrows_input(kernel : @lower.PreparedKernel) -> Bool {
  guard @lower.kernel_count_group(kernel) is Some(group) &&
    @lower.count_group_aggregate_count(group) > 0 &&
    bounded_immediate_binding_schema(@lower.kernel_input_schema(kernel)) &&
    bounded_immediate_binding_schema(@lower.kernel_output_schema(kernel)) else {
    return false
  }
  true
}

///|
// The bounded INNER JOIN compares only its checked immediate key columns.
// Other required columns are carried as original immutable cells: neither
// binary input scan nor projected output constructs their value forest.
fn bounded_inner_join_borrows_input(kernel : @lower.PreparedJoinKernel) -> Bool {
  let owner = @lower.bound_preparation(@lower.join_kernel_owner(kernel))
  let step = @lower.join_kernel_step(kernel)
  let profile = @lower.join_kernel_profile(kernel)
  guard @lower.inner_join_kind(profile) == @join.Inner &&
    @lower.inner_join_key_count(profile) > 0 &&
    @lower.node_at(owner, step) is Some(node) &&
    @lower.node_input_count(node) == 2 &&
    @lower.preparation_schema_at(owner, @pipeline.Step(step)).map(
      @schema.all_fields_required,
    ) ==
    Some(true) else {
    return false
  }
  for port in 0..<2 {
    guard @lower.node_input_target(node, port).bind(target => {
        @lower.preparation_schema_at(owner, target)
      })
      is Some(schema) &&
      @schema.all_fields_required(schema) else {
      return false
    }
    for index in 0..<@lower.inner_join_key_count(profile) {
      guard @lower.inner_join_key_at(profile, index) is Some((left, right)) &&
        @schema.lookup(schema, if port == 0 { left } else { right })
        is Some(contract) else {
        return false
      }
      match contract.shape {
        @contract.Number | @contract.Boolean => ()
        _ => return false
      }
    }
  }
  true
}

///|
/// Constructor-specific recipe for bounded Values, Append, primitive Set/Join,
/// INNER JOIN with immediate keys, required-field CROSS JOIN, scalar grouped
/// COUNT, UNNEST and binding-row
/// providers; not a claim about
/// arbitrary executors of the same kernel.
/// The bounded single-operation constructors use an operation workspace, not
/// the legacy sequence wiring/table store. Their completed port retains exact
/// schema names and input identities. Keep a second metadata occurrence in
/// scratch; all operation, DATA, measurement and fragment allowances stay intact.
pub fn generated_bounded_sequence_capacity(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
) -> ExecutionCapacity? {
  guard generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_index_at(generated, 1) is None &&
    (
      generated.selected_steps is Some([_]) ||
      generated_sequence_step_at(generated, 0) is Some(@lower.ValuesStep(_))
    ) &&
    generated_sequence_step_at(generated, 0) is Some(operation) else {
    return generated_sequence_capacity(generated, limits, measurement)
  }
  match operation {
    @lower.ValuesStep(_)
    | @lower.AppendStep(_)
    | @lower.SetStep(_)
    | @lower.JoinStep(_)
    | @lower.CrossJoinStep(_)
    | @lower.RowStep(_) => ()
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
  let borrowed_group = match operation {
    @lower.RowStep(kernel) => bounded_count_group_borrows_input(kernel)
    _ => false
  }
  if operation is @lower.RowStep(kernel) &&
    @lower.kernel_count_group(kernel) is Some(_) &&
    !borrowed_group {
    return generated_sequence_capacity(generated, limits, measurement)
  }
  let borrowed_unnest = match operation {
    @lower.RowStep(kernel) =>
      @lower.kernel_unnest(kernel) is Some(_) &&
      @schema.all_fields_required(@lower.kernel_input_schema(kernel)) &&
      @schema.all_fields_required(schema)
    _ => false
  }
  if operation is @lower.RowStep(kernel) &&
    @lower.kernel_unnest(kernel) is Some(_) &&
    !borrowed_unnest {
    return generated_sequence_capacity(generated, limits, measurement)
  }
  // The bounded UNPIVOT input and output checks retain original admitted
  // cells. Its RowWorkspace funds maps, rows and resumable cursor frames;
  // no input forest or canonical measurement body is constructed here.
  let borrowed_unpivot = match operation {
    @lower.RowStep(kernel) =>
      @lower.kernel_unpivot_outputs(kernel) is Some(_) &&
      @schema.all_fields_required(@lower.kernel_input_schema(kernel)) &&
      @schema.all_fields_required(schema)
    _ => false
  }
  // Bounded numeric PIVOT scans original required scalar cells, including
  // the immutable text axis. It keeps aggregate/order scratch and the full
  // retained output; it constructs no copied input or measurement forest.
  let borrowed_pivot = match operation {
    @lower.RowStep(kernel) if @lower.kernel_pivot(kernel) is Some(_) => {
      let input = @lower.kernel_input_schema(kernel)
      let mut borrowed = @schema.all_fields_required(input) &&
        @schema.all_fields_required(schema)
      for field in 0..<@schema.field_count(input) {
        match @schema.field_at(input, field).unwrap().contract.shape {
          @contract.Number | @contract.Boolean | @contract.Text(_) => ()
          _ => borrowed = false
        }
      }
      for field in 0..<@schema.field_count(schema) {
        match @schema.field_at(schema, field).unwrap().contract.shape {
          @contract.Number | @contract.Boolean => ()
          _ => borrowed = false
        }
      }
      borrowed
    }
    _ => false
  }
  let borrowed_row = match operation {
    @lower.RowStep(kernel) => {
      let bounded = @lower.kernel_bindings(kernel) is Some(_) ||
        (match @lower.kernel_body(kernel) {
          @lower.Filter(_)
          | @lower.Select(_)
          | @lower.DistinctRows
          | @lower.StableSort(_)
          | @lower.Limit(_, _, _)
          | @lower.AssertAll(_)
          | @lower.AssertUnique(_) => true
          _ => false
        })
      (
        bounded ||
        borrowed_group ||
        borrowed_unnest ||
        borrowed_unpivot ||
        borrowed_pivot
      ) &&
      @lower.node_input_count(node) == 1 &&
      // Only the input forest is borrowed. A binding may construct recursive
      // output through its existing logical-root growth owner; its complete
      // output and fragment-live envelopes remain prepaid below.
      @lower.node_input_target(node, 0)
      .bind(target => @lower.preparation_schema_at(prepared, target))
      .map(input => {
        bounded_immediate_binding_schema(input) ||
        // Binding snapshots and these forwarding constructors borrow the
        // original immutable cells. Recursive recheck returns the same value,
        // not an input tree copy. Preserve the complete independent output
        // and recheck/traversal inventories.
        (
          (
            @lower.kernel_bindings(kernel) is Some(_) ||
            @lower.kernel_body(kernel) is @lower.StableSort(_) ||
            @lower.kernel_body(kernel) is @lower.Select(_) ||
            // UNNEST scans original arrays and rechecks the same immutable
            // carried/element values. Its maps, row arrays, complete input
            // charge and recheck/measurement cursors remain funded below.
            borrowed_unnest ||
            // UNPIVOT borrows kept and selected original cells, including
            // recursive values, and immutable prepared column labels.
            borrowed_unpivot ||
            borrowed_pivot
          ) &&
          @schema.all_fields_required(input) &&
          @schema.all_fields_required(schema)
        )
      })
      .unwrap_or(false)
    }
    _ => false
  }
  // The bounded CROSS JOIN scans both original ProducerReads with its
  // operation workspace. It constructs names/column maps and output row
  // arrays, but rechecks the same immutable cells without copying input DATA.
  let cross = operation is @lower.CrossJoinStep(_)
  let mut borrowed_cross = cross &&
    @lower.node_input_count(node) == 2 &&
    @schema.all_fields_required(schema)
  if borrowed_cross {
    for index in 0..<2 {
      if @lower.node_input_target(node, index)
        .bind(target => @lower.preparation_schema_at(prepared, target))
        .map(@schema.all_fields_required)
        .unwrap_or(false) ==
        false {
        borrowed_cross = false
      }
    }
  }
  if cross && !borrowed_cross {
    return generated_sequence_capacity(generated, limits, measurement)
  }
  let borrowed_join = match operation {
    @lower.JoinStep(kernel) => bounded_inner_join_borrows_input(kernel)
    _ => false
  }
  let binary = operation is @lower.SetStep(_) || operation is @lower.JoinStep(_)
  let mut borrowed_binary = binary &&
    @lower.node_input_count(node) == 2 &&
    bounded_immediate_binding_schema(schema)
  if borrowed_binary {
    for index in 0..<2 {
      if @lower.node_input_target(node, index)
        .bind(target => @lower.preparation_schema_at(prepared, target))
        .map(bounded_immediate_binding_schema)
        .unwrap_or(false) ==
        false {
        borrowed_binary = false
      }
    }
  }
  // Unsupported binary shapes keep the full existing envelope. Immediate
  // Set/Join inputs and the checked INNER JOIN's carried DATA are borrowed;
  // every logical occurrence still uses the bounded charged input scan.
  if binary && !borrowed_binary && !borrowed_join {
    return generated_sequence_capacity(generated, limits, measurement)
  }
  let roots = @schema.field_count(schema).to_int64() +
    @lower.node_input_count(node).to_int64()
  let ordinary = generated_sequence_capacity_with_roots(
    generated,
    limits,
    measurement,
    roots,
    roots,
    true,
    borrowed_input_values=operation is @lower.AppendStep(_) ||
      borrowed_row ||
      borrowed_binary ||
      borrowed_cross ||
      borrowed_join,
    // Append uses the same workspace-funded binary input scan as CROSS JOIN;
    // its constructor receives no physical measurement forest or wire buffer.
    bounded_measurement=(borrowed_row && !borrowed_group) ||
      operation is @lower.AppendStep(_) ||
      borrowed_cross ||
      borrowed_join,
  )
  guard ordinary is Some(ordinary) else { return None }
  // The Values provider does not pass FixedInputGuardMeasureLimits to its
  // constructor. Its original admitted Number/Boolean cells are borrowed;
  // bounded_values_step uses the scalar measure/recheck branch, without a
  // copied input tree, stepped-measure cursor or output-recheck tree. Keep
  // the complete accumulated output in retained (and the driver's independent
  // copy), plus all operation/frame/metadata slots and the current row roots.
  // This changes constructor DATA only; all cumulative input/output budgets
  // and failures still execute. Other schemas/providers keep the old quote.
  if generated_sequence_step_at(generated, 0) is Some(@lower.ValuesStep(_)) &&
    limits.max_frames > 0 &&
    limits.rows.operation_entries.to_int64() >=
    @schema.field_count(schema).to_int64() + 2L &&
    !generated.contexts.any(context => {
      capacity_uses_fragment_step(generated, @lower.kernel_step(context.kernel))
    }) {
    let mut primitive = true
    for index in 0..<@schema.field_count(schema) {
      guard @schema.field_at(schema, index) is Some(field) else { return None }
      match @schema.field_contract(field).shape {
        @contract.Number | @contract.Boolean => ()
        _ => primitive = false
      }
    }
    if primitive && @schema.field_count(schema) > 0 {
      guard execution_capacity_inventory_bytes([
          {
            unit: CursorRootSlots,
            count: limits.rows.operation_entries.to_int64(),
            copies: 1,
          },
          { unit: CursorRootSlots, count: roots, copies: 1, },
          {
            unit: CursorRootSlots,
            count: limits.max_frames.to_int64(),
            copies: 1,
          },
          {
            unit: CursorRootSlots,
            count: 2L * @schema.field_count(schema).to_int64() + 2L,
            copies: 1,
          },
        ])
        is Some(execution) else {
        return None
      }
      guard @lower.node_values_row_count(node) is Some(count) &&
        count >= 0 &&
        checked_preparation_add_product(
          count.to_int64(),
          count.to_int64(),
          @schema.field_count(schema).to_int64(),
        )
        is Some(items) &&
        preparation_array_representation(count.to_int64() + 1L, items, true)
        is Some(rows) &&
        preparation_representation_cost(rows) is Some(row_bytes) else {
        return None
      }
      // Commit retains the SAME checked primitive cells in one array per
      // original row and the outer row array; it creates no copied value/text
      // forest. Include their shared growth inventory, original completion
      // roots and the retained execution owner's fixed/cursor envelope. That
      // owner remains reachable until its existing cleanup acknowledges it.
      // Active workspace coexists with this retained output; the canonical
      // constructor preserves execution >= retention for every later caller.
      return execution_capacity_inventory(
        [
          { unit: QuotedBytes, count: row_bytes, copies: 1, },
          { unit: CursorRootSlots, count: roots, copies: 1, },
          { unit: QuotedBytes, count: execution, copies: 1, },
        ],
        [{ unit: QuotedBytes, count: execution, copies: 1, }],
        RetainedAlongsideExecution,
      )
    }
  }
  Some(ordinary)
}

///|
fn generated_sequence_capacity_with_roots(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
  retained_roots : Int64,
  metadata_scratch : Int64,
  bounded_single : Bool,
  borrowed_input_values? : Bool = false,
  bounded_measurement? : Bool = false,
) -> ExecutionCapacity? {
  let rows = limits.rows
  if rows.retained_entries < 0 ||
    rows.metadata_entries < 0 ||
    rows.input_values.max_nodes < 0 ||
    rows.input_values.max_text_bytes < 0 ||
    measurement.max_nodes < 0 ||
    measurement.max_bytes < 0 {
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
        // The selected bounded constructor scans original input cells;
        // its cursor stack is already bounded by operation_entries. It does
        // not copy the input value forest. Logical input admission still
        // scans and charges every occurrence before any output is committed.
        count: if borrowed_input_values {
          0L
        } else {
          rows.input_values.max_nodes.to_int64()
        },
        copies: 1,
      },
      {
        unit: ValueNodeSlots,
        count: rows.output_values.max_nodes.to_int64(),
        copies: 1,
      },
      {
        unit: ValueNodeSlots,
        // Bounded row/UNNEST constructors use SteppedValueMeasure over the
        // same immutable cells. Every continuation reserves a RowWorkspace
        // slot before allocation; operation_entries funds those slots above.
        // No physical-measurement value forest is constructed on this path.
        count: if bounded_measurement {
          0L
        } else {
          measurement.max_nodes.to_int64()
        },
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: measurement.max_depth.to_int64(),
        copies: 1,
      },
      {
        unit: DecodedTextBytes,
        count: if borrowed_input_values {
          0L
        } else {
          rows.input_values.max_text_bytes.to_int64()
        },
        copies: 1,
      },
      {
        unit: DecodedTextBytes,
        count: rows.output_values.max_text_bytes.to_int64(),
        copies: 1,
      },
      {
        unit: CanonicalWireBytes,
        // The same stepped traversal charges the logical text/work budgets
        // without encoding a second canonical body. Output, recheck, fragment
        // and depth inventories remain independent of this unused buffer.
        count: if bounded_measurement {
          0L
        } else {
          measurement.max_bytes.to_int64()
        },
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
    // Only the selected bounded constructor can use the borrowed-leaf proof.
    // Unknown expressions and all generic sequence paths retain the original
    // live-value envelope; neither case changes its actual logical guards.
    let leaf = if bounded_single {
      bounded_leaf_fragment_capacity(generated, context, limits)
    } else {
      None
    }
    let live_capacity = match leaf {
      Some(bytes) => Some(bytes)
      None =>
        execution_capacity_inventory_bytes([
          { unit: ValueNodeSlots, count: live, copies: 1, },
          { unit: CanonicalWireBytes, count: live, copies: 1, },
        ])
    }
    guard live_capacity is Some(live_capacity) else { return None }
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
        { unit: QuotedBytes, count: live_capacity, copies: 1, },
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

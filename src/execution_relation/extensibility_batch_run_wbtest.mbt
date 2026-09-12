///|
priv struct ExtBatchOutputRow {
  read : ExtBatchRead
  plan : ExtBatchPlan
}

///|
impl RowValues for ExtBatchOutputRow with fn value_count(self) {
  self.plan.output_addresses.length()
}

///|
impl RowValues for ExtBatchOutputRow with fn value_at(self, column) {
  ext_batch_read(self.read, self.plan.output_addresses[column])
}

///|
priv struct ExtBatchTrace {
  mut chunks : Int
  mut selected : Int
  mut rejected : Int
}

///|
// Strategy is fixed before execution. An error from either strategy is final.
fn ext_run_choice(
  choice : ExtBatchChoice,
  input : LayoutRelation,
  width : Int,
  logical : LogicalBudget,
  physical : LayoutAllocation,
  trace : ExtBatchTrace,
) -> Result[LayoutStorage, RowIssue] {
  match choice {
    Typed(plan) => ext_run_batch(plan, input, width, logical, physical, trace)
    Row(kernel) => {
      let schema = @relation.output_schema(@lower.kernel_checked(kernel))
      let count = @schema.field_count(schema)
      if !reserve_slots(physical.slots, count) ||
        !spend_control(physical.work, count) {
        return Err(RowLimit)
      }
      let names = Array::makei(count, i => {
        @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
      })
      let builder = match
        layout_column_builder(
          schema,
          names,
          input.storage.count,
          TypedColumns,
          physical,
        ) {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      // The existing evaluator owns a fresh scratch workspace. Reserve its
      // entire ceiling alongside the already retained producer/builder storage;
      // do not reset or reuse the enclosing live-allocation counter.
      let available = physical.slots.limit - physical.slots.live
      let scratch = { limit: available, live: 0, peak: 0, }
      if !reserve_slots(physical.slots, available) {
        abort_layout_columns(builder)
        return Err(RowLimit)
      }
      let result = evaluate_row_body_into(
        PreparedBody(kernel),
        input,
        input.storage.count,
        physical.work,
        row_output(),
        scratch,
        fn(row, _source, _names, _projection) {
          append_layout_row(builder, row)
        },
        ordered_budget=Some(logical),
      )
      release_slots(physical.slots, available)
      match result {
        Ok(_) => finish_layout_columns(builder)
        Err(e) => {
          abort_layout_columns(builder)
          Err(e)
        }
      }
    }
  }
}

///|
priv struct ExtBatchBuffers {
  columns : Array[LayoutColumn]
  owners : Array[LayoutOwnedBuffer[LayoutColumn]]
  masks : Array[LayoutOwnedBuffer[FixedArray[Byte]]]
}

///|
fn ext_batch_release(buffers : ExtBatchBuffers) -> Unit {
  buffers.columns.clear()
  for b in buffers.owners {
    ignore(release_owned_layout_buffer(b.lease.buffer.ledger, b))
  }
  for b in buffers.masks {
    ignore(release_owned_layout_buffer(b.lease.buffer.ledger, b))
  }
  buffers.owners.clear()
  buffers.masks.clear()
}

///|
fn ext_batch_buffers(
  plan : ExtBatchPlan,
  count : Int,
  ledger : LayoutLedger,
) -> Result[ExtBatchBuffers, RowIssue] {
  let buffers : ExtBatchBuffers = { columns: [], owners: [], masks: [], }
  for (_, expr) in plan.bindings {
    let numeric = @lower.expression_contract(expr).shape is @contract.Number
    let unit = if numeric { 9 } else { 2 }
    if count > 2147483647 / unit || !spend_control(ledger.work, count) {
      ext_batch_release(buffers)
      return Err(RowLimit)
    }
    let owner = match
      allocate_owned_layout_buffer(ledger, 3, count * unit, fn() {
        if numeric {
          Numeric(FixedArray::make(count, 0.0), FixedArray::make(count, 0))
        } else {
          Flags(FixedArray::make(count, 0), FixedArray::make(count, 0))
        }
      }) {
      Ok(b) => b
      Err(_) => {
        ext_batch_release(buffers)
        return Err(RowLimit)
      }
    }
    buffers.owners.push(owner)
    buffers.columns.push(owner.value.unwrap())
    let mask = match
      allocate_owned_layout_buffer(ledger, 1, count, fn() {
        FixedArray::make(count, (2 : Byte))
      }) {
      Ok(b) => b
      Err(_) => {
        ext_batch_release(buffers)
        return Err(RowLimit)
      }
    }
    buffers.masks.push(mask)
  }
  Ok(buffers)
}

///|
fn ext_batch_write(column : LayoutColumn, row : Int, value : Value) -> Bool {
  match (column, value) {
    (Numeric(values, valid), Number(n)) => {
      values[row] = n
      valid[row] = 1
      true
    }
    (Flags(values, valid), Boolean(b)) => {
      values[row] = if b { 1 } else { 0 }
      valid[row] = 1
      true
    }
    (Numeric(_, valid), Null) | (Flags(_, valid), Null) => {
      valid[row] = 0
      true
    }
    _ => false
  }
}

///|
// A restricted, row-major typed batch kernel. It executes the preselected
// bounded programs, not ExpressionFrame nor the existing row evaluator.
// Shared expression events and root helpers own the semantic accounting.
fn ext_run_batch(
  plan : ExtBatchPlan,
  input : LayoutRelation,
  width : Int,
  logical : LogicalBudget,
  physical : LayoutAllocation,
  trace : ExtBatchTrace,
) -> Result[LayoutStorage, RowIssue] {
  if !physical_equal(@lower.kernel_owner(plan.kernel), input.owner) {
    return Err(OwnerMismatch)
  }
  if @lower.kernel_input(plan.kernel) != input.id {
    return Err(InputMismatch)
  }
  if input.names != plan.input_names ||
    input.storage.width != plan.input_names.length() ||
    width <= 0 {
    return Err(InvalidRows)
  }
  guard physical.ledger is Some(_) else { return Err(InvalidRowLimits) }
  let metadata = physical.slots
  let count = input.storage.count
  if !reserve_slots(metadata, count) ||
    !reserve_slots(metadata, plan.bindings.length()) {
    return Err(RowLimit)
  }
  let scope : ExpressionRoots = {
    budget: logical,
    slots: [],
    free: [],
    limit: metadata.limit,
  }
  let builder = match
    layout_column_builder(
      @relation.output_schema(@lower.kernel_checked(plan.kernel)),
      plan.names,
      count,
      TypedColumns,
      physical,
    ) {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  let result = ext_run_batch_impl(
    plan, input, width, physical, trace, scope, builder,
  )
  cleanup_expression_roots(scope)
  match result {
    Err(issue) => {
      logical.failed = true
      abort_layout_columns(builder)
      Err(issue)
    }
    Ok(_) => finish_layout_columns(builder)
  }
}

///|
fn ext_run_batch_impl(
  plan : ExtBatchPlan,
  input : LayoutRelation,
  width : Int,
  physical : LayoutAllocation,
  trace : ExtBatchTrace,
  scope : ExpressionRoots,
  builder : LayoutColumnBuilder,
) -> Result[Unit, RowIssue] {
  let b = scope.budget
  let count = input.storage.count
  let control = physical.work
  match admit_logical_rows(b, count.to_int64()) {
    Err(e) => return Err(LogicalRows(e))
    Ok(_) => ()
  }
  let roots : Array[ExpressionRootLease] = []
  for row in 0..<count {
    if !spend_control(control, input.names.length() + 1) {
      return Err(RowLimit)
    }
    let root = match
      retain_logical_row(b, input.names, IndexedRow::{ table: input, row, }) {
      Ok(root) => root
      Err(e) => return Err(LogicalRows(e))
    }
    match register_scope_root(scope, root) {
      Ok(root) => roots.push(root)
      Err(e) => return Err(LogicalRows(e))
    }
  }
  let output_values = row_output()
  let mut start = 0
  while start < count {
    let n = Int::min(width, count - start)
    let buffers = match ext_batch_buffers(plan, n, physical.ledger.unwrap()) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    trace.chunks += 1
    let result = ext_run_batch_chunk(
      plan, input, start, n, physical, trace, scope, roots, builder, buffers, output_values,
    )
    ext_batch_release(buffers)
    match result {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    start += n
  }
  Ok(())
}

///|
fn ext_run_batch_chunk(
  plan : ExtBatchPlan,
  input : LayoutRelation,
  start : Int,
  count : Int,
  physical : LayoutAllocation,
  trace : ExtBatchTrace,
  scope : ExpressionRoots,
  input_roots : Array[ExpressionRootLease],
  builder : LayoutColumnBuilder,
  buffers : ExtBatchBuffers,
  output_values : ValueBudget,
) -> Result[Unit, RowIssue] {
  let b = scope.budget
  for lane in 0..<count {
    let row = start + lane
    if !spend_control(physical.work, 1) {
      return Err(RowLimit)
    }
    match charge_logical_work(b, 1L) {
      Err(e) => return Err(LogicalRows(e))
      Ok(_) => ()
    }
    let read : ExtBatchRead = { input, row, slots: buffers.columns, lane, }
    let slot_roots : Array[ExpressionRootLease] = []
    for slot in 0..<plan.programs.length() {
      match charge_logical_work(b, 1L) {
        Err(e) => return Err(LogicalRows(e))
        Ok(_) => ()
      }
      let expression_scope = expression_roots(b, 100)
      let mask = buffers.masks[slot].value.unwrap()
      let evaluated = ext_batch_eval(
        plan.programs[slot],
        read,
        expression_scope,
        physical.work,
        mask,
      )
      let detached = match evaluated {
        Err(e) => {
          cleanup_expression_roots(expression_scope)
          return Err(Evaluation(row, slot, e))
        }
        Ok(value) => {
          guard value.root is Some(root) else {
            cleanup_expression_roots(expression_scope)
            return Err(InvalidRows)
          }
          let root = match detach_expression_root(root) {
            Ok(root) => root
            Err(e) => {
              cleanup_expression_roots(expression_scope)
              return Err(LogicalRows(e))
            }
          }
          cleanup_expression_roots(expression_scope)
          (value.value, root)
        }
      }
      let lease = match register_scope_root(scope, detached.1) {
        Ok(root) => root
        Err(e) => return Err(LogicalRows(e))
      }
      slot_roots.push(lease)
      if !ext_batch_write(buffers.columns[slot], lane, detached.0) {
        return Err(InvalidRows)
      }
      if mask[lane] == 1 {
        trace.selected += 1
      } else if mask[lane] == 0 {
        trace.rejected += 1
      }
    }
    let output = ExtBatchOutputRow::{ read, plan, }
    if !retain_row(output, plan.names, output_values) {
      return Err(RowLimit)
    }
    match
      row_event_output(scope, plan.names, output, slot_roots, input_roots[row]) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    match append_layout_values(builder, output) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok(())
}

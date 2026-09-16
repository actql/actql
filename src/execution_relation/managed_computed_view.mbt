///|
/// Provisional validation/measurement of only newly computed output columns.
/// Unchanged columns use copied occurrence metadata, never a value reader.
struct ManagedComputedView[T] {
  selection : ManagedViewSelection[T]
  schema : @schema.Schema
  budget : ValueBudget
  measurement : FixedInputGuardBudget
  ceiling : Int
  mut row : Int
  mut open : Bool
  mut reading : Bool
  mut issue : ManagedOutputValueIssue?
}

///|
/// `values` and `measurement` bound this builder's actual admission work on
/// new columns. They do not replace the complete consumer/output logical
/// ledger, which the output issuer must still enforce for every column.
pub fn[T] prepare_managed_computed_view(
  plan : ManagedViewPlan[T],
  rows : Array[Int],
  max_cells : Int,
  max_metadata_work : Int,
  values : ValueLimits,
  max_value_bytes : Int,
  measurement : FixedInputGuardMeasureLimits,
) -> Result[ManagedComputedView[T], ManagedComputedViewIssue] {
  if max_value_bytes < 0 ||
    measurement.max_work < 0 ||
    measurement.max_bytes < 0 ||
    measurement.max_nodes < 0 ||
    measurement.max_depth < 0 {
    return Err(Values(Guard(InvalidLimits)))
  }
  let budget = match value_budget(values) {
    Ok(value) => value
    Err(issue) => return Err(Values(Admission(issue)))
  }
  let selection = match
    prepare_managed_view_selection_base(
      plan, rows, max_cells, max_metadata_work, true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Selection(issue))
  }
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(plan.input.receiver),
    plan.target,
  ).unwrap()
  Ok({
    selection,
    schema,
    budget,
    measurement: {
      work: measurement.max_work,
      bytes: measurement.max_bytes,
      nodes: measurement.max_nodes,
      depth: measurement.max_depth,
    },
    ceiling: max_value_bytes,
    row: 0,
    open: true,
    reading: false,
    issue: None,
  })
}

///|
pub(all) enum ManagedComputedViewIssue {
  Selection(ManagedSelectionMeasureIssue)
  Values(ManagedOutputValueIssue)
  // Provisional measurement witness. The caller must resolve the complete
  // output ledger/precedence before treating it as the final diagnostic.
  NeedsOrderedMeasurement(FixedInputGuardIssue)
  RowCount
  Closed
}

///|
pub fn[T] managed_computed_view_schema(
  value : ManagedComputedView[T],
) -> @schema.Schema {
  value.schema
}

///|
/// Original receiving column for an unchanged output column; None for new
/// values or an out-of-range column. Not proof of actual native execution.
pub fn[T] managed_computed_view_source_column(
  value : ManagedComputedView[T],
  column : Int,
) -> Int? {
  managed_view_plan_column(value.selection.plan, column)
}

///|
pub fn[T] cancel_managed_computed_view(value : ManagedComputedView[T]) -> Bool {
  if !value.open {
    return false
  }
  value.open = false
  discard_managed_row_measurements(value.selection.index)
  true
}

///|
/// Read callback is invoked only for new-value columns, in canonical output
/// order. Checked values must carry this exact output field contract.
pub fn[T] append_managed_computed_view(
  value : ManagedComputedView[T],
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[Unit, ManagedComputedViewIssue] {
  if !value.open || value.reading {
    return Err(Closed)
  }
  if value.row >= value.selection.rows.length() {
    cancel_managed_computed_view(value) |> ignore
    return Err(RowCount)
  }
  value.reading = true
  let result = append_managed_computed_view_row(value, read)
  value.reading = false
  if result is Err(_) {
    cancel_managed_computed_view(value) |> ignore
  }
  result
}

///|
fn[T] append_managed_computed_view_row(
  value : ManagedComputedView[T],
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[Unit, ManagedComputedViewIssue] {
  if !charge_node(value.budget, 1) {
    return Err(Values(Admission(CaptureLimit)))
  }
  let width = value.selection.plan.columns.length()
  for column, origin in value.selection.plan.columns {
    if origin is Some(_) {
      // Reused values still participate in the output's diagnostic order.
      // Their exact per-occurrence size needs no value read or encoding.
      if value.issue is None &&
        managed_row_measurement_get(
          value.selection.index,
          value.row * width + column,
        ).unwrap().0 >
        value.ceiling {
        value.issue = Some(Guard(ValueBytes(Output, value.row, column)))
      }
      continue
    }
    let field = @schema.field_at(value.schema, column).unwrap()
    guard read(column) is Some(checked) else {
      return Err(Values(Admission(InvalidCheckedRow)))
    }
    if !value.open {
      return Err(Closed)
    }
    if !physical_equal(field.contract, checked.contract) {
      return Err(Values(Admission(ForeignCheckedValue(value.row, column))))
    }
    if !charge_text(value.budget, @schema.reference_name(field.name)) ||
      !measure(checked.value, 2, value.budget) {
      return Err(Values(Admission(CaptureLimit)))
    }
    // As with ordinary managed output, complete admission before reporting a
    // deferred logical measurement failure. No partial index can be published.
    if value.issue is Some(_) {
      continue
    }
    let budget = value.measurement
    if budget.work <= 0 {
      value.issue = Some(Guard(MeasurementWork))
      continue
    }
    budget.work -= 1
    let usage = try {
      let writer = @encode.measuring_writer(
        budget.bytes,
        budget.nodes,
        budget.depth,
      )
      emit_runtime_value(Captured(checked.value), writer)
      @encode.finish_measurement_usage(writer)
    } catch {
      issue => {
        value.issue = Some(Guard(Measurement(Output, value.row, column, issue)))
        continue
      }
    }
    budget.bytes -= usage.0
    budget.nodes -= usage.1
    if usage.0 > value.ceiling {
      value.issue = Some(Guard(ValueBytes(Output, value.row, column)))
      continue
    }
    let null = checked.value is @admitted.Null
    if !managed_row_measurement_set(
        value.selection.index,
        value.row * width + column,
        (usage.0, usage.1, null),
      ) {
      return Err(Values(Guard(InvalidLayout)))
    }
    let prior = value.selection.facts.columns[column]
    value.selection.facts.columns[column] = {
      ..prior,
      bytes: prior.bytes + usage.0,
      nodes: prior.nodes + usage.1,
      max_value_bytes: Int::max(prior.max_value_bytes, usage.0),
      null_rows: prior.null_rows + (if null { 1 } else { 0 }),
      admitted_depth: budget.depth,
    }
  }
  value.row += 1
  Ok(())
}

///|
/// Validation is still not execution. The returned selection must pass the
/// installed execution verifier and ordinary retention/completion boundaries.
pub fn[T] finish_managed_computed_view(
  value : ManagedComputedView[T],
) -> Result[ManagedViewSelection[T], ManagedComputedViewIssue] {
  if !value.open || value.reading {
    return Err(Closed)
  }
  if value.row != value.selection.rows.length() {
    cancel_managed_computed_view(value) |> ignore
    return Err(RowCount)
  }
  value.reading = true
  if !managed_producer_read_available(value.selection.plan.input) {
    cancel_managed_computed_view(value) |> ignore
    return Err(Selection(ForeignInput))
  }
  if !value.open {
    return Err(Closed)
  }
  if value.issue is Some(issue) {
    cancel_managed_computed_view(value) |> ignore
    return Err(
      match issue {
        Guard(issue) => NeedsOrderedMeasurement(issue)
        _ => Values(issue)
      },
    )
  }
  value.open = false
  value.reading = false
  Ok({
    ..value.selection,
    facts: {
      ..value.selection.facts,
      admission_usage: {
        work: value.budget.work,
        nodes: value.budget.nodes,
        text_bytes: value.budget.text,
      },
    },
  })
}

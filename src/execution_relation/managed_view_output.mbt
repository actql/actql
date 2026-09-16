///|
/// Facts supplied only by an installed Host verifier for one exact output.
/// The verifier must establish actual execution, row correspondence and every
/// newly computed column's validation. This record alone is not evidence.
pub(all) struct ManagedViewOutputFacts {
  rows : Int
  columns : Array[ManagedColumnMeasurement]
  admission_usage : ValueUsage
}

///|
struct ManagedViewOutputPort[P, T] {
  plan : ManagedViewPlan[T]
  stream : ManagedOutputValues
  verify : (P) -> ManagedViewOutputFacts?
  index : ManagedRowMeasurements?
  mut open : Bool
}

///|
pub(all) enum ManagedViewOutputIssue {
  Closed
  ForeignBinding
  Unverified
  InconsistentFacts
  OutputRepresentationRequired
  Values(ManagedOutputValueIssue)
}

///|
/// Host installation before execution, never a connector/Program-selected
/// callback. Its closure must bind proof to the exact attempt, output material,
/// plan and stream. Metadata limits were enforced when preparing the plan.
pub fn[P, T] prepare_managed_view_output_port(
  plan : ManagedViewPlan[T],
  stream : ManagedOutputValues,
  verify : (P) -> ManagedViewOutputFacts?,
) -> Result[ManagedViewOutputPort[P, T], ManagedViewOutputIssue] {
  if !stream.open || stream.reading || stream.rows != 0 {
    return Err(Closed)
  }
  // This issuer accepts aggregate column facts, not per-row index material.
  // Do not silently promise a downstream index which it cannot populate.
  if stream.row_measurements is Some(_) {
    return Err(OutputRepresentationRequired)
  }
  if !physical_equal(stream.owner, plan.input.receiver) ||
    stream.target != plan.target ||
    @schema.field_count(stream.buffer.schema) != plan.columns.length() ||
    !managed_producer_read_available(plan.input) {
    return Err(ForeignBinding)
  }
  if stream.managed_producer is Some(producer) &&
    !producer.bindings.any(id => physical_equal(id, plan.input.identity)) {
    return Err(ForeignBinding)
  }
  // Reserve the stream against append/finish during verifier re-entry. Store
  // retention must be installed before this reservation, using the same stream.
  if !stream.open || stream.reading || stream.rows != 0 {
    return Err(Closed)
  }
  if stream.row_measurements is Some(_) {
    return Err(OutputRepresentationRequired)
  }
  stream.reading = true
  Ok({ plan, stream, verify, index: None, open: true, })
}

///|
pub fn[P, T] cancel_managed_view_output_port(
  port : ManagedViewOutputPort[P, T],
) -> Bool {
  if !port.stream.open || (!port.open && !port.stream.reading) {
    return false
  }
  port.open = false
  cancel_managed_output_values(port.stream) |> ignore
  true
}

///|
/// Consume before invoking trusted code. On failure no receipt escapes; cleanup
/// of provisional output remains the installed implementation's responsibility.
pub fn[P, T] finish_managed_view_output(
  port : ManagedViewOutputPort[P, T],
  proof : P,
) -> Result[ManagedOutputValueReceipt, ManagedViewOutputIssue] {
  if !port.open || !port.stream.open {
    return Err(Closed)
  }
  port.open = false
  let stream = port.stream
  let result = managed_view_output_verify(port, proof)
  match result {
    Err(issue) => {
      cancel_managed_output_values(stream) |> ignore
      Err(issue)
    }
    Ok(_) => {
      stream.reading = false
      match finish_managed_output_values(stream) {
        Ok(receipt) => Ok(receipt)
        Err(issue) => Err(Values(issue))
      }
    }
  }
}

///|
fn[P, T] managed_view_output_verify(
  port : ManagedViewOutputPort[P, T],
  proof : P,
) -> Result[Unit, ManagedViewOutputIssue] {
  let stream = port.stream
  let plan = port.plan
  if !managed_producer_read_available(plan.input) {
    return Err(ForeignBinding)
  }
  guard (port.verify)(proof) is Some(facts) else { return Err(Unverified) }
  if !stream.open {
    return Err(Closed)
  }
  if !managed_producer_read_available(plan.input) {
    return Err(ForeignBinding)
  }
  let source_rows = plan.input.output.material.receipt.rows
  if facts.rows < 0 ||
    facts.rows > source_rows ||
    (plan.rows != SelectedRows && facts.rows != source_rows) ||
    facts.columns.length() != plan.columns.length() {
    return Err(InconsistentFacts)
  }
  let usage = facts.admission_usage
  let limits = stream.buffer.budget.limits
  if usage.nodes < 0 || usage.text_bytes < 0 || usage.work < 0 {
    return Err(InconsistentFacts)
  }
  // Summary failure does not identify the first offending row/field. Do not
  // fabricate its diagnostic; an ordered path is needed before publication.
  if facts.rows > stream.max_rows ||
    usage.nodes > limits.max_nodes ||
    usage.text_bytes > limits.max_text_bytes ||
    usage.work > limits.max_work {
    return Err(OutputRepresentationRequired)
  }
  let budget = stream.measurement
  let mut work = budget.work
  let mut bytes = budget.bytes
  let mut nodes = budget.nodes
  let mut needs_ordered = false
  if facts.rows > work {
    needs_ordered = true
  } else {
    work -= facts.rows
  }
  for index, column in facts.columns {
    if column.rows != facts.rows ||
      column.bytes < 0 ||
      column.nodes < 0 ||
      column.max_value_bytes < 0 ||
      column.null_rows < 0 ||
      column.null_rows > facts.rows ||
      column.admitted_depth < 0 ||
      column.max_value_bytes > column.bytes ||
      (facts.rows == 0 && (column.bytes != 0 || column.nodes != 0)) {
      return Err(InconsistentFacts)
    }
    if managed_view_plan_column_facts(plan, index) is Some(inherited) {
      if column.max_value_bytes > inherited.max_value_bytes_bound ||
        (inherited.null_free && column.null_rows != 0) {
        return Err(InconsistentFacts)
      }
      if inherited.exact_measurement is Some(exact) &&
        (
          column.bytes != exact.bytes ||
          column.nodes != exact.nodes ||
          column.max_value_bytes != exact.max_value_bytes ||
          column.null_rows != exact.null_rows
        ) {
        return Err(InconsistentFacts)
      }
    }
    if facts.rows > 0 &&
      (
        column.admitted_depth > budget.depth ||
        column.admitted_depth > limits.max_depth
      ) {
      return Err(OutputRepresentationRequired)
    }
    if !needs_ordered {
      if column.max_value_bytes > stream.max_value_bytes ||
        facts.rows > work ||
        column.bytes > bytes ||
        column.nodes > nodes {
        needs_ordered = true
      } else {
        work -= facts.rows
        bytes -= column.bytes
        nodes -= column.nodes
      }
    }
  }
  // No receipt before binding/liveness verification. An indexed diagnostic
  // resolution below retains the consumed prefix of the shared ledger.
  if !managed_producer_read_available(plan.input) {
    return Err(ForeignBinding)
  }
  if !stream.open {
    return Err(Closed)
  }
  if needs_ordered {
    guard port.index is Some(index) else {
      return Err(OutputRepresentationRequired)
    }
    match
      measure_managed_output_index(
        index,
        facts.rows,
        facts.columns.length(),
        stream.max_value_bytes,
        budget,
      ) {
      // Exact index and exact aggregate facts must agree. An aggregate
      // violation followed by successful indexed measurement is corruption,
      // never permission to publish contradictory evidence.
      Ok(_) => return Err(InconsistentFacts)
      Err(issue) => return Err(Values(Guard(issue)))
    }
  } else {
    // The normal success path stays O(columns), even when an index is held.
    budget.work = work
    budget.bytes = bytes
    budget.nodes = nodes
  }
  stream.buffer.budget.nodes = usage.nodes
  stream.buffer.budget.text = usage.text_bytes
  stream.buffer.budget.work = usage.work
  stream.rows = facts.rows
  stream.row_measurements = port.index
  for index, column in facts.columns {
    stream.column_usage[index] = (column.bytes, column.nodes)
    stream.column_maxima[index] = column.max_value_bytes
    stream.column_nulls[index] = column.null_rows
  }
  Ok(())
}

///|
/// Resolve only an otherwise ambiguous rejection, using sealed exact cell
/// measurements in the same row/column order as measure_input_values. All
/// depth and value-validity obligations must already have been established.
fn measure_managed_output_index(
  index : ManagedRowMeasurements,
  rows : Int,
  width : Int,
  ceiling : Int,
  budget : FixedInputGuardBudget,
) -> Result[Unit, FixedInputGuardIssue] {
  if (width == 0 && index.cells.length() != 0) ||
    (
      width > 0 &&
      (
        index.cells.length() / width != rows ||
        index.cells.length() % width != 0
      )
    ) {
    return Err(InvalidLayout)
  }
  for row in 0..<rows {
    if budget.work <= 0 {
      return Err(MeasurementWork)
    }
    budget.work -= 1
    for column in 0..<width {
      if budget.work <= 0 {
        return Err(MeasurementWork)
      }
      budget.work -= 1
      let (bytes, nodes, _) = index.cells[row * width + column]
      if bytes <= 0 || nodes <= 0 {
        return Err(InvalidLayout)
      }
      if bytes > budget.bytes || nodes > budget.nodes {
        return Err(Measurement(Output, row, column, @encode.OutputLimit))
      }
      budget.bytes -= bytes
      budget.nodes -= nodes
      if bytes > ceiling {
        return Err(ValueBytes(Output, row, column))
      }
    }
  }
  Ok(())
}

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
  mut index : ManagedRowMeasurements?
  mut open : Bool
  mut phase : ManagedViewFinishPhase
  mut facts_cursor : ManagedOutputFactsCursor?
}

///|
priv enum ManagedViewFinishPhase {
  Ready
  Verifying
  Facts
  Receipt
  Complete
} derive(Eq)

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
  if !stream.open || stream.reading || stream.finish_started || stream.rows != 0 {
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
  if !stream.open || stream.reading || stream.finish_started || stream.rows != 0 {
    return Err(Closed)
  }
  if stream.row_measurements is Some(_) {
    return Err(OutputRepresentationRequired)
  }
  stream.reading = true
  Ok({
    plan,
    stream,
    verify,
    index: None,
    open: true,
    phase: Ready,
    facts_cursor: None,
  })
}

///|
pub fn[P, T] cancel_managed_view_output_port(
  port : ManagedViewOutputPort[P, T],
) -> Bool {
  if !port.stream.open || (!port.open && !port.stream.reading) {
    discard_managed_view_output_index(port)
    return false
  }
  port.open = false
  cancel_managed_output_values(port.stream) |> ignore
  discard_managed_view_output_index(port)
  port.facts_cursor = None
  port.phase = Complete
  true
}

///|
fn[P, T] discard_managed_view_output_index(
  port : ManagedViewOutputPort[P, T],
) -> Unit {
  if port.index is Some(index) {
    discard_managed_row_measurements(index)
    port.index = None
  }
}

///|
/// Consume before invoking trusted code. On failure no receipt escapes; cleanup
/// of provisional output remains the installed implementation's responsibility.
pub fn[P, T] finish_managed_view_output(
  port : ManagedViewOutputPort[P, T],
  proof : P,
) -> Result[ManagedOutputValueReceipt, ManagedViewOutputIssue] {
  if !port.open || port.stream.active_uses != 0 {
    return Err(Closed)
  }
  while true {
    match advance_managed_view_output_finish(port, proof, 64) {
      Err(issue) => return Err(issue)
      Ok(poll) => if poll.receipt is Some(receipt) { return Ok(receipt) }
    }
  }
  Err(Closed)
}

///|
/// Verify once, then resume finite summary admission and the common receipt
/// cursor. The reserved stream remains unavailable to competing issuers.
pub fn[P, T] advance_managed_view_output_finish(
  port : ManagedViewOutputPort[P, T],
  proof : P,
  quantum : Int,
) -> Result[ManagedOutputFinishAdvance, ManagedViewOutputIssue] {
  if quantum <= 0 || port.stream.active_uses != 0 {
    return Err(Closed)
  }
  with_managed_output_scratch_use(port.stream, fn() {
    let result = advance_managed_view_output_finish_active(port, proof, quantum)
    if result is Err(_) && port.phase != Verifying {
      cancel_managed_output_values(port.stream) |> ignore
      discard_managed_view_output_index(port)
      port.facts_cursor = None
      port.phase = Complete
    }
    result
  })
}

///|
fn[P, T] advance_managed_view_output_finish_active(
  port : ManagedViewOutputPort[P, T],
  proof : P,
  quantum : Int,
) -> Result[ManagedOutputFinishAdvance, ManagedViewOutputIssue] {
  let stream = port.stream
  if !stream.open {
    return Err(Closed)
  }
  if !managed_producer_read_available(port.plan.input) {
    return Err(ForeignBinding)
  }
  for step in 0..<quantum {
    if !stream.open {
      return Err(Closed)
    }
    match port.phase {
      Ready => {
        if !port.open {
          return Err(Closed)
        }
        port.open = false
        port.phase = Verifying
        let cursor = match managed_view_output_verify(port, proof) {
          Ok(cursor) => cursor
          Err(issue) => {
            port.phase = Complete
            return Err(issue)
          }
        }
        port.facts_cursor = Some(cursor)
        port.phase = Facts
      }
      Verifying | Complete => return Err(Closed)
      Facts =>
        match
          advance_managed_output_facts_cursor(port.facts_cursor.unwrap(), 1) {
          Err(issue) => return Err(issue)
          Ok((true, _)) => {
            port.facts_cursor = None
            port.phase = Receipt
          }
          Ok((false, _)) => ()
        }
      Receipt => {
        if !managed_producer_read_available(port.plan.input) {
          return Err(ForeignBinding)
        }
        // The enclosing scratch use prevents reentrant disposal. Keep the
        // reservation across yields, but allow this owner to issue internally.
        stream.reading = true
        let poll = match
          advance_managed_output_finish_active(stream, quantum - step) {
          Ok(poll) => poll
          Err(issue) => return Err(Values(issue))
        }
        if poll.receipt is Some(_) {
          stream.reading = false
          port.index = None
          port.phase = Complete
        }
        return Ok({ ..poll, steps: step + poll.steps, })
      }
    }
  }
  Ok({ receipt: None, steps: quantum, })
}

///|
fn[P, T] managed_view_output_verify(
  port : ManagedViewOutputPort[P, T],
  proof : P,
) -> Result[ManagedOutputFactsCursor, ManagedViewOutputIssue] {
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
  let inherited_valid = (index : Int, column : ManagedColumnMeasurement) => {
    guard managed_view_plan_column_facts(plan, index) is Some(inherited) else {
      return true
    }
    if column.max_value_bytes > inherited.max_value_bytes_bound ||
      (inherited.null_free && column.null_rows != 0) {
      return false
    }
    match inherited.exact_measurement {
      Some(exact) =>
        column.bytes == exact.bytes &&
        column.nodes == exact.nodes &&
        column.max_value_bytes == exact.max_value_bytes &&
        column.null_rows == exact.null_rows
      None => true
    }
  }
  prepare_managed_output_facts_cursor(
    stream,
    facts,
    inherited_valid,
    port.index,
  )
}

///|
/// Shared finite summary verifier for installed execution implementations.
/// The caller must first bind the facts to one exact execution and retained
/// generation. Aggregate metadata supplied by a Program is never sufficient.
fn apply_managed_output_facts(
  stream : ManagedOutputValues,
  facts : ManagedViewOutputFacts,
  validate_column : (Int, ManagedColumnMeasurement) -> Bool,
  index : ManagedRowMeasurements?,
) -> Result[Unit, ManagedViewOutputIssue] {
  let cursor = match
    prepare_managed_output_facts_cursor(stream, facts, validate_column, index) {
    Ok(cursor) => cursor
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_managed_output_facts_cursor(cursor, 64) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => return Ok(())
      Ok((false, _)) => ()
    }
  }
  Err(Closed)
}

///|
/// One checked Effect source occurrence and its exact captured cell-backed
/// output. The ordinary task port may close while this owner is live. This is
/// neither a Preview nor an apply permit, and it does not copy Result cells.
struct CapturedEffectInput {
  source : CheckedEffectSourcePort
  pin : CapturedOutputPin
}

///|
/// Capture only the source retained by this checked Effect Run. An authored
/// name or caller-supplied output cannot replace its checked Stage Result port.
/// Nonterminal and managed representations require their own retained output
/// path before they can be accepted as Effect inputs.
pub fn pin_captured_effect_source(
  run : CapturedEffectRunDAG,
  member_index : Int,
  max_pins : Int,
) -> Result[CapturedEffectInput, RunIssue] {
  guard captured_effect_run_source_at(run, member_index) is Some(source) &&
    source.member_index == member_index else {
    return Err(ForeignCandidate)
  }
  let pin = match
    pin_captured_result_output(
      run.captured,
      source.stage,
      source.occurrence,
      max_pins,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ source, pin, })
}

///|
/// Borrow an exact checked Result occurrence from its completed task. This
/// remains Host-private retention, not permission to disclose the Result or
/// use it as an Effect input. A different Program owner cannot relabel it.
pub fn pin_captured_result_output(
  run : CapturedDAG,
  task : Int,
  occurrence : @execution.ManagedResultOccurrence,
  max_pins : Int,
) -> Result[CapturedOutputPin, RunIssue] {
  let owner = @execution.managed_result_occurrence_owner(occurrence)
  let port = @execution.managed_result_occurrence_port(occurrence)
  let target = @ports.port_target(port)
  guard run.graph.owners.get(task) is Some(actual) &&
    physical_equal(actual, owner) else {
    return Err(ForeignCandidate)
  }
  if captured_task_target(run, task) != Some(target) {
    return Err(UnsupportedGraph)
  }
  let pin = match pin_captured_task_output(run, task, target, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output = captured_output_pin_materialized(pin)
  if !@execution.completed_output_matches_port(output, owner, target) {
    release_captured_output_pin(pin) |> ignore
    return Err(ForeignCandidate)
  }
  Ok(pin)
}

///|
/// The checked occurrence retains its authored Result projection and order.
pub fn captured_effect_input_occurrence(
  value : CapturedEffectInput,
) -> @execution.ManagedResultOccurrence {
  value.source.occurrence
}

///|
/// The borrowed producer is live only while both the original completion and
/// this Effect input pin remain live. Projection is applied by the Result view
/// preparation, not by returning a caller-defined table here.
pub fn captured_effect_input_output(
  value : CapturedEffectInput,
) -> @execution.CompletedOutput {
  captured_output_pin_materialized(value.pin)
}

///|
/// Prepare the authored Result projection and order from this exact retained
/// Effect source. The existing bounded Result exporter owns the row traversal;
/// this port does not materialize a second table or accept caller rows. The
/// Effect input pin must remain live until the export has finished or cancelled.
/// The resulting bytes are input evidence, not an Effect Plan or apply permit.
pub fn start_captured_effect_input_export(
  value : CapturedEffectInput,
  result_view : @execution.CompletedResultViewLimits,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[
  @execution.CompletedResultRelationExportPreparation,
  @execution.CompletedExportIssue,
] {
  @execution.start_completed_result_relation_export(
    captured_effect_input_output(value),
    value.source.occurrence,
    result_view,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema_limits,
    max_batch_bytes,
  )
}

///|
/// End the Effect consumer's retention once its Preview input has been safely
/// captured or abandoned. This does not acknowledge any mutation outcome.
pub fn release_captured_effect_input(value : CapturedEffectInput) -> Bool {
  release_captured_output_pin(value.pin)
}

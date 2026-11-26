///|
fn prepare_captured_pending_data_edge_read(
  run : CapturedDAG,
  edge : DataEdge,
  source : @execution.CompletedOutput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[@execution.ProducerRead, RunIssue] {
  guard run.graph.owners_at(edge.consumer) is Some(receiver) &&
    run.graph.owners_at(edge.producer) is Some(producer) else {
    return Err(ForeignCandidate)
  }
  let binding = match (edge.operation_input, edge.source_input) {
    (Some((step, port)), None) =>
      @execution.bind_completed_operation_input(
        receiver, step, port, producer, source,
      )
    _ =>
      @execution.bind_completed_input(
        receiver,
        edge.source_input.unwrap_or(edge.input),
        producer,
        source,
      )
  }
  let binding = match binding {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  @execution.prepare_producer_read(
    receiver, binding, max_entries, max_name_bytes,
  ).map_err(issue => Read(issue))
}

///|
/// One finished export of a Result retained by its complete producer Unit.
/// Each consumer borrows the same admitted rows through its own checked edge.
struct CapturedCompletedUnitResultHandoff {
  unit : CapturedCompletedUnitResults
  index : Int
  producer : Int
  port : @ports.ResultPort
  receipt : @execution.CompletedRelationExportReceipt
  source : @execution.CompletedOutput
  retained : () -> Bool
}

///|
/// Bind the actual finished export to one canonical conversion of the original
/// managed completion. The caller holds the Unit, bridge and receipt through
/// every selected receiver. The returned value owns no new pins or export.
pub fn[T] prepare_captured_completed_unit_result_handoff(
  unit : CapturedCompletedUnitResults,
  index : Int,
  output : @execution.ManagedCompletedOutput[T],
  bridge : @execution.ManagedPublicationBridge[T],
  preparation : @execution.CompletedResultRelationExportPreparation,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Result[CapturedCompletedUnitResultHandoff, RunIssue] {
  guard captured_completed_unit_result_at(unit, index) is Some(borrow) &&
    captured_any_result_borrow_matches_managed(borrow, output) else {
    return Err(ForeignCandidate)
  }
  let occurrence = captured_any_result_borrow_occurrence(borrow)
  let port = @execution.managed_result_occurrence_port(occurrence)
  guard graph_stage_target_task(
      unit.run.graph,
      unit.unit,
      @ports.port_target(port),
    )
    is Some(producer) &&
    @execution.managed_publication_bridge_matches_result_export(
      bridge, output, preparation, occurrence,
    ) &&
    @execution.completed_result_export_preparation_matches_receipt(
      preparation, receipt,
    ) &&
    @execution.completed_relation_export_original_source(receipt)
    is Some(original) else {
    return Err(ForeignCandidate)
  }
  let retained = () => {
    captured_completed_unit_results_match(unit, unit.run, unit.unit) &&
    captured_any_result_borrow_retained(borrow) &&
    @execution.managed_publication_bridge_retained(bridge) &&
    @execution.completed_relation_export_has_output_identity(receipt, original)
  }
  guard retained() else { return Err(ForeignCandidate) }
  let source = @execution.restrict_completed_output(original, retained)
  Ok({ unit, index, producer, port, receipt, source, retained, })
}

///|
/// Borrow the exact confirmed Result export from this Unit member. A caller
/// cannot choose a different receipt with equal bytes or a different Result.
pub fn captured_completed_unit_result_export_original(
  value : CapturedCompletedUnitResultHandoff,
  unit : CapturedCompletedUnitResults,
  index : Int,
) -> (@ports.ResultPort, @execution.CompletedRelationExportReceipt)? {
  if physical_equal(value.unit, unit) &&
    value.index == index &&
    (value.retained)() {
    Some((value.port, value.receipt))
  } else {
    None
  }
}

///|
/// The exact canonical representation staged at the receiving port. The
/// completed consumer still needs its own proof that it used this original.
pub fn captured_completed_unit_result_input_original(
  value : CapturedCompletedUnitResultHandoff,
) -> @execution.CompletedOutput? {
  if (value.retained)() {
    Some(value.source)
  } else {
    None
  }
}

///|
/// Stage the checked receiving port before registration or activation. Both
/// siblings borrow the same handoff. Repeat selection of the same original is
/// harmless, but another (even equivalent) conversion cannot replace a Read.
pub fn retain_captured_completed_unit_result_input(
  value : CapturedCompletedUnitResultHandoff,
  edge_index : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[Unit, RunIssue] {
  let run = value.unit.run
  guard next_captured_task(run) is Some(task) &&
    @graph.graph_data_at(run.graph, edge_index) is Some(edge) &&
    edge.consumer == task &&
    edge.producer == value.producer &&
    @graph.graph_result_input_port(run.graph, edge_index) is Ok(Some(port)) &&
    physical_equal(port, value.port) else {
    return Err(ForeignCandidate)
  }
  let pending = () => {
    next_captured_task(run) == Some(task) &&
    run.managed_selections[task] is None &&
    !captured_task_activation_pending(run) &&
    (value.retained)()
  }
  guard pending() else { return Err(NotReady) }
  if run.inputs[task][edge.input] is Some(read) {
    guard @execution.producer_read_original_output(read) is Some(original) &&
      physical_equal(original, value.source) &&
      pending() &&
      run.inputs[task][edge.input] is Some(current) &&
      physical_equal(current, read) else {
      return Err(ForeignCandidate)
    }
    return Ok(())
  }
  let read = match
    prepare_captured_pending_data_edge_read(
      run,
      edge,
      value.source,
      max_entries,
      max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard pending() && run.inputs[task][edge.input] is None else {
    return Err(NotReady)
  }
  run.inputs[task][edge.input] = Some(read)
  Ok(())
}

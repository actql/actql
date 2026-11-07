///|
/// Complete checked Result inventory for one acquired dependency Unit. This
/// is ordinary Result-borrow custody, not the final Effect member inventory.
struct CapturedEffectLocalUnitInputs {
  run : CapturedEffectRunDAG
  unit : Int
  results : Array[CapturedEffectLocalResult]
  pins : CapturedAnyResultOutputSet
  mut live : Bool
}

///|
/// Capture a completed acquisition-prefix Unit before its consumer executes.
/// The existing checked Effect ancestry selects all declared local Results;
/// a caller cannot provide a subset or borrow an unrelated Unit. No downstream
/// completion, Preview readiness or approval is inferred from this inventory.
pub fn pin_captured_effect_acquired_unit_results(
  run : CapturedEffectRunDAG,
  unit : Int,
  max_pins : Int,
  max_dependency_work? : Int = 65536,
  max_dependency_depth? : Int = 64,
) -> Result[CapturedEffectLocalUnitInputs, RunIssue] {
  if unit < 0 || unit >= run.captured.graph.captured_prefix_value() {
    return Err(ForeignCandidate)
  }
  let all = match
    effect_dependency_ports(
      run.checked.computation,
      4096,
      max_dependency_work,
      max_dependency_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let ports = all.filter(port => port.stage == unit)
  if ports.is_empty() || ports.length() > max_pins {
    return Err(PreviewWorkLimit)
  }
  let requests = ports.map(port => (port.task, port.occurrence))
  let pins = match
    pin_captured_any_result_output_set(run.captured, requests, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let results = ports.mapi((index, port) => {
    stage: port.stage,
    task: port.task,
    borrow: captured_any_result_output_set_borrow_at(pins, index).unwrap(),
  })
  Ok({ run, unit, results, pins, live: true, })
}

///|
pub fn captured_effect_local_unit_inputs_match_computation(
  inputs : CapturedEffectLocalUnitInputs,
  computation : CheckedEffectComputationDAG,
) -> Bool {
  inputs.live &&
  !inputs.run.captured.stopped &&
  physical_equal(inputs.run.checked.computation, computation)
}

///|
pub fn captured_effect_local_unit_inputs_run_definition_cid(
  inputs : CapturedEffectLocalUnitInputs,
) -> String? {
  if !inputs.live {
    return None
  }
  Some(
    @publication.publication_contract_identity(
      @effect_binding.effect_program_run_definition(inputs.run.checked.run),
    ),
  )
}

///|
pub fn captured_effect_local_unit_result_count(
  inputs : CapturedEffectLocalUnitInputs,
) -> Int {
  if inputs.live {
    inputs.results.length()
  } else {
    0
  }
}

///|
pub fn captured_effect_local_unit_result_at(
  inputs : CapturedEffectLocalUnitInputs,
  index : Int,
) -> CapturedEffectLocalResult? {
  if !inputs.live || inputs.run.captured.stopped {
    return None
  }
  inputs.results
  .get(index)
  .bind(result => {
    if captured_any_result_borrow_available(result.borrow) {
      Some(result)
    } else {
      None
    }
  })
}

///|
pub fn captured_effect_local_unit_result_matches_source(
  inputs : CapturedEffectLocalUnitInputs,
  result : CapturedEffectLocalResult,
  identity : @query.CapturedSourceRelationIdentity,
) -> Bool {
  if !inputs.live ||
    inputs.run.captured.stopped ||
    result.stage != inputs.unit ||
    result.task != inputs.unit ||
    !inputs.results.any(value => physical_equal(value, result)) ||
    !captured_any_result_borrow_available(result.borrow) {
    return false
  }
  match result.borrow.kind {
    Source(value) =>
      physical_equal(value.run, inputs.run.captured) &&
      @query.captured_source_relation_identity_matches_source(
        identity,
        value.source,
      )
    _ => false
  }
}

///|
/// The original Unit inventory retains this exact acquisition. This supplies
/// provenance only; a later computed Result must keep its own live export.
pub fn captured_effect_local_unit_acquired_source_matches(
  inputs : CapturedEffectLocalUnitInputs,
  identity : @query.CapturedSourceRelationIdentity,
) -> Bool {
  inputs.live &&
  captured_effect_original_acquisition_matches(
    inputs.run.captured,
    inputs.unit,
    identity,
  ) &&
  inputs.live
}

///|
pub fn release_captured_effect_local_unit_inputs(
  inputs : CapturedEffectLocalUnitInputs,
) -> Bool {
  if !inputs.live {
    return false
  }
  let released = release_captured_any_result_output_set(inputs.pins)
  if released {
    inputs.live = false
  }
  released
}

///|
pub fn start_captured_effect_local_unit_result_export(
  inputs : CapturedEffectLocalUnitInputs,
  index : Int,
  result_view : @execution.CompletedResultViewLimits,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[
  CapturedEffectLocalResultExport,
  CapturedEffectLocalResultExportIssue,
] {
  guard captured_effect_local_unit_result_at(inputs, index) is Some(result) else {
    return Err(MissingResult)
  }
  let preparation = match
    start_captured_any_result_borrow_export(
      result.borrow,
      result_view,
      max_rows,
      values,
      payload_wire,
      logical_wire,
      schema_limits,
      max_batch_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  Ok({ owner: LocalUnit(inputs), result, preparation, derived_retained: None, })
}

///|
pub fn captured_effect_local_unit_result_export_matches_receipt(
  inputs : CapturedEffectLocalUnitInputs,
  value : CapturedEffectLocalResultExport,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Bool {
  match value.owner {
    LocalUnit(owner) =>
      physical_equal(owner, inputs) &&
      inputs.live &&
      captured_any_result_borrow_available(value.result.borrow) &&
      @execution.completed_result_export_preparation_matches_receipt(
        value.preparation,
        receipt,
      )
    EffectInputs(_) => false
  }
}

///|
pub fn captured_effect_local_unit_inputs_match_run(
  inputs : CapturedEffectLocalUnitInputs,
  run : CapturedEffectRunDAG,
) -> Bool {
  inputs.live && !run.captured.stopped && physical_equal(inputs.run, run)
}

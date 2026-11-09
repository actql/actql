///|
/// A checked local Result needed by an Effect's complete semantic Manifest.
/// The capture uses the ordinary Result borrow; this is not a second ledger.
struct CapturedEffectLocalResult {
  stage : Int
  task : Int
  borrow : CapturedAnyResultBorrow
}

///|
/// Root dependency evidence must refer to the exact still-retained capture,
/// not another source with equal logical rows or the same checked Program.
pub fn captured_effect_local_result_matches_source(
  inputs : CapturedEffectInputs,
  result : CapturedEffectLocalResult,
  identity : @query.CapturedSourceRelationIdentity,
) -> Bool {
  if !inputs.live ||
    inputs.run.captured.stopped ||
    result.stage < 0 ||
    result.stage >= inputs.run.captured.graph.captured_prefix_value() ||
    result.task != result.stage ||
    !inputs.local_results.any(value => physical_equal(value, result)) ||
    !captured_any_result_borrow_available(result.borrow) {
    return false
  }
  match result.borrow.kind {
    Source(value) =>
      @query.captured_source_relation_identity_matches_source(
        identity,
        value.source,
      ) &&
      physical_equal(value.run, inputs.run.captured)
    _ => false
  }
}

///|
// Inspect the SAME captured acquisition retained by this Run. Equal logical
// rows, a reused Prepared owner, or an evidence object's CID cannot substitute
// for that original capture. The callback may retire the Run synchronously.
fn captured_effect_original_acquisition_matches(
  run : CapturedDAG,
  unit : Int,
  identity : @query.CapturedSourceRelationIdentity,
) -> Bool {
  if run.stopped || unit < 0 {
    return false
  }
  let graph = run.graph
  if graph.captured_prefix_value() > 0 {
    if unit >= graph.captured_prefix_value() {
      return false
    }
    guard run.original_sources.get(unit).bind(value => value) is Some(source) else {
      return false
    }
    return @query.captured_source_relation_identity_matches_source(
        identity, source,
      ) &&
      !run.stopped
  }
  // Whole Sources supply checked inputs, not completed task slots. Retain
  // their exact original read binding; consuming that input does not erase
  // the provenance of an independently retained computed Result.
  for slot in graph.supplied_slots_iter() {
    if graph_task_unit_index(graph, slot.consumer) != Some(unit) {
      continue
    }
    if run.supplied_reads
      .get(slot.consumer)
      .bind(values => values.get(slot.input).bind(value => value))
      is Some(read) &&
      @query.captured_source_relation_identity_has_input_binding(identity, read) {
      return !run.stopped
    }
  }
  false
}

///|
/// Match acquisition provenance, not a computed Result's physical output.
/// Result export/currentness and publication admission remain separate duties.
pub fn captured_effect_inputs_acquired_source_matches(
  inputs : CapturedEffectInputs,
  unit : Int,
  identity : @query.CapturedSourceRelationIdentity,
) -> Bool {
  inputs.live &&
  captured_effect_original_acquisition_matches(
    inputs.run.captured,
    unit,
    identity,
  ) &&
  inputs.live
}

///|
priv struct EffectDependencyPort {
  stage : Int
  task : Int
  occurrence : @execution.ManagedResultOccurrence
}

///|
/// Select complete local Manifests only for Effect source Units and their
/// imported Result ancestry. Exact checked import owners determine edges;
/// caller-authored dependency CIDs or task masks are not accepted.
fn effect_dependency_ports(
  value : CheckedEffectComputationDAG,
  max_results : Int,
  max_work : Int,
  max_depth : Int,
) -> Result[Array[EffectDependencyPort], RunIssue] {
  let graph = value.graph_value()
  let program = graph.program_value()
  let count = @checked.unit_count(program)
  if max_results < 0 || max_work < count || max_depth < 0 {
    return Err(PreviewWorkLimit)
  }
  let mut work = max_work - count
  let depth = Array::make(count, -1)
  for source in value.sources_iter() {
    if work == 0 {
      return Err(PreviewWorkLimit)
    }
    work -= 1
    if source is Some(source) {
      depth[source.stage] = 0
    }
  }
  for source in value.table_sources_iter() {
    if work == 0 {
      return Err(PreviewWorkLimit)
    }
    work -= 1
    if source is Some(source) {
      depth[source.stage] = 0
    }
  }
  let identity = @checked.source_identity(program)
  let incoming = @context.incoming_links_requirements(
    @context.program_incoming_gates_owner(@checked.incoming_gates(program)),
  )
  let wiring = @context.program_incoming_wiring(incoming)
  // Checked imports point strictly backwards. Descending traversal also
  // propagates the longest path through shared dependencies, not merely the
  // first path that happens to visit a Unit.
  for stage = count - 1; stage >= 0; stage = stage - 1 {
    if depth[stage] < 0 {
      continue
    }
    let imports = @checked.unit_result_import_count(program, stage).unwrap()
    for index in 0..<imports {
      if work == 0 {
        return Err(PreviewWorkLimit)
      }
      work -= 1
      let imported = @checked.unit_result_import_at(program, stage, index).unwrap()
      let site = @context.result_import_type_site(imported.row)
      guard site.stage == stage &&
        site.requirement is @context.Result(_, predecessor, _) else {
        return Err(ForeignCandidate)
      }
      let mut producer = None
      for candidate in 0..<stage {
        if work == 0 {
          return Err(PreviewWorkLimit)
        }
        work -= 1
        if @context.program_identity_stage_at(identity, candidate)
          is Some(owner) &&
          physical_equal(owner, predecessor) {
          producer = Some(candidate)
          break
        }
      }
      guard producer is Some(producer) else { return Err(ForeignCandidate) }
      if depth[stage] >= max_depth {
        return Err(PreviewWorkLimit)
      }
      depth[producer] = Int::max(depth[producer], depth[stage] + 1)
    }
  }
  let output : Array[EffectDependencyPort] = []
  for stage in 0..<count {
    if depth[stage] < 0 {
      continue
    }
    guard @results.wiring_stage_at(wiring, stage) is Some(ports) else {
      return Err(ForeignCandidate)
    }
    let publications = @results.stage_port_publications(ports)
    let results = @ports.port_count(publications)
    if results > max_results - output.length() || results > work {
      return Err(PreviewWorkLimit)
    }
    work -= results
    for index in 0..<results {
      let port = @ports.port_at(publications, index).unwrap()
      // A captured Unit can also publish a later computed Result. Resolve its
      // exact checked target before falling back to that Unit's Source task.
      // The ordinary pin still checks the original owner, target and lifetime.
      let selected = match
        graph_stage_target_task(graph, stage, @ports.port_target(port)) {
        Some(task) => Some(task)
        None if stage < graph.captured_prefix_value() => Some(stage)
        None => None
      }
      guard selected is Some(task) && graph.owners_at(task) is Some(owner) else {
        return Err(ForeignCandidate)
      }
      let name = @ports.name(@ports.port_result(port))
      let occurrence = match
        @execution.bind_managed_result_occurrence(owner, name, port) {
        Ok(value) => value
        Err(_) => return Err(ForeignCandidate)
      }
      output.push({ stage, task, occurrence, })
    }
  }
  Ok(output)
}

///|
pub fn captured_effect_local_result_count(value : CapturedEffectInputs) -> Int {
  if value.live {
    value.local_results.length()
  } else {
    0
  }
}

///|
pub fn captured_effect_local_result_at(
  value : CapturedEffectInputs,
  index : Int,
) -> CapturedEffectLocalResult? {
  if !value.live {
    return None
  }
  value.local_results
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
pub fn captured_effect_local_result_stage(
  value : CapturedEffectLocalResult,
) -> Int {
  value.stage
}

///|
pub fn captured_effect_local_result_task(
  value : CapturedEffectLocalResult,
) -> Int {
  value.task
}

///|
/// Resolve a member to its exact checked local Result occurrence, not just
/// another Result with the same shape or bytes.
pub fn captured_effect_local_result_matches_member(
  inputs : CapturedEffectInputs,
  local_index : Int,
  member_index : Int,
) -> Bool {
  guard captured_effect_local_result_at(inputs, local_index) is Some(result) &&
    captured_effect_input_at(inputs, member_index) is Some(input) else {
    return false
  }
  result.stage == captured_effect_input_stage(input) &&
  @execution.managed_result_occurrence_name(
    captured_any_result_borrow_occurrence(result.borrow),
  ) ==
  @execution.managed_result_occurrence_name(
    captured_effect_input_occurrence(input),
  ) &&
  captured_any_result_borrows_share_view(
    result.borrow,
    captured_effect_input_borrow(input),
  )
}

///|
pub fn captured_effect_local_result_borrow(
  value : CapturedEffectLocalResult,
) -> CapturedAnyResultBorrow {
  value.borrow
}

///|
/// Exact preparation custody for one local Result export. A receipt from
/// another Result or another traversal cannot replace this preparation.
struct CapturedEffectLocalResultExport {
  owner : CapturedEffectLocalResultExportOwner
  result : CapturedEffectLocalResult
  preparation : @execution.CompletedResultRelationExportPreparation
  derived_retained : (() -> Bool)?
}

///|
priv enum CapturedEffectLocalResultExportOwner {
  EffectInputs(CapturedEffectInputs)
  LocalUnit(CapturedEffectLocalUnitInputs)
}

///|
pub(all) enum CapturedEffectLocalResultExportIssue {
  MissingResult
  ForeignOutput
  Export(@execution.CompletedExportIssue)
}

///|
pub fn start_captured_effect_local_result_export(
  inputs : CapturedEffectInputs,
  index : Int,
  result_view : @execution.CompletedResultViewLimits,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
  converted_output? : @execution.CompletedOutput,
) -> Result[
  CapturedEffectLocalResultExport,
  CapturedEffectLocalResultExportIssue,
] {
  guard captured_effect_local_result_at(inputs, index) is Some(result) else {
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
      converted_output?,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  Ok({
    owner: EffectInputs(inputs),
    result,
    preparation,
    derived_retained: None,
  })
}

///|
/// The resident adapter supplies a physical bridge, not a replacement Result
/// identity. Ownership and generation are checked before accepting its export.
pub fn[T] bind_captured_effect_local_result_managed_export(
  inputs : CapturedEffectInputs,
  index : Int,
  output : @execution.ManagedCompletedOutput[T],
  bridge : @execution.ManagedPublicationBridge[T],
  preparation : @execution.CompletedResultRelationExportPreparation,
) -> Result[
  CapturedEffectLocalResultExport,
  CapturedEffectLocalResultExportIssue,
] {
  guard captured_effect_local_result_at(inputs, index) is Some(result) else {
    return Err(MissingResult)
  }
  if !captured_any_result_borrow_matches_managed(result.borrow, output) ||
    !@execution.managed_publication_bridge_matches_result_export(
      bridge,
      output,
      preparation,
      captured_any_result_borrow_occurrence(result.borrow),
    ) {
    return Err(ForeignOutput)
  }
  Ok({
    owner: EffectInputs(inputs),
    result,
    preparation,
    derived_retained: Some(() => {
      @execution.managed_publication_bridge_retained(bridge)
    }),
  })
}

///|
/// Recheck the original derived-view fence after availability callbacks. This
/// is separate from the longer-lived original captured Result retention.
fn captured_effect_local_result_export_derived_retained(
  value : CapturedEffectLocalResultExport,
) -> Bool {
  match value.derived_retained {
    Some(retained) => retained()
    None => true
  }
}

///|
pub fn captured_effect_local_result_export_preparation(
  value : CapturedEffectLocalResultExport,
) -> @execution.CompletedResultRelationExportPreparation {
  value.preparation
}

///|
/// Retain the checked Result occurrence through receipt admission. Equal
/// bytes, names, and CIDs do not replace exact export identity or liveness.
pub fn captured_effect_local_result_export_matches_receipt(
  inputs : CapturedEffectInputs,
  value : CapturedEffectLocalResultExport,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Bool {
  match value.owner {
    EffectInputs(owner) =>
      physical_equal(owner, inputs) &&
      inputs.live &&
      captured_any_result_borrow_available(value.result.borrow) &&
      @execution.completed_result_export_preparation_matches_receipt(
        value.preparation,
        receipt,
      )
    LocalUnit(_) => false
  }
}

///|
pub fn captured_effect_local_result_export_result(
  value : CapturedEffectLocalResultExport,
) -> CapturedEffectLocalResult {
  value.result
}

///|
/// Callback-free lifetime fence for this same Effect input/export pair after
/// physical availability/current callbacks. This issues no availability,
/// authorization or receipt, and does not acquire or copy a pin inventory.
pub fn captured_effect_local_result_export_retained(
  inputs : CapturedEffectInputs,
  value : CapturedEffectLocalResultExport,
) -> Bool {
  match value.owner {
    EffectInputs(owner) =>
      physical_equal(owner, inputs) &&
      inputs.live &&
      inputs.pins.live &&
      inputs.table_pins.live &&
      captured_any_result_borrow_retained(value.result.borrow)
    LocalUnit(_) => false
  }
}

///|
/// Original computed Result correspondence in the graph actually opened by
/// this capture. Source-input graphs preserve checked Program/Unit/target
/// ownership while their task coordinates differ from captured-prefix graphs.
/// This reads retained fields only; receipt/current checks stay with exports.
pub fn captured_effect_local_result_export_matches_computed_unit(
  value : CapturedEffectLocalResultExport,
  computation : CheckedEffectComputationDAG,
  unit : Int,
) -> Bool {
  let run = match value.owner {
    EffectInputs(inputs) if inputs.live => inputs.run
    LocalUnit(inputs) if inputs.live && inputs.unit == unit => inputs.run
    _ => return false
  }
  let result = value.result
  if run.captured.stopped ||
    !physical_equal(run.checked.computation, computation) ||
    result.stage != unit ||
    !captured_any_result_borrow_retained(result.borrow) {
    return false
  }
  let graph = run.captured.graph
  result.task >= graph.captured_prefix_value() &&
  graph_stage_target_task(
    graph,
    unit,
    @ports.port_target(
      @execution.managed_result_occurrence_port(
        captured_any_result_borrow_occurrence(result.borrow),
      ),
    ),
  ) ==
  Some(result.task)
}

///|
/// Bind a serial post-Model Result to the original Model input actually read
/// by this captured Run. The completed Result is intentionally not the Model
/// boundary itself. This reads the checked same-Unit edges and the existing
/// nominal ProducerRead; it never compares rows/CIDs, executes a task or issues
/// an input, permission, current proof or cleanup acknowledgement.
pub fn captured_effect_local_result_export_matches_model_suffix(
  value : CapturedEffectLocalResultExport,
  inputs : CapturedEffectInputs,
  computation : CheckedEffectComputationDAG,
  unit : Int,
  model_task : Int,
  original : @execution.CompletedOutput,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Bool {
  guard value.owner is EffectInputs(originals) &&
    physical_equal(originals, inputs) &&
    inputs.live &&
    captured_effect_local_result_export_matches_computed_unit(
      value, computation, unit,
    ) else {
    return false
  }
  let run = inputs.run.captured
  let graph = run.graph
  let result = value.result
  if model_task < graph.captured_prefix_value() ||
    model_task >= result.task ||
    graph_task_unit_index(graph, model_task) != Some(unit) ||
    !run.done[model_task] {
    return false
  }
  let mut consumer = result.task
  // Checked edges are ordered; a strictly decreasing cursor bounds this
  // metadata-only walk without another stack, Array, graph or work owner.
  while consumer > model_task {
    if graph_task_unit_index(graph, consumer) != Some(unit) ||
      graph_task_input_count(graph, consumer) != Some(1) ||
      !run.done[consumer] {
      return false
    }
    let mut producer = -1
    for edge in graph.data_iter() {
      if edge.consumer == consumer {
        if producer >= 0 ||
          edge.input != 0 ||
          edge.producer < model_task ||
          edge.producer >= consumer {
          return false
        }
        producer = edge.producer
      }
    }
    if producer < model_task {
      return false
    }
    if producer == model_task {
      guard run.inputs[consumer][0] is Some(input) &&
        @execution.producer_read_matches_completed_output(input, original) &&
        @execution.completed_result_export_preparation_matches_receipt(
          value.preparation,
          receipt,
        ) else {
        return false
      }
      // Original availability can call out. Keep only callback-free exact
      // alias/lifetime fences afterwards; revocation cannot leave a live path.
      return inputs.live &&
        !run.stopped &&
        run.lifetimes[model_task].live &&
        run.lifetimes[consumer].live &&
        (
          run.inputs[consumer][0] is Some(actual) &&
          physical_equal(actual, input)
        ) &&
        captured_effect_local_result_export_derived_retained(value) &&
        captured_effect_local_result_export_retained(inputs, value)
    }
    consumer = producer
  }
  false
}

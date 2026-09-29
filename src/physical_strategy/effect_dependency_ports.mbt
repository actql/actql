///|
/// A checked local Result needed by an Effect's complete semantic Manifest.
/// The capture uses the ordinary Result borrow; this is not a second ledger.
struct CapturedEffectLocalResult {
  stage : Int
  task : Int
  borrow : CapturedAnyResultBorrow
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
  let graph = value.graph
  let program = graph.program
  let count = @checked.unit_count(program)
  if max_results < 0 || max_work < count || max_depth < 0 {
    return Err(PreviewWorkLimit)
  }
  let mut work = max_work - count
  let depth = Array::make(count, -1)
  for source in value.sources {
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
      // Acquisition occupies task zero but is not a Compute task with a
      // selected graph target. Its actual Result target is checked against
      // the captured Source completion when the pin is acquired.
      let selected = if stage == 0 && !graph.source_free_root {
        Some(0)
      } else {
        graph_stage_target_task(graph, stage, @ports.port_target(port))
      }
      guard selected is Some(task) && graph.owners.get(task) is Some(owner) else {
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
pub fn captured_effect_local_result_borrow(
  value : CapturedEffectLocalResult,
) -> CapturedAnyResultBorrow {
  value.borrow
}

///|
/// Exact preparation custody for one local Result export. A receipt from
/// another Result or another traversal cannot replace this preparation.
struct CapturedEffectLocalResultExport {
  inputs : CapturedEffectInputs
  result : CapturedEffectLocalResult
  preparation : @execution.CompletedResultRelationExportPreparation
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
    ) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  Ok({ inputs, result, preparation, })
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
  Ok({ inputs, result, preparation, })
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
  physical_equal(value.inputs, inputs) &&
  inputs.live &&
  captured_any_result_borrow_available(value.result.borrow) &&
  @execution.completed_result_export_preparation_matches_receipt(
    value.preparation,
    receipt,
  )
}

///|
pub fn captured_effect_local_result_export_result(
  value : CapturedEffectLocalResultExport,
) -> CapturedEffectLocalResult {
  value.result
}

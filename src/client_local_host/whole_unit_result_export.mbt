///|
/// Own the one bridge and finished export borrowed by a Whole Unit's
/// Artifact and every receiver of that Result. The caller owns the Unit pins.
struct LocalWholeUnitResultExport {
  bridge : @execution.ManagedPublicationBridge[Int]
  export_preparation : @execution.CompletedResultRelationExportPreparation
  receipt : @execution.CompletedRelationExportReceipt
  handoff : @strategy.CapturedCompletedUnitResultHandoff
  mut closed : Bool
}

///|
pub(all) enum LocalWholeUnitResultExportIssue {
  ForeignOriginal
  Capacity
  Bridge(@execution.ManagedProducerBridgeIssue)
  Export(@execution.CompletedExportIssue)
  Handoff(@strategy.RunIssue)
}

///|
/// Prepare the unconsumed receiver's exact producer view. Back the live
/// bridge, checked projection and export with the original Run's allowance
/// before copying rows or advancing the Result view.
pub fn prepare_local_whole_unit_result_export(
  selected : LocalWholeTaskPreparation,
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  unit : Int,
  results : @strategy.CapturedCompletedUnitResults,
  index : Int,
  quantum : Int,
  max_rounds : Int,
  fund : (@execution.ExecutionCapacity) -> Bool,
) -> Result[LocalWholeUnitResultExport, LocalWholeUnitResultExportIssue] {
  let current = () => {
    local_whole_task_preparation_matches(selected, selected.run, selected.task) &&
    owner.source_free_captured is Some(original) &&
    physical_equal(original, selected.run) &&
    installed_managed_preparation_admission_original(owner, prepared, request)
    is Some(_) &&
    @strategy.captured_completed_unit_results_match(results, selected.run, unit)
  }
  guard quantum > 0 &&
    max_rounds > 0 &&
    current() &&
    owner.captured_preparation is Some(plan) &&
    !plan.whole_sources.is_empty() &&
    @strategy.captured_completed_unit_result_at(results, index) is Some(borrow) else {
    return Err(ForeignOriginal)
  }
  let occurrence = @strategy.captured_any_result_borrow_occurrence(borrow)
  let port = @execution.managed_result_occurrence_port(occurrence)
  guard @strategy.graph_stage_target_task(
      plan.graph,
      unit,
      @results.port_target(port),
    )
    is Some(producer) &&
    selected.tasks.get(producer) is Some(Some(task)) &&
    task.completed is Some(completed) &&
    @strategy.captured_any_result_borrow_matches_managed(borrow, completed) &&
    @strategy.captured_any_result_borrow_row_count(borrow) is Some(rows) &&
    (task.operations.material)() is Some(material) else {
    return Err(ForeignOriginal)
  }
  guard client_node_publication_limits_original(
      plan.capacity_plan.exports.wire.max_bytes,
      plan.capacity_plan,
    )
    is Some(limits) &&
    @local.local_export_retention_capacity(plan.capacity_plan.exports)
    is Some(codec) &&
    @execution.managed_publication_bridge_import_geometry(
      completed,
      material,
      plan.capacity_plan.exports.wire.max_columns,
      plan.capacity_plan.exports.wire.max_bytes,
    )
    is Some(geometry) &&
    local_whole_producer_result_limits(
      plan.capacity_plan,
      limits,
      port,
      geometry,
      rows,
    )
    is Some(limits) &&
    completed_unit_result_export_capacity(
      borrow,
      rows,
      limits,
      codec,
      Some(geometry),
    )
    is Some(capacity) &&
    fund(capacity) else {
    return Err(Capacity)
  }
  if !current() {
    return Err(ForeignOriginal)
  }
  let (bridge, output) = match
    prepare_publication_bridge_for_original(
      selected.available,
      task.operations,
      completed,
      geometry.row,
      geometry.entries,
      geometry.name_bytes,
      limits,
    ) {
    Ok(value) => value
    Err(MissingOutput) => return Err(ForeignOriginal)
    Err(Bridge(issue)) => return Err(Bridge(issue))
  }
  let opened = start_local_whole_unit_result_export(
    bridge, output, completed, results, index, occurrence, limits, rows, quantum,
    max_rounds, current,
  )
  if opened is Err(_) {
    @execution.close_managed_publication_bridge(bridge)
  }
  opened
}

///|
// Final Named Result sizing can be too narrow for this producer. Construct
// its view bounds from its own checked port and already measured rows under
// the same installed execution, value and wire policy.
fn local_whole_producer_result_limits(
  plan : ClientLocalCapacityPlan,
  limits : @publication_host.PublicationOutputExportLimits,
  port : @results.ResultPort,
  geometry : @execution.ManagedPublicationBridgeLimits,
  rows : Int,
) -> @publication_host.PublicationOutputExportLimits? {
  let width = @schema.field_count(@results.port_schema(port))
  let terms = @results.port_order_term_count(port)
  let workspace = rows.to_int64() *
    (if terms == 0 || rows < 2 { 1L } else { 2L }) +
    terms.to_int64()
  guard client_local_result_port_mapping_work(
      width,
      geometry.entries,
      @results.port_projection_count(port),
      terms,
    )
    is Some(mapping) &&
    rows >= 0 &&
    rows <= plan.execution.rows.max_rows &&
    width <= plan.exports.wire.max_columns &&
    workspace <= 2147483647L &&
    mapping <= plan.execution.max_work &&
    rows <= plan.execution.max_work else {
    return None
  }
  Some({
    ..limits,
    max_result_fields: width,
    max_result_mapping_work: mapping,
    max_result_order_work: if terms == 0 {
      rows
    } else {
      plan.execution.max_work
    },
    max_result_workspace_entries: workspace.to_int(),
    max_rows: rows,
  })
}

///|
fn start_local_whole_unit_result_export(
  bridge : @execution.ManagedPublicationBridge[Int],
  output : @execution.CompletedOutput,
  completed : @execution.ManagedCompletedOutput[Int],
  results : @strategy.CapturedCompletedUnitResults,
  index : Int,
  occurrence : @execution.ManagedResultOccurrence,
  limits : @publication_host.PublicationOutputExportLimits,
  rows : Int,
  quantum : Int,
  max_rounds : Int,
  current : () -> Bool,
) -> Result[LocalWholeUnitResultExport, LocalWholeUnitResultExportIssue] {
  let preparation = match
    @execution.start_completed_result_relation_export(
      output,
      occurrence,
      {
        max_fields: limits.max_result_fields,
        max_mapping_work: limits.max_result_mapping_work,
        max_order_work: limits.max_result_order_work,
        max_workspace_entries: limits.max_result_workspace_entries,
      },
      limits.max_rows,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      limits.max_batch_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  let opened = finish_local_whole_unit_result_export(
    preparation, bridge, completed, results, index, rows, quantum, max_rounds, current,
  )
  if opened is Err(_) {
    @execution.cancel_completed_result_relation_export(preparation) |> ignore
  }
  opened
}

///|
fn finish_local_whole_unit_result_export(
  preparation : @execution.CompletedResultRelationExportPreparation,
  bridge : @execution.ManagedPublicationBridge[Int],
  completed : @execution.ManagedCompletedOutput[Int],
  results : @strategy.CapturedCompletedUnitResults,
  index : Int,
  rows : Int,
  quantum : Int,
  max_rounds : Int,
  current : () -> Bool,
) -> Result[LocalWholeUnitResultExport, LocalWholeUnitResultExportIssue] {
  let mut ready = false
  for _ in 0..<max_rounds {
    if !current() {
      return Err(ForeignOriginal)
    }
    match
      @execution.advance_completed_result_relation_export(preparation, quantum) {
      Ok((true, _)) => {
        ready = true
        break
      }
      Ok((false, _)) => ()
      Err(issue) => return Err(Export(issue))
    }
  }
  if !ready {
    return Err(Capacity)
  }
  let stream = match
    @execution.finish_completed_result_relation_export_preparation(preparation) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  let mut count = 0
  while true {
    if !current() {
      return Err(ForeignOriginal)
    }
    match @execution.next_completed_output_export(stream, batch=false) {
      Ok(None) => break
      Ok(Some(_)) if count < rows => count += 1
      Ok(Some(_)) => return Err(Capacity)
      Err(issue) => return Err(Export(issue))
    }
  }
  if !current() {
    return Err(ForeignOriginal)
  }
  let receipt = match @execution.finish_completed_relation_export(stream) {
    Ok((value, _)) => value
    Err(issue) => return Err(Export(issue))
  }
  match
    @strategy.prepare_captured_completed_unit_result_handoff(
      results, index, completed, bridge, preparation, receipt,
    ) {
    Ok(handoff) if current() =>
      Ok({
        bridge,
        export_preparation: preparation,
        receipt,
        handoff,
        closed: false,
      })
    value => {
      @execution.cancel_completed_relation_export_receipt(receipt)
      match value {
        Ok(_) => Err(ForeignOriginal)
        Err(issue) => Err(Handoff(issue))
      }
    }
  }
}

///|
/// Borrow the original selected export. The DAG still owns receiver selection.
pub fn LocalWholeUnitResultExport::handoff(
  self : Self,
) -> @strategy.CapturedCompletedUnitResultHandoff? {
  if self.closed {
    None
  } else {
    Some(self.handoff)
  }
}

///|
/// Retire the export and its converted view after the last borrower releases.
pub fn LocalWholeUnitResultExport::close(self : Self) -> Unit {
  if !self.closed {
    self.closed = true
    @execution.cancel_completed_relation_export_receipt(self.receipt)
    @execution.cancel_completed_result_relation_export(self.export_preparation)
    |> ignore
    @execution.close_managed_publication_bridge(self.bridge)
  }
}

///|
// Same capture construction and Result pins, not another execution/resource
// owner. Retain this record before any exporter/issuer can fail.
priv struct LocalNativeMockEffectUnitResult {
  index : Int
  mut managed_export : @local_values.LocalValuesEffectResultExport?
  mut exported : @strategy.CapturedEffectLocalResultExport?
  mut stream : @execution.CompletedOutputExport?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut snapshot : @execution.CompletedRelationSnapshotPreparation?
  mut _retained_wire : String?
  mut _retained_definition : @run_host.ClientEffectLocalResultDefinition?
  mut artifact : @run_host.ClientEffectLocalResultArtifact?
  mut _retained_dependency : @run_host.ClientEffectDependencyCapture?
}

///|
fn LocalNativeMockEffectUnitResult::close(self : Self) -> Unit {
  self._retained_dependency = None
  self.artifact = None
  self._retained_definition = None
  self._retained_wire = None
  if self.snapshot is Some(value) {
    value.cancel()
    self.snapshot = None
  }
  if self.receipt is Some(value) {
    @execution.cancel_completed_relation_export_receipt(value)
    self.receipt = None
  }
  if self.stream is Some(value) {
    @execution.cancel_completed_output_export(value)
    self.stream = None
  }
  if self.exported is Some(value) {
    @execution.cancel_completed_result_relation_export(
      @strategy.captured_effect_local_result_export_preparation(value),
    )
    |> ignore
    self.exported = None
  }
  if self.managed_export is Some(value) {
    value.close()
    self.managed_export = None
  }
}

///|
// Count original declared Results not already supplied by an Effect member.
// No names are synthesized and no Result/Model is executed by this census.
fn native_mock_effect_extra_unit_results(
  prepared : @run_host.PreparedClientEffectComputation,
  unit : Int,
) -> Int {
  let candidate = @run_host.prepared_client_effect_computation_candidate(
    prepared,
  )
  let program = @checked.effect_program_static_checked_computation(candidate)
  guard @stage_results.stage_at(@checked.checked_stage_results(program), unit)
    is Some(stage) else {
    return 0
  }
  let mut count = 0
  for index in 0..<@results.count(stage) {
    let name = @results.name(@results.result_at(stage, index).unwrap())
    if !native_mock_effect_result_consumed(prepared, unit, name) {
      count += 1
    }
  }
  count
}

///|
// Complete the SAME Unit Manifest. Select each original borrow's physical
// exporter, never a Model task number, failed export or equal row contents.
fn LocalCommandBusinessPreparation::prepare_mock_effect_unit_results(
  self : Self,
  state : LocalNativeMockEffectPlan,
  held : LocalNativeMockEffectProposals,
  max_bytes : Int,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    held.construction is Some(construction) &&
    held.materials is Some(materials) &&
    held.acquired is Some(acquired) &&
    state.model_output is Some(_) &&
    held.unit_results.is_empty() else {
    stop("LocalOriginalEffectUnitResultsUnavailable")
  }
  let (_, unit, _) = @run_host.client_infer_plan_graph_coordinates(state.graph)
  let limits = state.first._retained_models[0]._retained_limits
  let wire = limits.identity.wire
  let expected = native_mock_effect_extra_unit_results(
    state._retained_prepared,
    unit,
  )
  for index in 0..<@strategy.captured_effect_local_result_count(held.inputs) {
    let result = @strategy.captured_effect_local_result_at(held.inputs, index).unwrap()
    if @strategy.captured_effect_local_result_stage(result) != unit {
      continue
    }
    let name = @execution.managed_result_occurrence_name(
      @strategy.captured_any_result_borrow_occurrence(
        @strategy.captured_effect_local_result_borrow(result),
      ),
    )
    if native_mock_effect_result_consumed(state._retained_prepared, unit, name) {
      continue
    }
    let entry : LocalNativeMockEffectUnitResult = {
      index,
      managed_export: None,
      exported: None,
      stream: None,
      receipt: None,
      snapshot: None,
      _retained_wire: None,
      _retained_definition: None,
      artifact: None,
      _retained_dependency: None,
    }
    held.unit_results.push(entry)
    let exported = if !@strategy.captured_any_result_borrow_requires_managed_export(
        @strategy.captured_effect_local_result_borrow(result),
      ) {
      self.prepare_mock_effect_direct_result_export(state, held, index)
    } else {
      let managed = self.prepare_mock_effect_local_result_export(
        state, held, index,
      )
      entry.managed_export = Some(managed)
      managed
      .captured_export()
      .unwrap_or_else(() => stop("LocalOriginalEffectUnitResultsUnavailable"))
    }
    entry.exported = Some(exported)
    let preparation = @strategy.captured_effect_local_result_export_preparation(
      exported,
    )
    while !@execution.advance_completed_result_relation_export(preparation, 31)
          .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
          .native_effect_proposal(self.original).0 {
      ()
    }
    let stream = @execution.finish_completed_result_relation_export_preparation(
        preparation,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal(self.original)
    entry.stream = Some(stream)
    while @execution.next_completed_output_export_canonical_row(
            stream,
            wire.max_nodes,
            wire.max_depth,
            limits.output_work,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
          .native_effect_proposal(self.original)
          is Some(_) {
      ()
    }
    let (receipt, _) = @execution.finish_completed_relation_export(stream)
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal(self.original)
    entry.receipt = Some(receipt)
    let name = @execution.managed_result_occurrence_name(
      @strategy.captured_any_result_borrow_occurrence(
        @strategy.captured_effect_local_result_borrow(result),
      ),
    )
    let definition = @run_host.issue_client_effect_local_result_definition(
        state._retained_prepared,
        unit,
        name,
        16384,
        1024,
        20,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Definition(issue))
      .native_effect_proposal(self.original)
    entry._retained_definition = Some(definition)
    construction.retain_wire(
      self.original,
      @run_host.client_effect_local_result_definition_json(definition),
    )
    let artifact = business.model_work[0]
      .local_effect_model_artifact(
        materials,
        held.inputs,
        exported,
        acquired,
        definition,
        receipt,
        16384,
        1024,
        20,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Artifact(issue))
      .native_effect_proposal(self.original)
    entry.artifact = Some(artifact)
    for
      body in [
        @run_host.client_effect_local_result_artifact_json(artifact),
        @run_host.client_effect_local_result_derivation_json(artifact),
        @run_host.client_effect_local_result_ordering_json(artifact),
      ] {
      construction.retain_wire(self.original, body)
    }
    let (bytes, nodes, _, depth) = @execution.completed_relation_export_snapshot_extent(
        stream, receipt,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal(self.original)
    if !construction.prepare(
        self.original,
        Int::max(1, bytes),
        Int::max(1, nodes),
        Int::max(1, depth),
      ) {
      stop("LocalOriginalEffectUnitResultsUnavailable")
    }
    let snapshot = @execution.start_completed_relation_export_snapshot(
        stream,
        receipt,
        wire.max_bytes,
        wire.max_nodes,
        wire.max_depth,
        limits.output_workspace,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal(self.original)
    entry.snapshot = Some(snapshot)
    while !snapshot
          .advance(256)
          .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
          .native_effect_proposal(self.original).0 {
      ()
    }
    let (rows, _) = snapshot
      .finish()
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal(self.original)
    snapshot.cancel()
    entry.snapshot = None
    entry._retained_wire = Some(rows)
    entry._retained_dependency = Some(
      @run_host.admit_client_effect_dependency_capture(
        materials,
        held.inputs,
        artifact,
        entry.index,
        exported,
        receipt,
        rows,
        max_bytes,
        wire.max_nodes,
        wire.max_depth,
        before_body=Some((bytes, nodes, depth) => {
          construction.prepare_canonical(self.original, bytes, nodes, depth)
        }),
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Dependency(issue))
      .native_effect_proposal(self.original),
    )
  }
  if held.unit_results.length() != expected {
    stop("LocalOriginalEffectUnitResultsUnavailable")
  }
}

///|
// Immutable checked declaration selection only; actual pins/export/Artifact
// admission still establish the live original at their existing boundaries.
fn native_mock_effect_result_consumed(
  prepared : @run_host.PreparedClientEffectComputation,
  unit : Int,
  name : String,
) -> Bool {
  let headers = @checked.effect_program_static_headers(
    @run_host.prepared_client_effect_computation_candidate(prepared),
  )
  for index in 0..<@syntax.effect_header_count(headers) {
    let header = @syntax.effect_header_at(headers, index).unwrap()
    if @syntax.effect_header_stage(header) == unit &&
      @syntax.effect_header_source_result(header) == Some(name) {
      return true
    }
  }
  false
}

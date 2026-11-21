///|
// Called in the original retained Request. Each Result is exported once;
// multiple Effect members borrow its exact completed receipt and snapshot.
fn LocalNativeMockEffectPlan::prepare_direct_mock_effect_proposals(
  self : Self,
  run : @local_values.ClientInstalledManagedRun,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> Unit raise ClientStop {
  guard self.proposals is None &&
    self.first._retained_models.is_empty() &&
    self._retained_import_recipes.length() == 2 &&
    self.direct_sources is Some(direct) &&
    direct._retained_publication is Some(publication) &&
    self.effect_capture is Some(captured) &&
    self.effect_host is Some(host) &&
    self.suffix is Some(execution) else {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
  let prepared = self._retained_prepared
  let plan = self._retained_plan
  let request = self.first.request
  let limits = @local_values.installed_effect_managed_publication_limits(
    run, prepared, request, plan, max_bytes,
  ).unwrap_or_else(() => stop("LocalOriginalEffectResultUnavailable"))
  let wire = limits.payload_wire
  let effect_limits = @run_host.client_standard_effect_computation_limits().effects
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap_or_else(() => stop("LocalOriginalEffectResultUnavailable"))
  let bridge = @local_driver.local_publication_bridge_limits(
    installed,
    @strategy.captured_effect_run_dag(captured),
  ).unwrap_or_else(() => stop("LocalOriginalEffectResultUnavailable"))
  let inputs = @local_values.pin_installed_effect_sources(
      run,
      prepared,
      request,
      plan,
      captured,
      bridge.entries,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal_with_cause(report)
  let held = native_mock_effect_proposals(inputs, bridge)
  self.proposals = Some(held)
  @local_values.retain_installed_effect_captured_input_inventory(
    run, prepared, request, plan, inputs,
  )
  .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
  .native_effect_proposal_with_cause(report)
  let first_input = @strategy.captured_effect_input_at(inputs, 0).unwrap_or_else(() => {
      stop("LocalOriginalEffectProposalsUnavailable")
    },
  )
  let unit = @strategy.captured_effect_input_stage(first_input)
  for index in 0..<@strategy.captured_effect_inputs_count(inputs) {
    guard @strategy.captured_effect_input_at(inputs, index) is Some(input) &&
      @strategy.captured_effect_input_stage(input) == unit else {
      stop("LocalOriginalEffectInvocationUnavailable")
    }
    let proposal = @strategy.prepare_captured_effect_proposal_plan(
        inputs,
        index,
        wire.max_columns,
        effect_limits.max_work,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Proposal(issue))
      .native_effect_proposal_with_cause(report)
    held.members.push(native_mock_effect_proposal_member(proposal))
  }
  let operation = native_mock_effect_capture_operation(
      run, prepared, request, plan, 0,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal_with_cause(report)
  held.members[0].capture_operation = Some(operation)
  let recipe = self._retained_import_recipes[0]
  @local_values.prepare_installed_effect_capture_recipe_extent(
    "native.mock.file.capture", recipe,
  )
  .bind(extent => {
    @local_values.begin_installed_effect_operation_input(operation, extent)
  })
  .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
  .native_effect_proposal_with_cause(report)
  let construction : LocalNativeMockEffectImportConstruction = {
    operation,
    recipe,
    retained: 0L,
    workspace: 0L,
  }
  held.construction = Some(construction)
  let observation = @run_host.client_effect_direct_sources_publication_observation(
    publication,
  )
  let invocation = @run_host.client_effect_direct_sources_publication_invocation(
    publication,
  )
  let admission = @run_host.client_effect_allowed_run_admission(
    self.first.allowed,
  )
  let (_, policy, _) = @publication.resolve_run_local_result_context(
      admission,
      self.first.definition,
      invocation,
      observation,
    )
    .map_err(issue => {
      LocalNativeMockEffectProposalIssue::Artifact(Context(issue))
    })
    .native_effect_proposal_with_cause(report)
  let retention = @local_values.rebind_installed_effect_result_retention(
      run, prepared, request, plan, retention, policy, 16384, 1024, 20,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::UnitPublication(issue))
    .native_effect_proposal_with_cause(report)
  held.publication_context = Some((observation, invocation, retention))
  let materials = @run_host.bind_prepared_client_effect_original_materials(
      self.first.allowed,
      self.first.definition,
      self.first.issued,
      request=Some(request),
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Materials(issue))
    .native_effect_proposal_with_cause(report)
  held.materials = Some(materials)
  let combined = @local_values.prepare_installed_effect_combined_source_unit(
      run, plan, request, publication, unit, retention, 16384, 1024, 20,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::UnitPublication(issue))
    .native_effect_proposal_with_cause(report)
  held._retained_combined_source_unit = Some(combined)
  let local_invocation = @run_host.client_effect_combined_source_unit_invocation(
    combined,
  )
  held.invocation = Some(local_invocation)
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
    if @strategy.captured_effect_local_result_stage(result) != unit {
      continue
    }
    let entry = native_mock_effect_unit_result(index)
    held.unit_results.push(entry)
    let managed = execution
      .prepare_effect_result_export(
        captured,
        inputs,
        index,
        bridge.row,
        bridge.entries,
        bridge.name_bytes,
        limits,
        before_row=Some(text => {
          construction
          .prepare_row_result(text, bridge.row)
          .retain_mock_effect_proposal_issue(report)
        }),
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::ManagedExport(issue))
      .native_effect_proposal_with_cause(report)
    entry.managed_export = Some(managed)
    let exported = managed
      .captured_export()
      .unwrap_or_else(() => stop("LocalOriginalEffectResultUnavailable"))
    entry.exported = Some(exported)
    let preparation = @strategy.captured_effect_local_result_export_preparation(
      exported,
    )
    while !@execution.advance_completed_result_relation_export(preparation, 31)
          .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
          .native_effect_proposal_with_cause(report).0 {
      ()
    }
    let stream = @execution.finish_completed_result_relation_export_preparation(
        preparation,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal_with_cause(report)
    entry.stream = Some(stream)
    while @execution.next_completed_output_export_canonical_row(
            stream,
            wire.max_nodes,
            wire.max_depth,
            limits.values.max_text_bytes,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
          .native_effect_proposal_with_cause(report)
          is Some((row_index, _, row)) {
      for effect_index, proposal in held.members {
        if @strategy.captured_effect_local_result_matches_member(
            inputs, index, effect_index,
          ) {
          let values = @strategy.project_captured_effect_proposal_row(
              proposal.plan,
              row,
              row_index,
              wire.max_columns,
              effect_limits.max_work,
              wire.max_bytes,
              wire.max_nodes,
              wire.max_depth,
            )
            .map_err(issue => {
              LocalNativeMockEffectProposalIssue::Proposal(issue)
            })
            .native_effect_proposal_with_cause(report)
          proposal.rows.push(values)
        }
      }
    }
    let (receipt, _) = @execution.finish_completed_relation_export(stream)
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal_with_cause(report)
    entry.receipt = Some(receipt)
    let artifact = @local_values.prepare_installed_effect_combined_source_result_artifact(
        run, plan, request, publication, inputs, exported, combined, receipt, admission,
        16384, 1024, 20,
      )
      .map_err(issue => {
        LocalNativeMockEffectProposalIssue::UnitPublication(issue)
      })
      .native_effect_proposal_with_cause(report)
    entry.artifact = Some(artifact)
    let (bytes, nodes, _, depth) = @execution.completed_relation_export_snapshot_extent(
        stream, receipt,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal_with_cause(report)
    construction
    .prepare_body_result(
      native_mock_effect_dependency_body_capacity(
        Int::max(1, bytes),
        Int::max(1, nodes),
        Int::max(1, depth),
      ),
    )
    .native_effect_proposal_with_cause(report)
    let snapshot = @execution.start_completed_relation_export_snapshot(
        stream,
        receipt,
        wire.max_bytes,
        wire.max_nodes,
        wire.max_depth,
        limits.max_result_workspace_entries,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal_with_cause(report)
    entry.snapshot = Some(snapshot)
    while !snapshot
          .advance(256)
          .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
          .native_effect_proposal_with_cause(report).0 {
      ()
    }
    let (rows, _) = snapshot
      .finish()
      .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
      .native_effect_proposal_with_cause(report)
    snapshot.cancel()
    entry.snapshot = None
    entry._retained_wire = Some(rows)
    let dependency = @run_host.admit_client_effect_dependency_capture(
        materials,
        inputs,
        artifact,
        index,
        exported,
        receipt,
        rows,
        max_bytes,
        wire.max_nodes,
        wire.max_depth,
        before_body=Some((bytes, nodes, depth) => {
          construction
          .prepare_body_result(
            native_mock_effect_canonical_body_capacity(bytes, nodes, depth),
          )
          .retain_mock_effect_proposal_issue(report)
        }),
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Dependency(issue))
      .native_effect_proposal_with_cause(report)
    entry._retained_dependency = Some(dependency)
    for effect_index, proposal in held.members {
      if @strategy.captured_effect_local_result_matches_member(
          inputs, index, effect_index,
        ) {
        if proposal._retained_artifact is Some(_) {
          stop("LocalOriginalEffectResultUnavailable")
        }
        proposal._retained_invocation = Some(local_invocation)
        proposal._retained_artifact = Some(artifact)
        proposal._retained_snapshot_wire = Some(rows)
        proposal._retained_dependency = Some(dependency)
      }
    }
  }
  for proposal in held.members {
    guard proposal._retained_artifact is Some(_) else {
      stop("LocalOriginalEffectResultUnavailable")
    }
    @strategy.finish_captured_effect_proposal_plan(
      proposal.plan,
      proposal.rows.length(),
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Proposal(issue))
    .native_effect_proposal_with_cause(report)
  }
  held._retained_local_manifest = Some(
    @local_values.prepare_installed_effect_model_unit_manifest(
      run,
      plan,
      request,
      local_invocation,
      held.unit_results.map(entry => entry.artifact.unwrap()),
      max_bytes,
      wire.max_nodes,
      wire.max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::UnitPublication(issue))
    .native_effect_proposal_with_cause(report),
  )
}

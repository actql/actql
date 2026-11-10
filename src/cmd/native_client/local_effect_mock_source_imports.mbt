///|
// A caller record on the SAME capture operation, never a Source/Run owner.
// Retain each original before its next fallible constructor or cleanup step.
priv struct LocalNativeMockEffectSourceImport {
  source : @run_host.ClientEffectAcquiredEvidence
  artifacts : Array[@run_host.ClientEffectLocalResultArtifact]
  names : Array[String]
  captures : Array[@run_host.ClientEffectDependencyCapture]
  mut snapshot : @execution.CompletedRelationSnapshotPreparation?
  mut _snapshot_wire : String?
  mut manifest : @run_host.ClientEffectLocalManifest?
  mut managed_export : @local_values.LocalValuesEffectResultExport?
  mut exported : @strategy.CapturedEffectLocalResultExport?
  mut stream : @execution.CompletedOutputExport?
  mut receipt : @execution.CompletedRelationExportReceipt?
}

///|
fn LocalNativeMockEffectSourceImport::close_export(self : Self) -> Unit {
  self._snapshot_wire = None
  if self.snapshot is Some(snapshot) {
    snapshot.cancel()
    self.snapshot = None
  }
  if self.receipt is Some(receipt) {
    @execution.cancel_completed_relation_export_receipt(receipt)
    self.receipt = None
  }
  if self.stream is Some(stream) {
    @execution.cancel_completed_output_export(stream)
    self.stream = None
  }
  if self.exported is Some(exported) {
    @execution.cancel_completed_result_relation_export(
      @strategy.captured_effect_local_result_export_preparation(exported),
    )
    |> ignore
    self.exported = None
  }
  if self.managed_export is Some(exported) {
    exported.close()
    self.managed_export = None
  }
}

///|
// Bind every declared producer Result and every checked consumer import.
// Source/Model are already complete and stay with their original owners.
fn LocalCommandBusinessPreparation::prepare_mock_effect_source_imports(
  self : Self,
  state : LocalNativeMockEffectPlan,
  held : LocalNativeMockEffectProposals,
) -> Unit raise ClientStop {
  let occurrence = state.graph.occurrence
  let program = @checked.effect_program_static_checked_computation(
    @run_host.prepared_client_effect_computation_candidate(
      state._retained_prepared,
    ),
  )
  let unit = @run_host.client_infer_occurrence_coordinates(occurrence).1
  let count = @checked.unit_result_import_count(program, unit).unwrap_or_else(() => {
    stop("LocalOriginalEffectImportsUnavailable")
  })
  if count == 0 {
    return
  }
  guard held.imports is None &&
    held.source_imports.is_empty() &&
    held.publication_context is Some((observation, invocation, retention)) else {
    stop("LocalOriginalEffectImportsUnavailable")
  }
  let limits = state.first._retained_models[0]._retained_limits
  let wire = limits.identity.wire
  guard state._retained_import_recipes.length() == 2 else {
    stop("LocalOriginalEffectImportsUnavailable")
  }
  let construction = held.construction.unwrap_or_else(() => {
    stop("LocalOriginalEffectImportsUnavailable")
  })
  // The complete original source occurrence inventory, not import names or
  // counts as a substitute for producer custody. Canonical metadata is funded
  // in this same capture extent before any of these constructors are called.
  let direct = @run_host.select_client_effect_direct_acquisition_occurrences(
    state._retained_prepared,
    limits.output_work,
  ).unwrap_or_else(() => stop("LocalOriginalEffectImportsUnavailable"))
  for
    source_index in 0..<@run_host.client_direct_acquisition_occurrence_count(
      direct,
    ) {
    let (stage, _, _) = @run_host.client_direct_acquisition_occurrence_at(
      direct, source_index,
    ).unwrap()
    let pending = if state.lookup is Some(lookup) {
      @run_host.issue_client_keyed_native_effect_source_unit(
        state._retained_prepared,
        lookup,
        source_index,
        retention,
        16384,
        1024,
        20,
      )
    } else {
      guard state.model_read is Some(read) &&
        state.captured_inputs.get(source_index) is Some(input) &&
        @row_host.row_captured_input_source(input) is Some(captured) &&
        read.identities.get(source_index) is Some(identity) &&
        read.logicals.get(source_index) is Some(logical) &&
        read.observations.get(source_index) is Some(observed) &&
        state.input_originals.get(source_index) is Some((acquisition, _)) else {
        stop("LocalOriginalEffectImportsUnavailable")
      }
      @run_host.issue_client_whole_native_effect_source_unit(
        state._retained_prepared,
        direct,
        source_index,
        captured,
        identity,
        acquisition,
        logical,
        observed,
        @run_host.client_request_authority_scope_cid(state.first.request),
        retention,
        16384,
        1024,
        20,
      )
    }
    let acquired = pending
      .map_err(issue => LocalNativeMockEffectProposalIssue::Source(issue))
      .native_effect_proposal(self.original)
    let source : LocalNativeMockEffectSourceImport = {
      source: acquired,
      artifacts: [],
      names: [],
      captures: [],
      snapshot: None,
      _snapshot_wire: None,
      manifest: None,
      managed_export: None,
      exported: None,
      stream: None,
      receipt: None,
    }
    held.source_imports.push(source)
    construction.retain_wire(
      self.original,
      @run_host.client_effect_local_invocation_json(
        @run_host.client_effect_acquired_invocation(acquired),
      ),
    )
    if state.lookup is None {
      // These are newly encoded whole-input metadata originals. The keyed
      // branch already retains its identical bodies on the original lookup.
      for
        (_, body) in @run_host.client_effect_acquired_dependency_bodies(
          acquired,
        ) {
        construction.retain_wire(self.original, body)
      }
    }
    for index in 0..<@strategy.captured_effect_local_result_count(held.inputs) {
      let result = @strategy.captured_effect_local_result_at(held.inputs, index).unwrap_or_else(() => {
          stop("LocalOriginalEffectImportsUnavailable")
        },
      )
      if @strategy.captured_effect_local_result_stage(result) != stage {
        continue
      }
      let managed = self.prepare_mock_effect_local_result_export(
        state, held, index,
      )
      source.managed_export = Some(managed)
      let exported = managed
        .captured_export()
        .unwrap_or_else(() => stop("LocalOriginalEffectImportsUnavailable"))
      source.exported = Some(exported)
      let preparation = @strategy.captured_effect_local_result_export_preparation(
        exported,
      )
      while !@execution.advance_completed_result_relation_export(
              preparation, 31,
            )
            .map_err(issue => {
              LocalNativeMockEffectProposalIssue::Completed(issue)
            })
            .native_effect_proposal(self.original).0 {
        continue
      }
      let stream = @execution.finish_completed_result_relation_export_preparation(
          preparation,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original)
      source.stream = Some(stream)
      while @execution.next_completed_output_export_canonical_row(
              stream,
              wire.max_nodes,
              wire.max_depth,
              limits.output_work,
            )
            .map_err(issue => {
              LocalNativeMockEffectProposalIssue::Completed(issue)
            })
            .native_effect_proposal(self.original)
            is Some(_) {
        continue
      }
      let (receipt, _) = @execution.finish_completed_relation_export(stream)
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original)
      source.receipt = Some(receipt)
      let name = @execution.managed_result_occurrence_name(
        @strategy.captured_any_result_borrow_occurrence(
          @strategy.captured_effect_local_result_borrow(result),
        ),
      )
      let definition = @run_host.issue_client_effect_local_result_definition(
          state._retained_prepared,
          stage,
          name,
          16384,
          1024,
          20,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Definition(issue))
        .native_effect_proposal(self.original)
      construction.retain_wire(
        self.original,
        @run_host.client_effect_local_result_definition_json(definition),
      )
      let artifact = @run_host.issue_acquired_client_effect_local_result_artifact(
          state._retained_prepared,
          held.inputs,
          exported,
          acquired,
          definition,
          receipt,
          @run_host.client_effect_allowed_run_admission(state.first.allowed),
          state.first.definition,
          invocation,
          observation,
          16384,
          1024,
          20,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Artifact(issue))
        .native_effect_proposal(self.original)
      source.artifacts.push(artifact)
      source.names.push(name)
      for
        retained_wire in [
          @run_host.client_effect_local_result_artifact_json(artifact),
          @run_host.client_effect_local_result_derivation_json(artifact),
          @run_host.client_effect_local_result_ordering_json(artifact),
        ] {
        construction.retain_wire(self.original, retained_wire)
      }
      let (bytes, nodes, _, depth) = @execution.completed_relation_export_snapshot_extent(
          stream, receipt,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original)
      // Original writer measurements precede snapshot allocation. This is an
      // additional retained original, not an assumption that parsing freed it.
      if !construction.prepare(
          self.original,
          Int::max(1, bytes),
          Int::max(1, nodes),
          Int::max(1, depth),
        ) {
        stop("LocalOriginalEffectProposalsUnavailable")
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
      source.snapshot = Some(snapshot)
      while !snapshot
            .advance(256)
            .map_err(issue => {
              LocalNativeMockEffectProposalIssue::Completed(issue)
            })
            .native_effect_proposal(self.original).0 {
        continue
      }
      let (rows_wire, _) = snapshot
        .finish()
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original)
      snapshot.cancel()
      source.snapshot = None
      source._snapshot_wire = Some(rows_wire)
      source.captures.push(
        @run_host.admit_client_effect_dependency_capture(
          held.materials.unwrap(),
          held.inputs,
          artifact,
          index,
          exported,
          receipt,
          rows_wire,
          wire.max_bytes,
          wire.max_nodes,
          wire.max_depth,
          before_body=Some((bytes, nodes, depth) => {
            construction.prepare_canonical(self.original, bytes, nodes, depth)
          }),
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Dependency(issue))
        .native_effect_proposal(self.original),
      )
      source.close_export()
    }
    source.manifest = Some(
      @run_host.issue_client_effect_local_manifest(
        state._retained_prepared,
        @run_host.client_effect_acquired_invocation(acquired),
        source.artifacts,
        16384,
        1024,
        20,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Manifest(issue))
      .native_effect_proposal(self.original),
    )
    construction.retain_wire(
      self.original,
      @run_host.client_effect_local_manifest_json(source.manifest.unwrap()),
    )
  }
  for index in 0..<count {
    let captured = @strategy.capture_effect_result_import(
        held.inputs,
        unit,
        index,
        limits.output_work,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Capture(issue))
      .native_effect_proposal(self.original)
    let producer = @strategy.captured_effect_result_import_producer(captured)
    let stage = @strategy.captured_effect_local_result_stage(producer)
    let name = @execution.managed_result_occurrence_name(
      @strategy.captured_any_result_borrow_occurrence(
        @strategy.captured_effect_local_result_borrow(producer),
      ),
    )
    let mut selected = None
    for source in held.source_imports {
      if @run_host.client_effect_local_invocation_matches(
          @run_host.client_effect_acquired_invocation(source.source),
          state._retained_prepared,
          stage,
        ) {
        for index, artifact in source.artifacts {
          if source.names[index] == name {
            selected = Some((source, artifact))
          }
        }
      }
    }
    guard selected is Some((source, artifact)) &&
      source.manifest is Some(manifest) else {
      stop("LocalOriginalEffectImportsUnavailable")
    }
    held.import_observations.push(
      @run_host.issue_client_effect_result_import_observation(
        state._retained_prepared,
        held.inputs,
        captured,
        manifest,
        artifact,
        16384,
        1024,
        20,
      )
      .map_err(issue => {
        LocalNativeMockEffectProposalIssue::ImportObservation(issue)
      })
      .native_effect_proposal(self.original),
    )
    construction.retain_wire(
      self.original,
      @run_host.client_effect_result_import_observation_json(
        held.import_observations[index],
      ),
    )
  }
  held.imports = Some(
    @run_host.issue_client_effect_imported_evidence(
      state._retained_prepared,
      held.inputs,
      unit,
      held.import_observations,
      16384,
      1024,
      20,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Imports(issue))
    .native_effect_proposal(self.original),
  )
  let imported = held.imports.unwrap()
  construction.retain_wire(
    self.original,
    @run_host.client_effect_imported_scope_json(imported),
  )
  construction.retain_wire(
    self.original,
    @run_host.client_effect_local_invocation_json(
      @run_host.client_effect_imported_invocation(imported),
    ),
  )
  for wire in @run_host.client_effect_imported_relation_bodies(imported) {
    construction.retain_wire(self.original, wire)
  }
  // Only now can the next capture phase start. Restore the original full
  // Preview/row recipe beside ALL retained import originals, before the
  // caller constructs Model evidence, member output or target requests.
  if !construction.finish(self.original, state._retained_import_recipes[1]) {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
}

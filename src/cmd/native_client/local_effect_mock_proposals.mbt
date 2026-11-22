///|
// Original typed failures stay private on this command through diagnosis and
// cleanup. A generic public stop code never substitutes for the original cause.
priv enum LocalNativeMockEffectProposalIssue {
  Managed(@local_values.ClientInstalledManagedRunIssue)
  Capture(@strategy.RunIssue)
  Proposal(@strategy.CapturedEffectProposalIssue)
  ManagedExport(@local_values.LocalValuesEffectResultExportIssue)
  ManagedPublicExport(@local_values.LocalValuesResultExportIssue)
  Completed(@execution.CompletedExportIssue)
  Keyed(@run_host.ClientKeyedRequestIssue)
  Source(@run_host.ClientEffectAcquiredEvidenceIssue)
  Materials(@run_host.ClientEffectRunMaterialsIssue)
  Definition(@run_host.ClientEffectLocalResultDefinitionIssue)
  Artifact(@run_host.ClientEffectLocalResultArtifactIssue)
  UnitPublication(@local_values.ClientEffectUnitPreparationIssue)
  Dependency(@run_host.ClientEffectDependencyCaptureIssue)
  Manifest(@run_host.ClientEffectLocalManifestIssue)
  PreviewSource(@run_host.ClientEffectSourceArtifactIssue)
  PreviewIdentity(@run_host.ClientEffectLocalIdentityIssue)
  PreviewBody(@publication.EffectPreviewIdentityIssue)
  PreviewBinding(@run_host.ClientCapturedEffectPreviewIssue)
  PreviewDispatch(@effect.EffectIdentityIssue)
  PreviewKeys(@effect.EffectPreviewApplyIdentityIssue)
  PreviewPlan(@strategy.CapturedEffectPlanVerifyIssue)
  CapturedSource(@publication.CapturedRunIssuanceIssue)
  LocalSource(@publication.CapturedLocalEffectSourceIssue)
  Inventory(@publication.CapturedEffectDependencyIssue)
  PublicExport(@run_host.PublicationOutputExportIssue)
  PublicManifest(@publication.ResultManifestIssuanceIssue)
  PublicReceipt(@publication.RunReceiptIssuanceIssue)
  PublicBindings(@run_host.ClientEffectReceiptBindingsIssue)
  PublicNormalization(@run_host.ClientEffectNormalizationIssue)
  PublicCapture(@run_host.ClientEffectCapturedRunIssue)
  HostExecution(@local_values.LocalValuesExecutionIssue)
  ImportObservation(@run_host.ClientEffectResultImportIssue)
  Imports(@run_host.ClientEffectImportedEvidenceIssue)
  PolicyDependency(@checked.LocalDependencyBodyIssue)
}

///|
fn[T] Result::native_effect_proposal(
  self : Result[T, LocalNativeMockEffectProposalIssue],
  original : LocalCommandPreparationOriginal,
) -> T raise ClientStop {
  self.native_effect_proposal_with_cause(issue => {
    original.retain_primary(CommandBusinessEffectProposals(issue))
  })
}

///|
fn[T] Result::native_effect_proposal_with_cause(
  self : Result[T, LocalNativeMockEffectProposalIssue],
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> T raise ClientStop {
  match self {
    Ok(value) => value
    Err(issue) => {
      report(issue)
      stop("LocalOriginalEffectProposalsUnavailable")
    }
  }
}

///|
// Caller retention of the original Effect pins/export/projection continuations.
// These carry DATA only. Target observations, Preview, approval and physical
// writes retain their separate original Owners and authorizations.
priv struct LocalNativeMockEffectProposals {
  inputs : @strategy.CapturedEffectInputs
  bridge_limits : @execution.ManagedPublicationBridgeLimits
  mut construction : LocalNativeMockEffectImportConstruction?
  mut publication_context : (
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
    @publication.PublicationContract,
  )?
  members : Array[LocalNativeMockEffectProposalMember]
  unit_results : Array[LocalNativeMockEffectUnitResult]
  mut _retained_keyed_identity : @run_host.ClientKeyedLookupRequestIdentity?
  mut invocation : @run_host.ClientEffectLocalInvocation?
  mut materials : @run_host.ClientEffectRunMaterials?
  mut acquired : @run_host.ClientEffectModelAcquiredEvidence?
  mut _retained_combined_source_unit : @run_host.ClientEffectCombinedSourceUnit?
  mut _retained_local_manifest : @run_host.ClientEffectLocalManifest?
  _retained_lookup_dependencies : Array[
    @publication.CapturedEffectDependencyBody,
  ]
  mut _retained_direct_evidence : Array[@run_host.ClientEffectAcquiredEvidence]
  source_imports : Array[LocalNativeMockEffectSourceImport]
  mut imports : @run_host.ClientEffectImportedEvidence?
  import_observations : Array[@run_host.ClientEffectResultImportObservation]
}

///|
priv struct LocalNativeMockEffectProposalMember {
  plan : @strategy.CapturedEffectProposalPlan
  mut capture_operation : @local_values.ClientInstalledEffectOperationBorrow?
  mut _retained_invocation : @run_host.ClientEffectLocalInvocation?
  mut _retained_capture_issue : @local_values.ClientInstalledManagedRunIssue?
  mut managed_export : @local_values.LocalValuesEffectResultExport?
  mut exported : @strategy.CapturedEffectLocalResultExport?
  mut stream : @execution.CompletedOutputExport?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut snapshot : @execution.CompletedRelationSnapshotPreparation?
  mut _retained_snapshot_wire : String?
  mut _retained_dependency : @run_host.ClientEffectDependencyCapture?
  mut _retained_definition : @run_host.ClientEffectLocalResultDefinition?
  mut _retained_artifact : @run_host.ClientEffectLocalResultArtifact?
  rows : Array[(String, String)]
}

///|
fn native_mock_effect_proposals(
  inputs : @strategy.CapturedEffectInputs,
  bridge_limits : @execution.ManagedPublicationBridgeLimits,
) -> LocalNativeMockEffectProposals {
  {
    inputs,
    bridge_limits,
    construction: None,
    publication_context: None,
    members: [],
    unit_results: [],
    _retained_keyed_identity: None,
    invocation: None,
    materials: None,
    acquired: None,
    _retained_combined_source_unit: None,
    _retained_local_manifest: None,
    _retained_lookup_dependencies: [],
    _retained_direct_evidence: [],
    source_imports: [],
    imports: None,
    import_observations: [],
  }
}

///|
fn native_mock_effect_proposal_member(
  plan : @strategy.CapturedEffectProposalPlan,
) -> LocalNativeMockEffectProposalMember {
  {
    plan,
    capture_operation: None,
    _retained_invocation: None,
    _retained_capture_issue: None,
    managed_export: None,
    exported: None,
    stream: None,
    receipt: None,
    snapshot: None,
    _retained_snapshot_wire: None,
    _retained_dependency: None,
    _retained_definition: None,
    _retained_artifact: None,
    rows: [],
  }
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_proposals(
  self : LocalCommandBusinessPreparation,
  retention : @publication.PublicationContract,
  max_capture_bytes : Int,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    state.effect_capture is Some(captured) &&
    state.effect_host is Some(host) &&
    business.request_run is Some(run) &&
    state.proposals is None else {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
  if business.model_work.is_empty() {
    self.original.with_business_request(self.capture, () => {
      state.prepare_direct_mock_effect_proposals(
        run,
        retention,
        max_capture_bytes,
        issue => {
          self.original.retain_primary(CommandBusinessEffectProposals(issue))
        },
      )
    })
    self.yield_mock_effect_proposal_workspace(state)
    return
  }
  guard business.model_work.length() == 1 && state.model_use is Some(_) else {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    // The SAME installed parent admits the actual completed entry/row controls
    // before its new callback/index/row holders are constructed.
    @local_values.begin_installed_effect_operation_controls(
      run,
      state._retained_prepared,
      state.first.request,
      state._retained_plan,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal(self.original)
    |> ignore
    let limits = state.first._retained_models[0]._retained_limits
    let wire = limits.identity.wire
    // The producer's installed IO decoder is distinct from the Model Result
    // identity codec. Borrow this SAME sealed module/DAG policy once; no bound
    // is clamped, replaced by a default or inferred from public Result names.
    let installed = @builtin.configured_local_module(
      @builtin.configured_host_modules(host),
    ).unwrap_or_else(() => stop("LocalOriginalEffectResultUnavailable"))
    let bridge_limits = @local_driver.local_publication_bridge_limits(
      installed,
      @strategy.captured_effect_run_dag(captured),
    ).unwrap_or_else(() => stop("LocalOriginalEffectResultUnavailable"))
    let inputs = @strategy.pin_captured_effect_sources(
        captured,
        limits.input.rows.metadata_entries,
        max_dependency_work=limits.output_work,
        max_dependency_depth=wire.max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Capture(issue))
      .native_effect_proposal(self.original)
    // Closed initial Host frame: this record's borrowed references and its
    // six empty Array headers stay inside the existing fixed4096 call frame.
    // Import bodies/producer exports begin only after the first capture borrow.
    let held = native_mock_effect_proposals(inputs, bridge_limits)
    state.proposals = Some(held)
    @local_values.retain_installed_effect_captured_input_inventory(
      run,
      state._retained_prepared,
      state.first.request,
      state._retained_plan,
      inputs,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal(self.original)
    for entry in 0..<@strategy.captured_effect_inputs_count(inputs) {
      let plan = @strategy.prepare_captured_effect_proposal_plan(
          inputs,
          entry,
          wire.max_columns,
          limits.output_work,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Proposal(issue))
        .native_effect_proposal(self.original)
      let staged_rows = if entry == 0 {
        @strategy.captured_effect_proposal_plan_staged_rows(plan)
      } else {
        None
      }
      let current = native_mock_effect_proposal_member(plan)
      held.members.push(current)
      // Retain the original member capture before its fallible semantic
      // constructors. The existing capture recipe backs Artifact/Preview
      // metadata; this does not consume another Model or Source allowance.
      let capture_operation = native_mock_effect_capture_operation(
          run,
          state._retained_prepared,
          state.first.request,
          state._retained_plan,
          entry,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
        .native_effect_proposal(self.original)
      current.capture_operation = Some(capture_operation)
      if entry == 0 {
        guard state._retained_import_recipes.length() == 2 else {
          stop("LocalOriginalEffectImportsUnavailable")
        }
        // The first extent is staged. Retain its original before beginning
        // input, then enter the constructor before any metadata callback.
        @local_values.prepare_installed_effect_capture_recipe_extent(
          "native.mock.file.capture",
          state._retained_import_recipes[0],
        )
        .bind(input => {
          @local_values.begin_installed_effect_operation_input(
            capture_operation, input,
          )
        })
        .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
        .native_effect_proposal(self.original)
        held.construction = Some({
          operation: capture_operation,
          recipe: state._retained_import_recipes[0],
          retained: 0L,
          workspace: 0L,
          source_snapshot: None,
          source_copy: None,
        })
      }
      if entry == 0 && state.lookup is Some(lookup) {
        // The SAME completed lookup retains actual typed requests. Its key
        // identity is shared by all members; no rows are checked or fetched
        // again and no key/ref or static request is synthesized.
        held._retained_keyed_identity = Some(
          @run_host.client_keyed_lookup_request_identity(
            lookup, 16384, 1024, 20,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Keyed(issue))
          .native_effect_proposal(self.original),
        )
      }
      if held.invocation is None {
        guard held.publication_context is None &&
          business.model_work[0].completed_observation_originals(
            limits.output_rows,
          )
          is Some((observation, invocation, _, _)) else {
          stop("LocalOriginalEffectInvocationUnavailable")
        }
        // Resolve this admitted tuple before selecting its publication policy.
        // Keep every original custody/clock/time field; the contributing Source
        // policies remain independent, and no policy or extension is granted.
        let (_, policy, _) = @publication.resolve_run_local_result_context(
            @run_host.client_effect_allowed_run_admission(state.first.allowed),
            state.first.definition,
            invocation,
            observation,
          )
          .map_err(issue => {
            LocalNativeMockEffectProposalIssue::Artifact(Context(issue))
          })
          .native_effect_proposal(self.original)
        let retention = @publication.issue_result_retention_for_data_policy(
            retention, policy, 16384, 1024, 20,
          )
          .map_err(issue => {
            LocalNativeMockEffectProposalIssue::Artifact(Scope(issue))
          })
          .native_effect_proposal(self.original)
        held.publication_context = Some((observation, invocation, retention))
        held.construction
        .unwrap()
        .retain_wire(
          self.original,
          @publication.publication_contract_json(retention),
        )
        held.materials = Some(
          @run_host.bind_prepared_client_effect_original_materials(
            state.first.allowed,
            state.first.definition,
            state.first.issued,
            request=Some(state.first.request),
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Materials(issue))
          .native_effect_proposal(self.original),
        )
        self.prepare_mock_effect_source_imports(state, held)
        let construction = held.construction.unwrap()
        let measured = staged_rows is Some(_) && held.imports is Some(_)
        if measured {
          construction
          .yield_source_import_workspace()
          .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
          .native_effect_proposal(self.original)
        } else if held.imports is Some(_) {
          if !construction.finish(
              self.original,
              state._retained_import_recipes[1],
            ) {
            stop("LocalOriginalEffectProposalsUnavailable")
          }
        }
        let mut inventory_workspace = 0L
        let before_inventory = if measured {
          Some(source_slots => {
            let frame = @local_values.installed_effect_imported_model_evidence_frame_capacity(
              source_slots, 1024, 20,
            )
            if construction.prepare_body(self.original, frame) {
              let capacity = frame.unwrap()
              inventory_workspace = @execution.execution_capacity_execution_bytes(
                  capacity,
                ) -
                @execution.execution_capacity_retained_bytes(capacity)
              true
            } else {
              false
            }
          })
        } else {
          None
        }
        let before_body = if measured {
          let cid = @publication.publication_contract_identity(
            state.first.definition,
          )
          Some((kind, geometry) => {
            construction.prepare_body(
              self.original,
              @local_values.installed_effect_imported_model_evidence_body_capacity(
                kind, geometry, cid, inventory_workspace,
              ),
            )
          })
        } else {
          None
        }
        let acquired = business.model_work[0]
          .local_effect_model_acquired_evidence(
            retention,
            16384,
            1024,
            20,
            imports=held.imports,
            before_inventory~,
            before_body~,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Source(issue))
          .native_effect_proposal(self.original)
        // Keep the actual returned originals before any later export/target
        // constructor. All members reuse this one semantic Invocation.
        held.acquired = Some(acquired)
        held.invocation = Some(
          @run_host.client_effect_model_acquired_invocation(acquired),
        )
        held._retained_direct_evidence = @run_host.client_effect_model_acquired_direct_sources(
          acquired,
        )

        // The subsequent proposal still needs its original unmetered fixed
        // allowance. Do not use that allowance for the measured Model evidence.
        if measured {
          let capture = state._retained_import_recipes[1].copy()
          capture[1] = @execution.execution_capacity(0L, 0L).unwrap()
          if !construction.finish(self.original, capture) {
            stop("LocalOriginalEffectProposalsUnavailable")
          }
        }

        if state.lookup is Some(lookup) {
          guard self.original.project is Some(project) &&
            project.mock_declarations is Some(mock) &&
            mock.file_sources is Some(files) &&
            @run_host.client_infer_plan_native_keyed_read_profile(
              state.model_graph(),
            )
            is Some(profile) else {
            stop("LocalOriginalModelKeyedPlanUnavailable")
          }
          let mut physical_source = None
          for file in files {
            for (_, binding) in file._retained_listings {
              if physical_equal(
                  binding._retained_read_profile.contract(),
                  profile,
                ) {
                guard physical_source is None &&
                  binding._retained_read_profile.physical_source_body()
                  is Some(body) else {
                  stop("LocalOriginalModelKeyedPlanUnavailable")
                }
                physical_source = Some(body)
              }
            }
          }
          guard physical_source is Some(_) else {
            stop("LocalOriginalModelKeyedPlanUnavailable")
          }
          let dependencies = @run_host.client_keyed_lookup_native_dependency_bodies(
              lookup,
              retention,
              {
                max_entries: Int::min(4096, limits.output_work),
                max_total_bytes: max_capture_bytes,
                max_depth: Int::min(64, wire.max_depth),
                max_references: Int::min(65536, limits.output_work),
              },
              wire.max_nodes,
              wire.max_depth,
              physical_source~,
            )
            .map_err(issue => {
              LocalNativeMockEffectProposalIssue::Dependency(issue)
            })
            .native_effect_proposal(self.original)
          for dependency in dependencies {
            held._retained_lookup_dependencies.push(dependency)
          }
        }
      }
      let invocation = held.invocation.unwrap()
      guard @strategy.captured_effect_input_at(inputs, entry) is Some(input) &&
        @run_host.client_effect_local_invocation_matches(
          invocation,
          state._retained_prepared,
          @strategy.captured_effect_input_stage(input),
        ) else {
        stop("LocalOriginalEffectInvocationUnavailable")
      }
      current._retained_invocation = Some(invocation)
      let mut selected = None
      for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
        if @strategy.captured_effect_local_result_matches_member(
            inputs, index, entry,
          ) {
          if selected is Some(_) {
            stop("LocalOriginalEffectResultUnavailable")
          }
          selected = Some(index)
        }
      }
      let index = selected.unwrap_or_else(() => {
        stop("LocalOriginalEffectResultUnavailable")
      })
      let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap_or_else(() => {
          stop("LocalOriginalEffectResultUnavailable")
        },
      )
      let measure_proposal_rows = staged_rows is Some(_) &&
        held.imports is Some(_)
      if measure_proposal_rows &&
        !held.construction
        .unwrap()
        .prepare_proposal_export(
          self.original,
          @strategy.captured_effect_local_result_borrow(result),
          limits,
          staged_rows.unwrap(),
        ) {
        stop("LocalOriginalEffectProposalsUnavailable")
      }
      let exported = if !@strategy.captured_any_result_borrow_requires_managed_export(
          @strategy.captured_effect_local_result_borrow(result),
        ) {
        self.prepare_mock_effect_direct_result_export(state, held, index)
      } else {
        let managed = self.prepare_mock_effect_local_result_export(
          state, held, index,
        )
        current.managed_export = Some(managed)
        managed
        .captured_export()
        .unwrap_or_else(() => stop("LocalOriginalEffectResultUnavailable"))
      }
      current.exported = Some(exported)
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
      current.stream = Some(stream)
      let construction = if entry == 0 && held.imports is Some(_) {
        held.construction
      } else {
        None
      }
      // The managed export owns its own copied prefix. For a nonempty row
      // stream keep the entire old one-row construction space before the
      // original writer emits. Rows never keep this workspace individually.
      let original_row_workspace = if measure_proposal_rows &&
        !@execution.completed_output_export_rows_complete(stream)
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original) {
        let original = state._retained_import_recipes[1]
        let fixed = original[0]
        let workspace = @execution.checked_preparation_add_product(
          @execution.execution_capacity_execution_bytes(fixed) -
          @execution.execution_capacity_retained_bytes(fixed),
          @execution.execution_capacity_retained_bytes(original[1]),
          1L,
        )
        let capacity = workspace.bind(workspace => {
          @execution.execution_capacity(0L, workspace)
        })
        if !construction.unwrap().prepare_body(self.original, capacity) {
          stop("LocalOriginalEffectProposalsUnavailable")
        }
        workspace.unwrap()
      } else {
        0L
      }
      let row_decode_workspace = Ref(0L)
      let before_decode = construction.map(construction => {
        fn(bytes, nodes, depth) {
          let capacity = @local_values.installed_effect_capture_row_decode_workspace(
            bytes, nodes, depth,
          )
          guard capacity is Some(quote) &&
            construction.prepare_body(self.original, capacity) else {
            return false
          }
          row_decode_workspace.val = @execution.execution_capacity_execution_bytes(
            quote,
          )
          true
        }
      })
      let before_encode = construction.map(construction => {
        fn(bytes, nodes, depth, prior_text_units) {
          // The exported bytes and decoded row are still held here. Keep
          // their conservative decoder envelope beside the next writer and
          // the changes String when constructing the selector.
          construction.prepare_body(
            self.original,
            native_mock_effect_proposal_write_workspace(
              Int64::max(row_decode_workspace.val, original_row_workspace),
              bytes,
              nodes,
              depth,
              prior_text_units,
            ),
          )
        }
      })
      // The row and its encoded batch are local to this synchronous return.
      // Only the selector/changes pair crosses into the growing member array.
      let next_proposal = fn() raise ClientStop {
        guard @execution.next_completed_output_export_canonical_row(
            stream,
            wire.max_nodes,
            wire.max_depth,
            limits.output_work,
            before_decode~,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
          .native_effect_proposal(self.original)
          is Some((row_index, _, row)) else {
          return None
        }
        Some(
          @strategy.project_captured_effect_proposal_row(
            plan,
            row,
            row_index,
            wire.max_columns,
            limits.output_work,
            wire.max_bytes,
            wire.max_nodes,
            wire.max_depth,
            before_encode~,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Proposal(issue))
          .native_effect_proposal(self.original),
        )
      }
      while next_proposal() is Some(proposal) {
        if measure_proposal_rows {
          construction
          .unwrap()
          .append_proposal_row(current.rows, proposal)
          .native_effect_proposal(self.original)
        } else {
          current.rows.push(proposal)
        }
      }
      let (receipt, _) = @execution.finish_completed_relation_export(stream)
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original)
      current.receipt = Some(receipt)
      if !@strategy.captured_effect_local_result_export_matches_receipt(
          inputs, exported, receipt,
        ) {
        stop("LocalOriginalEffectResultUnavailable")
      }
      let definition = @run_host.issue_captured_client_effect_local_result_definition(
          state._retained_prepared,
          inputs,
          entry,
          16384,
          1024,
          20,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Definition(issue))
        .native_effect_proposal(self.original)
      current._retained_definition = Some(definition)
      let artifact = business.model_work[0]
        .local_effect_model_artifact(
          held.materials.unwrap(),
          inputs,
          exported,
          held.acquired.unwrap(),
          definition,
          receipt,
          16384,
          1024,
          20,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Artifact(issue))
        .native_effect_proposal(self.original)
      current._retained_artifact = Some(artifact)
      // Preserve the SAME finished export/receipt. This first durable row
      // snapshot neither re-exports a Result nor reruns its identity scan.
      if measure_proposal_rows {
        let (bytes, nodes, _, depth) = @execution.completed_relation_export_snapshot_extent(
            stream, receipt,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
          .native_effect_proposal(self.original)
        if !construction
          .unwrap()
          .prepare_snapshot(
            self.original,
            Int::max(1, bytes),
            Int::max(1, nodes),
            Int::max(1, depth),
            previous_workspace_returned=true,
          ) {
          stop("LocalOriginalEffectProposalsUnavailable")
        }
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
      current.snapshot = Some(snapshot)
      while !snapshot
            .advance(256)
            .map_err(issue => {
              LocalNativeMockEffectProposalIssue::Completed(issue)
            })
            .native_effect_proposal(self.original).0 {
        ()
      }
      let (rows_wire, _) = snapshot
        .finish()
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original)
      // Only the returned immutable wire survives this synchronous writer.
      // Drop the closed writer/workspace before yielding capture scratch.
      snapshot.cancel()
      current.snapshot = None
      current._retained_snapshot_wire = Some(rows_wire)
      current._retained_dependency = Some(
        @run_host.admit_client_effect_dependency_capture(
          held.materials.unwrap(),
          inputs,
          artifact,
          index,
          exported,
          receipt,
          rows_wire,
          max_capture_bytes,
          wire.max_nodes,
          wire.max_depth,
          before_body=Some((bytes, nodes, depth) => {
            held.construction
            .unwrap()
            .prepare_canonical(self.original, bytes, nodes, depth)
          }),
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Dependency(issue))
        .native_effect_proposal(self.original),
      )
      @strategy.finish_captured_effect_proposal_plan(
        plan,
        current.rows.length(),
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Proposal(issue))
      .native_effect_proposal(self.original)
    }
    // The owner requires every declared Result and Effect-consumed Table of
    // the Unit. A consumed subset must not be presented as a whole Manifest.
    self.prepare_mock_effect_unit_results(state, held, max_capture_bytes)
    let artifacts = held.members.map(entry => entry._retained_artifact.unwrap())
    for result in held.unit_results {
      artifacts.push(result.artifact.unwrap())
    }
    held._retained_local_manifest = Some(
      @run_host.issue_client_effect_local_manifest(
        state._retained_prepared,
        held.invocation.unwrap(),
        artifacts,
        max_capture_bytes,
        wire.max_nodes,
        wire.max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Manifest(issue))
      .native_effect_proposal(self.original),
    )
  })
  self.yield_mock_effect_proposal_workspace(state)
}

///|
fn LocalCommandBusinessPreparation::yield_mock_effect_proposal_workspace(
  self : LocalCommandBusinessPreparation,
  state : LocalNativeMockEffectPlan,
) -> Unit raise ClientStop {
  // The entire proposal/Manifest constructor frame has returned. Its owned
  // originals remain on `held`; only that phase's private scratch can return
  // before the separate target reader. No physical child is acknowledged.
  self.original.with_business_request(self.capture, () => {
    guard state.proposals is Some(held) &&
      held.construction is Some(construction) else {
      stop("LocalOriginalEffectProposalsUnavailable")
    }
    let yielded = if held.imports is Some(_) {
      // The imported Model path has independently selected the warm recipe
      // used by Preview. Its prior proposal scratch has no remaining alias.
      construction.yield_returned_workspace()
    } else {
      @local_values.yield_installed_effect_operation_construction_workspace(
        construction.operation,
      )
    }
    yielded
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal(self.original)
  })
}

///|
// Retire pure Core child continuations before returning their actual Result
// pins. No file, pending write, Store or physical owner is acknowledged here.
fn LocalNativeMockEffectProposals::close(self : Self) -> Bool {
  // Shared pure dependency aliases retire before their first member capture
  // backing. Physical pins and every partial child still close below through
  // the original owners; clearing metadata is never a physical ACK.
  self.acquired = None
  self._retained_combined_source_unit = None
  self.imports = None
  self.import_observations.clear()
  for source in self.source_imports {
    source.close_export()
  }
  self.source_imports.clear()
  self._retained_local_manifest = None
  // Direct Effect members borrow their Result owners' retained evidence.
  for entry in self.members {
    entry._retained_artifact = None
    entry._retained_dependency = None
    entry._retained_snapshot_wire = None
  }
  for result in self.unit_results {
    result.close()
  }
  self.unit_results.clear()
  self._retained_lookup_dependencies.clear()
  self.materials = None
  self.publication_context = None
  self._retained_keyed_identity = None
  self.invocation = None
  self._retained_direct_evidence.clear()
  for entry in self.members {
    if entry.snapshot is Some(snapshot) {
      snapshot.cancel()
      entry.snapshot = None
    }
    entry._retained_definition = None
    @strategy.cancel_captured_effect_proposal_plan(entry.plan)
    if entry.receipt is Some(receipt) {
      @execution.cancel_completed_relation_export_receipt(receipt)
      entry.receipt = None
    }
    if entry.stream is Some(stream) {
      @execution.cancel_completed_output_export(stream)
      entry.stream = None
    }
    if entry.exported is Some(exported) {
      @execution.cancel_completed_result_relation_export(
        @strategy.captured_effect_local_result_export_preparation(exported),
      )
      |> ignore
      entry.exported = None
    }
    if entry.managed_export is Some(exported) {
      exported.close()
      entry.managed_export = None
    }
    entry.rows.clear()
    entry._retained_invocation = None
    if entry.capture_operation is Some(operation) {
      match @local_values.retire_installed_effect_operation(operation, true) {
        Err(issue) => {
          entry._retained_capture_issue = Some(issue)
          return false
        }
        Ok(false) => return false
        Ok(true) => {
          entry.capture_operation = None
          entry._retained_capture_issue = None
        }
      }
    }
  }
  self.construction = None
  @strategy.release_captured_effect_inputs(self.inputs)
}

///|
// Add the observed output writer to the still-live row/projection workspace.
// prior_text_units is the length of the co-held returned changes wire.
fn native_mock_effect_proposal_write_workspace(
  row_decode_workspace : Int64,
  bytes : Int,
  nodes : Int,
  depth : Int,
  prior_text_units : Int,
) -> @execution.ExecutionCapacity? {
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: writer.record_headers + 3L,
    reference_slots: writer.reference_slots + 2L,
    scalar_words: writer.scalar_words + 6L,
    owned_utf16_units: writer.owned_utf16_units + prior_text_units.to_int64(),
    owned_wire_bytes: 0L,
  })
  .bind(workspace => {
    @execution.checked_preparation_add_product(
      row_decode_workspace, workspace, 1L,
    )
  })
  .bind(workspace => @execution.execution_capacity(0L, workspace))
}

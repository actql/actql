///|
// Caller-held public evidence and the original bounded export/issuance
// continuations. They reuse the same captured Run and grant no durable save,
// waiting, approval, mutation or physical cleanup acknowledgement.
priv struct LocalNativeMockEffectComputation {
  outputs : Array[@run_host.PublicationOutputExport]
  managed_outputs : Array[@local_values.LocalValuesResultExport]
  definitions : Array[@publication.PublicationContract]
  artifacts : Array[@publication.PublicationContract]
  snapshots : Array[@publication.CapturedResultSnapshot]
  derivations : Array[@publication.PublicationContract]
  orderings : Array[@publication.PublicationContract]
  retentions : Array[@publication.PublicationContract]
  schema_wires : Array[String]
  codec_cids : Array[String]
  mut _retained_manifest : @publication.PublicationContract?
  mut _retained_receipt : @publication.PublicationContract?
  mut issuer : @publication.CapturedRunIssuancePreparation?
  mut _retained_captured : @publication.PublicationContract?
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_computation(
  self : Self,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) else {
    stop("LocalOriginalEffectComputationUnavailable")
  }
  let max_bytes = native_mock_effect_record_bytes(installation)
  self.original.with_business_request(self.capture, () => {
    let limits : @run_host.PublicationOutputExportLimits = match
      state.first._retained_models.get(0) {
      Some(model) => {
        let limits = model._retained_limits
        let wire = limits.identity.wire
        {
          max_result_fields: wire.max_columns,
          max_result_mapping_work: wire.max_order_work,
          max_result_order_work: wire.max_order_work,
          max_result_workspace_entries: limits.output_workspace,
          max_rows: limits.output_rows,
          values: limits.output_values,
          payload_wire: wire,
          logical_wire: limits.identity.logical_wire,
          schema: limits.identity.schema,
          max_batch_bytes: Int::min(wire.max_bytes, 16384),
        }
      }
      None => {
        guard business.request_run is Some(run) else {
          stop("LocalOriginalEffectComputationUnavailable")
        }
        @local_values.installed_effect_managed_publication_limits(
          run,
          state._retained_prepared,
          state.first.request,
          state._retained_plan,
          max_bytes,
        ).unwrap_or_else(() => stop("LocalOriginalEffectComputationUnavailable"))
      }
    }
    state.build_mock_effect_computation(
      limits,
      max_bytes,
      issue => {
        self.original.retain_primary(CommandBusinessEffectProposals(issue))
      },
      managed_run=business.request_run,
    )
  })
}

///|
fn LocalNativeMockEffectPlan::build_mock_effect_computation(
  state : Self,
  limits : @run_host.PublicationOutputExportLimits,
  max_bytes : Int,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
  managed_run? : @local_values.ClientInstalledManagedRun? = None,
) -> Unit raise ClientStop {
  guard state.effect_capture is Some(captured) &&
    state.proposals is Some(proposals) &&
    proposals.materials is Some(materials) &&
    (
      proposals.acquired is Some(_) ||
      proposals._retained_combined_source_unit is Some(_)
    ) &&
    state.preview is Some(preview) &&
    preview._retained_dependency_inventory is Some(inventory) &&
    state.suffix is Some(execution) &&
    proposals.construction is Some(construction) &&
    state.computation is None else {
    stop("LocalOriginalEffectComputationUnavailable")
  }
  let wire = limits.payload_wire
  let policy = @run_host.client_standard_effect_computation_limits()
  let max_nodes = policy.effects.max_admission_nodes
  let max_depth = policy.effects.max_admission_depth
  if proposals._retained_combined_source_unit is Some(_) {
    // Dependency construction returned its scratch. Re-enter the original
    // capture workspace before issuing the public receipt and snapshot.
    construction
    .resize_result(
      construction.recipe,
      construction.retained,
      construction.workspace,
    )
    .native_effect_proposal_with_cause(report)
  }
  let held : LocalNativeMockEffectComputation = {
    outputs: [],
    managed_outputs: [],
    definitions: [],
    artifacts: [],
    snapshots: [],
    derivations: [],
    orderings: [],
    retentions: [],
    schema_wires: [],
    codec_cids: [],
    _retained_manifest: None,
    _retained_receipt: None,
    issuer: None,
    _retained_captured: None,
  }
  state.computation = Some(held)
  let run = @strategy.captured_effect_run_dag(captured)
  // A measured Model proposal already completed and retained the same
  // exports for its members and other Unit Results. Reuse those pins and
  // receipts under the original public limits instead of copying rows again.
  let reuse_original_exports = proposals._retained_combined_source_unit
    is Some(_) ||
    (
      proposals.imports is Some(_) &&
      proposals.members
      .get(0)
      .bind(entry => {
        @strategy.captured_effect_proposal_plan_staged_rows(entry.plan)
      })
      is Some(_)
    )
  let bridge = proposals.bridge_limits
  let row = bridge.row
  for
    index in 0..<@strategy.graph_result_count(@strategy.captured_dag_graph(run)) {
    if reuse_original_exports {
      guard proposals.original_public_result_export(materials, index)
        is Some((original, stream, receipt)) else {
        stop("LocalOriginalEffectComputationResultUnavailable")
      }
      let output = @run_host.borrow_captured_effect_result_publication_export(
          captured,
          proposals.inputs,
          index,
          original,
          stream,
          receipt,
          limits,
        )
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::PublicExport(issue)
        })
        .native_effect_proposal_with_cause(report)
      held.outputs.push(output)
      continue
    }
    let output = execution
      .prepare_captured_result_export(
        run,
        index,
        row,
        bridge.entries,
        bridge.name_bytes,
        limits,
        reserve_row_copy=Some((bytes, decoder) => {
          construction
          .reserve_row_copy(bytes, decoder)
          .retain_mock_effect_proposal_issue(report)
        }),
      )
      .map_err(issue => {
        LocalNativeMockEffectProposalIssue::ManagedPublicExport(issue)
      })
      .native_effect_proposal_with_cause(report)
    held.managed_outputs.push(output)
    held.outputs.push(output.output_export())
  }
  for index, output in held.outputs {
    // Public Named Results include the complete Unit, including
    // Results outside the Effect members. Select by the same checked
    // occurrence; neither equal rows nor an export failure chooses a source.
    let consumed = proposals.members
      .iter()
      .find_first(entry => {
        entry._retained_artifact
        .map(artifact => {
          @run_host.client_effect_local_result_artifact_matches_public_result(
            materials.prepared,
            proposals.inputs,
            artifact,
            index,
          )
        })
        .unwrap_or(false)
      })
      .bind(entry => entry._retained_artifact)
    let original = match consumed {
      Some(artifact) => artifact
      None =>
        proposals.unit_results
        .iter()
        .find_first(entry => {
          entry.artifact
          .map(artifact => {
            @run_host.client_effect_local_result_artifact_matches_public_result(
              materials.prepared,
              proposals.inputs,
              artifact,
              index,
            )
          })
          .unwrap_or(false)
        })
        .bind(entry => entry.artifact)
        .unwrap_or_else(() => {
          stop("LocalOriginalEffectComputationResultUnavailable")
        })
    }
    let (computation, relations, scope, data_policy, authority) = (match
        (proposals.acquired, proposals._retained_combined_source_unit) {
        (Some(acquired), None) =>
          @run_host.client_effect_model_public_result_evidence_refs(
            materials,
            proposals.inputs,
            acquired,
            original,
            index,
            preview._retained_invocation,
            preview._retained_observation,
          )
        (None, Some(combined)) =>
          @run_host.client_effect_combined_source_public_result_evidence_refs(
            materials,
            proposals.inputs,
            combined,
            original,
            index,
            preview._retained_invocation,
            preview._retained_observation,
          )
        _ => Err(ForeignOwner)
      })
      .map_err(issue => LocalNativeMockEffectProposalIssue::Artifact(issue))
      .native_effect_proposal_with_cause(report)
    if !reuse_original_exports {
      while true {
        match
          output
          .next()
          .map_err(issue => {
            LocalNativeMockEffectProposalIssue::PublicExport(issue)
          })
          .native_effect_proposal_with_cause(report) {
          Some(_) => ()
          None => break
        }
      }
      output
      .finish()
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal_with_cause(report)
      |> ignore
    }
    output
    .issue_result_evidence(
      computation, relations, scope, data_policy, authority, max_bytes, max_nodes,
      max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
    .native_effect_proposal_with_cause(report)
    |> ignore
    held.definitions.push(
      output
      .definition()
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal_with_cause(report),
    )
    held.artifacts.push(
      output
      .issue_artifact(
        preview._retained_invocation,
        @run_host.client_effect_local_result_retention(original),
        max_bytes,
        max_nodes,
        max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal_with_cause(report),
    )
    // Retain the actual public Result occurrence evidence before its
    // original local artifact/export can retire. Cold publication borrows
    // these exact bodies; Preview rows never issue replacement evidence.
    held.derivations.push(
      output
      .derivation()
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal_with_cause(report),
    )
    held.orderings.push(
      output
      .ordering()
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal_with_cause(report),
    )
    held.retentions.push(
      @run_host.client_effect_local_result_retention(original),
    )
    held.schema_wires.push(
      output
      .result_schema_wire()
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal_with_cause(report),
    )
    held.codec_cids.push(
      output
      .codec_contract_cid()
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal_with_cause(report),
    )
    held.snapshots.push(
      output
      .admit_captured_snapshot(max_bytes, max_nodes, max_depth)
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal_with_cause(report),
    )
  }
  let manifest = @publication.issue_result_manifest(
      materials.run_definition,
      preview._retained_invocation,
      held.definitions,
      held.artifacts,
      max_bytes,
      max_nodes,
      max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PublicManifest(issue))
    .native_effect_proposal_with_cause(report)
  held._retained_manifest = Some(manifest)
  let journal = @run_host.restore_client_effect_run_normalization(materials)
    .map_err(issue => {
      LocalNativeMockEffectProposalIssue::PublicNormalization(issue)
    })
    .native_effect_proposal_with_cause(report)
  // This existing Owner admits only the original finite empty binding
  // inventory and matches the actual compiler Template before Receipt use.
  @run_host.client_effect_run_receipt_bindings(
    materials, max_bytes, max_nodes, max_depth,
  )
  .map_err(issue => LocalNativeMockEffectProposalIssue::PublicBindings(issue))
  .native_effect_proposal_with_cause(report)
  |> ignore
  let receipt = @publication.issue_effect_free_run_receipt(
      @run_host.client_effect_allowed_run_admission(materials.allowed),
      materials.run_definition,
      preview._retained_invocation,
      preview._retained_observation,
      held.definitions,
      held.artifacts,
      manifest,
      journal,
      [],
      [],
      preview._retained_source_observations,
      preview._retained_models,
      [],
      max_bytes,
      max_nodes,
      max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PublicReceipt(issue))
    .native_effect_proposal_with_cause(report)
  held._retained_receipt = Some(receipt)
  if proposals._retained_combined_source_unit is Some(_) {
    guard managed_run is Some(managed) else {
      stop("LocalOriginalEffectComputationUnavailable")
    }
    state.issue_direct_mock_effect_capture(
      managed,
      proposals,
      construction,
      materials,
      preview,
      inventory,
      held,
      wire.max_columns,
      policy.effects.max_work,
      max_bytes,
      max_nodes,
      max_depth,
      report,
    )
    return
  }
  let issuer = @run_host.prepare_client_effect_captured_run(
      materials,
      proposals.inputs,
      preview.inputs,
      preview.proofs,
      preview._retained_invocation,
      held.definitions,
      held.artifacts,
      manifest,
      receipt,
      held.snapshots,
      preview._retained_captured_sources,
      preview._retained_local_sources,
      inventory,
      preview._retained_authoring,
      wire.max_columns,
      policy.effects.max_work,
      max_bytes,
      max_nodes,
      max_depth,
      limits.max_result_workspace_entries,
      models=preview._retained_models,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PublicCapture(issue))
    .native_effect_proposal_with_cause(report)
  held.issuer = Some(issuer)
  while !issuer
        .advance(64)
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::CapturedSource(issue)
        })
        .native_effect_proposal_with_cause(report).0 {
    ()
  }
  held._retained_captured = Some(
    issuer
    .finish_retained()
    .map_err(issue => LocalNativeMockEffectProposalIssue::CapturedSource(issue))
    .native_effect_proposal_with_cause(report),
  )
}

///|
// Pin selection is by the same public Result occurrence and the same inputs.
// The original proposal record remains the sole owner of the export and
// receipt. A selected incomplete export is a refusal, even for equal rows.
fn LocalNativeMockEffectProposals::original_public_result_export(
  self : Self,
  materials : @run_host.ClientEffectRunMaterials,
  index : Int,
) -> (
  @strategy.CapturedEffectLocalResultExport,
  @execution.CompletedOutputExport,
  @execution.CompletedRelationExportReceipt,
)? {
  let matches = fn(artifact) {
    @run_host.client_effect_local_result_artifact_matches_public_result(
      materials.prepared,
      self.inputs,
      artifact,
      index,
    )
  }
  if self.acquired is Some(_) &&
    self.members
    .iter()
    .find_first(entry => entry._retained_artifact.map(matches).unwrap_or(false))
    is Some(entry) {
    guard entry.exported is Some(original) &&
      entry.stream is Some(stream) &&
      entry.receipt is Some(receipt) else {
      return None
    }
    return Some((original, stream, receipt))
  }
  guard self.unit_results
    .iter()
    .find_first(entry => entry.artifact.map(matches).unwrap_or(false))
    is Some(entry) &&
    entry.exported is Some(original) &&
    entry.stream is Some(stream) &&
    entry.receipt is Some(receipt) else {
    return None
  }
  Some((original, stream, receipt))
}

///|
fn LocalNativeMockEffectPlan::issue_direct_mock_effect_capture(
  state : Self,
  run : @local_values.ClientInstalledManagedRun,
  proposals : LocalNativeMockEffectProposals,
  construction : LocalNativeMockEffectImportConstruction,
  materials : @run_host.ClientEffectRunMaterials,
  preview : LocalNativeMockEffectPreview,
  inventory : @publication.CapturedEffectDependencyInventory,
  held : LocalNativeMockEffectComputation,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> Unit raise ClientStop {
  let prepared = state._retained_prepared
  let request = state.first.request
  let plan = state._retained_plan
  let identity = @strategy.captured_effect_preview_ledger_identity(
    preview.inputs,
  )
  let slots = held.definitions.length().to_int64() +
    held.artifacts.length().to_int64() +
    held.snapshots.length().to_int64() +
    preview._retained_captured_sources.length().to_int64() +
    preview._retained_local_sources.length().to_int64() +
    2L * @publication.effect_preview_member_count(identity).to_int64()
  if slots > 2147483647L {
    report(Managed(InsufficientCapacity))
    stop("LocalOriginalEffectComputationUnavailable")
  }
  @local_values.yield_installed_effect_operation_construction_workspace(
    construction.operation,
  )
  .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
  .native_effect_proposal_with_cause(report)
  @local_values.reserve_installed_effect_dependency_capture(
    run,
    prepared,
    request,
    plan,
    materials.run_definition,
    preview._retained_invocation,
    slots.to_int(),
  )
  .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
  .native_effect_proposal_with_cause(report)
  construction
  .resize_result(
    construction.recipe,
    construction.retained,
    construction.workspace,
  )
  .native_effect_proposal_with_cause(report)
  let names : Array[String] = []
  let wires : Array[String] = []
  @run_host.visit_client_effect_captured_plan_wires(
    materials,
    proposals.inputs,
    preview.inputs,
    preview.proofs,
    preview._retained_invocation,
    max_fields,
    max_work,
    max_bytes,
    max_nodes,
    max_depth,
    (name, wire) => {
      names.push(name)
      wires.push(wire)
    },
    before_wire=Some((bytes, nodes, depth) => {
      construction
      .prepare_body_result(
        native_mock_effect_plan_wire_capacity(bytes, nodes, depth),
      )
      .retain_mock_effect_proposal_issue(report)
    }),
  )
  .map_err(issue => LocalNativeMockEffectProposalIssue::PublicCapture(issue))
  .native_effect_proposal_with_cause(report)
  @local_values.yield_installed_effect_operation_construction_workspace(
    construction.operation,
  )
  .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
  .native_effect_proposal_with_cause(report)
  let issuer = @local_values.begin_installed_effect_dependency_capture(
      run,
      prepared,
      request,
      plan,
      materials.run_definition,
      preview._retained_invocation,
      held.definitions,
      held.artifacts,
      held._retained_manifest.unwrap(),
      held._retained_receipt.unwrap(),
      held.snapshots,
      preview._retained_captured_sources,
      preview._retained_local_sources,
      [],
      preview._retained_authoring,
      [],
      identity,
      names,
      wires,
      @publication.captured_effect_dependency_inventory_json(inventory),
      [],
      max_bytes,
      max_nodes,
      max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal_with_cause(report)
  // The installed owner retains this same issuer and the captured plan inputs.
  // Every advance rechecks the owner and charges the original Work inventory.
  while !@local_values.advance_installed_effect_dependency_capture(
          run, prepared, request, plan, issuer, 64,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
        .native_effect_proposal_with_cause(report) {
    ()
  }
  let captured = @local_values.finish_installed_effect_dependency_capture(
      run, prepared, request, plan, issuer,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal_with_cause(report)
  held._retained_captured = Some(
    @publication.prepared_captured_effect_run_contract(captured),
  )
}

///|
// These plans return the wire only. The installed capture constructor quotes
// the later parsed plans alongside the original Capture and dependency tree.
fn native_mock_effect_plan_wire_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: bytes.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(execution) else {
    return None
  }
  @execution.execution_capacity(retained, execution)
}

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
  let values_publication = state.direct_sources.bind(value => {
    value._retained_values_publication
  })
  guard state.effect_capture is Some(captured) &&
    state.proposals is Some(proposals) &&
    proposals.materials is Some(materials) &&
    (
      proposals.acquired is Some(_) ||
      proposals._retained_combined_source_unit is Some(_) ||
      values_publication is Some(_)
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
  let direct = proposals._retained_combined_source_unit is Some(_) ||
    values_publication is Some(_)
  if direct {
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
  let measured_capture = proposals.measured_model_capture
  let reuse_original_exports = direct || measured_capture
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
        (None, Some(combined)) if proposals.imports is Some(imported) => {
          let retention = @run_host.client_effect_local_result_retention(
            original,
          )
          if @run_host.client_effect_imported_matches_direct_source_unit(
              imported,
              combined,
              retention,
              preview._retained_invocation,
              preview._retained_observation,
            ) {
            @run_host.client_effect_imported_result_evidence_refs(
              materials,
              proposals.inputs,
              imported,
              preview._retained_invocation,
              preview._retained_observation,
              retention,
            )
          } else {
            Err(ForeignOwner)
          }
        }
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
        (None, None) if values_publication is Some(publication) =>
          native_mock_values_public_result_evidence(
            materials, original, publication, preview,
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
  let manifest_funding = if measured_capture {
    let mut inventory = 0L
    let before_inventory = fn(count) {
      let capacity = native_mock_effect_public_manifest_inventory(
        count, max_depth,
      )
      if construction
        .prepare_body_result(
          capacity.bind(bytes => @execution.execution_capacity(0L, bytes)),
        )
        .retain_mock_effect_proposal_issue(report) {
        inventory = capacity.unwrap()
        true
      } else {
        false
      }
    }
    let before_material = fn(bytes, nodes, depth) {
      construction
      .prepare_body_result(
        native_mock_effect_public_manifest_capacity(
          held.definitions.length(),
          bytes,
          nodes,
          depth,
          max_bytes,
          max_nodes,
          inventory,
        ),
      )
      .retain_mock_effect_proposal_issue(report)
    }
    Some((before_inventory, before_material))
  } else {
    None
  }
  let manifest = @publication.issue_result_manifest(
      materials.run_definition,
      preview._retained_invocation,
      held.definitions,
      held.artifacts,
      max_bytes,
      max_nodes,
      max_depth,
      funding=manifest_funding,
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
  let receipt_funding = if measured_capture {
    let mut inventory = 0L
    let before_inventory = fn(slots) {
      let capacity = native_mock_effect_receipt_inventory(slots, max_depth)
      if construction
        .prepare_body_result(
          capacity.bind(bytes => @execution.execution_capacity(0L, bytes)),
        )
        .retain_mock_effect_proposal_issue(report) {
        inventory = capacity.unwrap()
        true
      } else {
        false
      }
    }
    let before_material = fn(bytes, nodes, depth) {
      construction
      .prepare_body_result(
        native_mock_effect_receipt_body_capacity(
          bytes, nodes, depth, max_bytes, max_nodes, inventory,
        ),
      )
      .retain_mock_effect_proposal_issue(report)
    }
    Some((before_inventory, before_material))
  } else {
    None
  }
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
      funding=receipt_funding,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PublicReceipt(issue))
    .native_effect_proposal_with_cause(report)
  held._retained_receipt = Some(receipt)
  if direct {
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
  let issuer = if measured_capture {
    guard preview._retained_dependency_geometry is Some(geometry) else {
      report(CapturedSource(CaptureIssuanceEncoding))
      stop("LocalOriginalEffectComputationUnavailable")
    }
    native_mock_effect_measured_capture(
      construction,
      materials,
      proposals.inputs,
      preview,
      held,
      inventory,
      geometry,
      wire.max_columns,
      policy.effects.max_work,
      max_bytes,
      max_nodes,
      max_depth,
      limits.max_result_workspace_entries,
      report,
    )
  } else {
    @run_host.prepare_client_effect_captured_run(
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
  }
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
fn native_mock_values_public_result_evidence(
  materials : @run_host.ClientEffectRunMaterials,
  artifact : @run_host.ClientEffectLocalResultArtifact,
  publication : @run_host.ClientEffectSourceFreeInvocationOriginal,
  preview : LocalNativeMockEffectPreview,
) -> Result[
  (String, Array[String], String, String, String),
  @run_host.ClientEffectLocalResultArtifactIssue,
] {
  guard @run_host.client_effect_source_free_result_original_scope(
      artifact, publication,
    )
    is Some(scope) &&
    physical_equal(
      preview._retained_observation,
      @run_host.client_effect_source_free_invocation_original_observation(
        publication,
      ),
    ) &&
    physical_equal(
      preview._retained_invocation,
      @run_host.client_effect_source_free_invocation_original_invocation(
        publication,
      ),
    ) else {
    return Err(ForeignInvocation)
  }
  @publication.resolve_run_local_result_evidence_refs(
    @run_host.client_effect_allowed_run_admission(materials.allowed),
    materials.run_definition,
    preview._retained_invocation,
    preview._retained_observation,
    @run_host.client_effect_local_result_retention(artifact),
  )
  .map_err(issue => {
    @run_host.ClientEffectLocalResultArtifactIssue::Context(issue)
  })
  .map(value => {
    (
      @publication.publication_contract_identity(
        @run_host.client_effect_compilation_compiled_plan(materials.compilation),
      ),
      [],
      @publication.publication_contract_identity(scope),
      value.1,
      value.2,
    )
  })
}

///|
// Retain the checked Model computation's typed inputs and private plan on
// its original capture operation. No installed direct-Source publication
// binding or second dependency owner is needed for this path.
fn native_mock_effect_measured_capture(
  construction : LocalNativeMockEffectImportConstruction,
  materials : @run_host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  preview : LocalNativeMockEffectPreview,
  held : LocalNativeMockEffectComputation,
  inventory : @publication.CapturedEffectDependencyInventory,
  geometry : @encode.EncodingConstructionGeometry,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> @publication.CapturedRunIssuancePreparation raise ClientStop {
  let identity = @strategy.captured_effect_preview_ledger_identity(
    preview.inputs,
  )
  let members = @publication.effect_preview_member_count(identity)
  let slots = held.definitions.length().to_int64() +
    held.artifacts.length().to_int64() +
    held.snapshots.length().to_int64() +
    preview._retained_captured_sources.length().to_int64() +
    preview._retained_local_sources.length().to_int64() +
    preview._retained_models.length().to_int64() +
    2L * members.to_int64()
  let fixed = if slots <= 2147483647L {
    @local_values.installed_effect_dependency_fixed_capacity(
      slots.to_int(),
      0,
      max_depth,
    )
  } else {
    None
  }
  construction
  .prepare_body_result(fixed)
  .native_effect_proposal_with_cause(report)
  let names : Array[String] = []
  let wires : Array[String] = []
  @run_host.visit_client_effect_captured_plan_wires(
    materials,
    inputs,
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
  let plan = @publication.prepare_original_effectful_capture_plan(
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
    preview._retained_models,
    identity,
    names,
    wires,
    inventory,
    geometry,
    [],
    max_bytes,
    max_nodes,
    max_depth,
    _ => true,
    original_limits=Some((max_bytes, max_nodes, max_depth, max_workspace)),
  ).unwrap_or_else(() => {
    report(CapturedSource(CaptureIssuanceEncoding))
    stop("LocalOriginalEffectComputationUnavailable")
  })
  defer @publication.cancel_capture_construction_plan(plan)
  construction
  .prepare_body_result(
    @local_values.installed_effect_capture_constructor_capacity(
      plan,
      @publication.captured_effect_dependency_inventory_count(inventory),
      preview._retained_captured_sources.length(),
      preview._retained_local_sources.length(),
      0,
      members,
      0,
      wires,
      max_bytes,
      max_nodes,
      max_depth,
      _ => true,
    ),
  )
  .native_effect_proposal_with_cause(report)
  @publication.start_planned_captured_run(plan).unwrap_or_else(() => {
    report(CapturedSource(CaptureIssuanceEncoding))
    stop("LocalOriginalEffectComputationUnavailable")
  })
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

///|
// The measured Artifact subtrees are already admitted. Only the root and
// names use unordered keys, with one growing vector and the two pairing maps.
fn native_mock_effect_public_manifest_inventory(
  count : Int,
  depth : Int,
) -> Int64? {
  if count > 2147483643 {
    return None
  }
  let count64 = count.to_int64()
  guard @shape.collection_construction_extent({
      records: 15L + 4L * count64 + 2L * depth.to_int64(),
      record_references: 20L + 8L * count64 + 2L * depth.to_int64(),
      record_words: 18L + 3L * count64 + 2L * depth.to_int64(),
      reference_arrays: 3L,
      reference_items: 3L * count64 + depth.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: 2L * count64,
    })
    is Some(inventory) &&
    @encode.measuring_writer_construction_extent(count + 4, depth)
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: inventory.record_headers + writer.record_headers,
    reference_slots: inventory.reference_slots + writer.reference_slots,
    scalar_words: inventory.scalar_words + writer.scalar_words,
    owned_utf16_units: 64L,
    owned_wire_bytes: 0L,
  })
}

///|
fn native_mock_effect_public_manifest_capacity(
  count : Int,
  bytes : Int,
  nodes : Int,
  depth : Int,
  max_bytes : Int,
  max_nodes : Int,
  inventory : Int64,
) -> @execution.ExecutionCapacity? {
  // The self-CID key adds one String node and under 100 ASCII bytes.
  // The measured body already includes the original Artifact subtrees.
  let sealed_bytes = Int64::min(max_bytes.to_int64(), bytes.to_int64() + 100L).to_int()
  let sealed_nodes = Int64::min(max_nodes.to_int64(), nodes.to_int64() + 1L).to_int()
  let skeleton_nodes = Int64::min(
    sealed_nodes.to_int64(),
    count.to_int64() + 6L,
  ).to_int()
  guard native_mock_effect_canonical_body_capacity(
      sealed_bytes,
      skeleton_nodes,
      Int::min(2, depth),
    )
    is Some(skeleton) &&
    @encode.text_writer_live_key_inventory(sealed_bytes, 0, depth)
    is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, depth) is Some(hash) &&
    @shape.collection_construction_extent({
      // Shape/schema checks over the complete borrowed Artifact tree, plus
      // the patched result/root arrays and the root validator/emit cursors.
      records: 32L + 8L * sealed_nodes.to_int64() + 3L * count.to_int64(),
      record_references: 40L +
      40L * sealed_nodes.to_int64() +
      5L * count.to_int64(),
      record_words: 36L + 32L * sealed_nodes.to_int64() + 3L * count.to_int64(),
      reference_arrays: 9L,
      reference_items: 8L * sealed_nodes.to_int64() + 4L * count.to_int64(),
      scalar_arrays: 1L,
      scalar_items: sealed_nodes.to_int64(),
      maps: 1L,
      map_entries: sealed_nodes.to_int64(),
    })
    is Some(controls) &&
    @execution.preparation_representation_cost({
      record_headers: controls.record_headers +
      writer.record_headers +
      hash.record_headers,
      reference_slots: controls.reference_slots +
      writer.reference_slots +
      hash.reference_slots,
      scalar_words: controls.scalar_words +
      writer.scalar_words +
      hash.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(workspace) &&
    @execution.checked_preparation_add_product(inventory, workspace, 1L)
    is Some(workspace) &&
    @execution.execution_capacity(0L, workspace) is Some(extra) else {
    return None
  }
  // Only the new root/skeleton and its final wire are charged on retention.
  // Nested Artifacts remain the original already-backed borrows.
  @execution.add_execution_capacity(skeleton, extra)
}

///|
// Exact evidence vectors from the original inputs and one measuring writer.
// The receipt emitter opens only its root and small binding/evidence records
// as unordered objects; borrowed canonical subtrees use ordered frames.
fn native_mock_effect_receipt_inventory(slots : Int64, depth : Int) -> Int64? {
  let levels = depth.to_int64()
  guard @shape.collection_construction_extent({
      // Receipt and root validation carriers, evidence vectors/copies and
      // sort scratch; original CIDs/values are borrowed by all these arrays.
      records: 50L + 4L * slots + 9L * levels,
      record_references: 90L + 6L * slots + 16L * levels,
      record_words: 55L + 4L * slots + 12L * levels,
      reference_arrays: 19L,
      reference_items: 5L * slots + 3L * levels,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(input) &&
    @encode.measuring_writer_construction_extent(27, depth) is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, depth) is Some(comparison) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: input.record_headers +
    writer.record_headers +
    comparison.record_headers,
    reference_slots: input.reference_slots +
    writer.reference_slots +
    comparison.reference_slots,
    scalar_words: input.scalar_words +
    writer.scalar_words +
    comparison.scalar_words,
    owned_utf16_units: comparison.owned_utf16_units,
    owned_wire_bytes: comparison.owned_wire_bytes,
  })
}

///|
fn native_mock_effect_receipt_body_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
  max_bytes : Int,
  max_nodes : Int,
  inventory : Int64,
) -> @execution.ExecutionCapacity? {
  // The existing run_receipt seal adds one fixed self-CID field. Unlike the
  // Manifest issuer, it reads the complete emitted body with the normalizing
  // parser. Retain that actual full returned tree and wire.
  let sealed_bytes = Int64::min(max_bytes.to_int64(), bytes.to_int64() + 100L).to_int()
  let sealed_nodes = Int64::min(max_nodes.to_int64(), nodes.to_int64() + 1L).to_int()
  guard native_mock_effect_canonical_body_capacity(
      sealed_bytes, sealed_nodes, depth,
    )
    is Some(body) &&
    @encode.text_writer_live_key_inventory(sealed_bytes, 27, depth)
    is Some(writer) &&
    @publication.protocol_wire_validation_construction_extent(
      sealed_nodes.to_int64(),
    )
    is Some(validation) &&
    @encode.hash_writer_live_key_inventory(0, depth) is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers +
      validation.record_headers +
      hash.record_headers,
      reference_slots: writer.reference_slots +
      validation.reference_slots +
      hash.reference_slots,
      scalar_words: writer.scalar_words +
      validation.scalar_words +
      hash.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(canonical) &&
    @execution.checked_preparation_add_product(inventory, canonical, 1L)
    is Some(workspace) &&
    @execution.execution_capacity(0L, workspace) is Some(extra) else {
    return None
  }
  @execution.add_execution_capacity(body, extra)
}

///|
// Caller DATA and the existing Core verifier children. The proposals retain
// the original captured pins; this adds no Source, Model, approval or cleanup
// authority and must retire before those original pins and capture operations.
priv struct LocalNativeMockEffectPreview {
  _retained_observation : @publication.RunEvidenceValue
  _retained_invocation : @publication.PublicationContract
  _retained_models : Array[@publication.RunEvidenceValue]
  _retained_source_observations : Array[@publication.RunEvidenceValue]
  _retained_authoring : @publication.RunEvidenceValue
  _retained_sources : Array[@publication.PublicationContract]
  _retained_identities : Array[@run_host.ClientEffectLocalIdentity]
  inputs : @strategy.CapturedEffectPreviewInputs
  _retained_wire : String
  _retained_keys : Array[Array[@effect.EffectDispatchKey]]
  verifiers : Array[@strategy.CapturedEffectPlanVerifier]
  proofs : Array[@strategy.CapturedEffectPlanProof]
  _retained_captured_sources : Array[@publication.CapturedEffectSourceArtifact]
  _retained_local_sources : Array[
    @publication.CapturedLocalEffectSourceEvidence,
  ]
  mut _retained_dependency_inventory : @publication.CapturedEffectDependencyInventory?
  mut _retained_dependency_geometry : @encode.EncodingConstructionGeometry?
}

///|
fn native_mock_preview_json(wire : String) -> Json raise ClientStop {
  @json.parse(wire) catch {
    _ => stop("LocalOriginalEffectPreviewEncodingUnavailable")
  }
}

///|
// Closed acceptance-only labels for the original generic Preview refusal.
// No configuration, request evidence or physical ownership is observed here.
priv enum NativeEffectPreviewFailureStage {
  Selection
  DirectOwner
  DirectLimits
  ModelWork
  ModelObservation
  CaptureTuple
  Construction
  Growth
  InvocationScope
  CapturedInput
  CheckedHeader
  MemberDescriptor
  TargetMapping
  TerminalBody
}

///|
fn[T] stop_native_effect_preview(
  stage : NativeEffectPreviewFailureStage,
  managed_reason? : Int = 0,
) -> T raise ClientStop {
  let stage = match stage {
    Selection => 1
    DirectOwner => 2
    DirectLimits => 3
    ModelWork => 4
    ModelObservation => 5
    CaptureTuple => 6
    Construction => 7
    Growth => 8
    InvocationScope => 9
    CapturedInput => 10
    CheckedHeader => 11
    MemberDescriptor => 12
    TargetMapping => 13
    TerminalBody => 14
  }
  native_model_preview_failure(stage, managed_reason)
  stop("LocalOriginalEffectPreviewUnavailable")
}

///|
fn native_effect_preview_managed_reason(
  issue : LocalNativeMockEffectProposalIssue,
) -> Int {
  match issue {
    Managed(InsufficientCapacity) => 1
    Managed(Ledger(RetentionLimit)) => 2
    Managed(Ledger(ExecutionLimit)) => 3
    Managed(Ledger(ResourceParked)) => 4
    Managed(Ledger(ClosedReservation)) => 5
    Managed(Ledger(_)) => 6
    Managed(AlreadyBound) => 7
    Managed(Retired) => 8
    Managed(ForeignOriginal) => 9
    Managed(Unsupported) => 10
    Managed(_) => 11
    _ => 12
  }
}

///|
// Use the same original request, target snapshots and completed Model evidence
// at the actual Preview boundary. Core authors every semantic/dispatch identity
// and verifies the plan against the already retained original Result snapshot.
// This operation does not persist, commit waiting, approve or send a mutation.
fn LocalCommandBusinessPreparation::prepare_mock_effect_preview(
  self : Self,
  installation : LocalRunInstallation,
  policy_binding : @local_host.NativeLocalRunPolicyBinding,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    (
      business.model_work.length() == 1 ||
      (
        business.model_work.is_empty() &&
        state.first._retained_models.is_empty() &&
        state.source_start is Some(_)
      )
    ) &&
    state.effect_capture is Some(_) &&
    state.proposals is Some(proposals) &&
    proposals.materials is Some(materials) &&
    state.preview is None &&
    self.original.project is Some(project) &&
    project.mock_declarations is Some(mock) &&
    mock.write_installations is Some(installations) else {
    stop_native_effect_preview(Selection)
  }
  // Observe selected configuration under the actual Read before suspending
  // it for Request payload work. Only these immutable bodies cross the phase.
  let retention = local_host_result(
    policy_binding.retention_dependency_bodies_in_original_read(
      self.capture,
      state.first.request,
    ),
  )
  self.original.with_business_request(self.capture, () => {
    if state.first._retained_models.is_empty() {
      guard business.model_work.is_empty() &&
        state.source_start is Some(_) &&
        business.request_run is Some(run) &&
        state.direct_sources is Some(direct) &&
        direct.publication_originals() is Some((observation, invocation)) else {
        stop_native_effect_preview(DirectOwner)
      }
      let max_bytes = native_mock_effect_record_bytes(installation)
      let limits = @local_values.installed_effect_managed_publication_limits(
        run,
        state._retained_prepared,
        state.first.request,
        state._retained_plan,
        max_bytes,
      ).unwrap_or_else(() => stop_native_effect_preview(DirectLimits))
      let report = issue => {
        self.original.retain_primary(CommandBusinessEffectProposals(issue))
      }
      state.build_mock_effect_preview(
        proposals,
        installations,
        installation.store_authority_cid,
        max_bytes,
        limits.max_result_fields,
        () => (observation, invocation, [], direct.observations, None),
        report,
      )
      state.prepare_direct_mock_effect_dependencies(
        run,
        retention,
        installation.store_authority_cid,
        max_bytes,
        report,
        values_installation=installation.source_free,
      )
      return
    }
    if business.model_work.length() != 1 {
      stop_native_effect_preview(ModelWork)
    }
    let limits = state.first._retained_models[0]._retained_limits
    state.build_mock_effect_preview(
      proposals,
      installations,
      installation.store_authority_cid,
      native_mock_effect_record_bytes(installation),
      limits.identity.wire.max_columns,
      () => {
        guard business.model_work[0].completed_observation_originals(
            limits.output_rows,
          )
          is Some((observation, invocation, models, sources)) else {
          stop_native_effect_preview(ModelObservation)
        }
        let task = @run_host.client_infer_occurrence_model_task_cid(
          state.model_graph().occurrence,
        ).unwrap_or_else(() => {
          stop("LocalOriginalEffectPreviewModelProvenanceUnavailable")
        })
        (observation, invocation, models, sources, Some(task))
      },
      issue => {
        self.original.retain_primary(CommandBusinessEffectProposals(issue))
      },
    )
    self.prepare_mock_effect_dependency_inventory(
      state,
      proposals,
      materials,
      state.preview.unwrap(),
      retention,
      installation,
    )
  })
}

///|
// The measured proposal and its imports are still retained on this capture.
// The warm frame needs the Preview constructor beside those originals.
// The original recovery recipe is used by another phase and remains intact.
fn native_mock_measured_effect_preview_recipe(
  held : Array[@execution.ExecutionCapacity],
  warm : Array[@execution.ExecutionCapacity],
  preview : @execution.ExecutionCapacity,
) -> Array[@execution.ExecutionCapacity]? {
  guard held.length() == 6 &&
    warm.length() == 6 &&
    @execution.execution_capacity_retained_bytes(held[1]) == 0L &&
    @execution.execution_capacity_execution_bytes(held[1]) == 0L else {
    return None
  }
  let previous = @execution.execution_capacity_retained_bytes(held[0])
  let warm_fixed = warm[0]
  let workspace = @execution.execution_capacity_execution_bytes(warm_fixed) -
    @execution.execution_capacity_retained_bytes(warm_fixed)
  let preview_r = @execution.execution_capacity_retained_bytes(preview)
  guard @execution.execution_capacity_execution_bytes(held[0]) == previous &&
    @execution.execution_capacity_execution_bytes(preview) - preview_r <=
    workspace &&
    @execution.checked_preparation_add_product(previous, preview_r, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(retained, workspace, 1L)
    is Some(execution) &&
    @execution.execution_capacity(retained, execution) is Some(fixed) else {
    return None
  }
  let selected = held.copy()
  selected[0] = fixed
  Some(selected)
}

///|
// Build the Preview from the original captured Result and closed target reads.
// Original Source or Model evidence is supplied by the selected caller inside
// this Request frame, after the existing construction workspace is available.
fn LocalNativeMockEffectPlan::build_mock_effect_preview(
  state : Self,
  proposals : LocalNativeMockEffectProposals,
  installations : Array[LocalProjectMockWriteInstallation],
  store_authority_cid : String,
  max_bytes : Int,
  max_fields : Int,
  observe : () -> (
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
    Array[@publication.RunEvidenceValue],
    Array[@publication.RunEvidenceValue],
    String?,
  ) raise ClientStop,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> Unit raise ClientStop {
  guard state.effect_capture is Some(captured) &&
    state.proposals is Some(original) &&
    physical_equal(original, proposals) &&
    proposals.materials is Some(materials) &&
    state.preview is None else {
    stop_native_effect_preview(CaptureTuple)
  }
  // Target/request construction has returned its own scratch and each read
  // child acknowledged close. Re-enter this SAME capture's original warm
  // workspace before any Preview/receipt constructors, never a new slot.
  let construction = proposals.construction.unwrap_or_else(() => {
    stop_native_effect_preview(Construction)
  })
  let policy = @run_host.client_standard_effect_computation_limits()
  let max_nodes = policy.effects.max_admission_nodes
  let max_depth = policy.effects.max_admission_depth
  let recipe = if proposals.uses_measured_model_proposal() {
    let selected = @local_values.installed_physical_write_preview_capacity(
      max_bytes, max_nodes, max_depth,
    ).bind(preview => {
      native_mock_measured_effect_preview_recipe(
        construction.recipe,
        state._retained_import_recipes[1],
        preview,
      )
    })
    guard construction.workspace == 0L && selected is Some(recipe) else {
      let issue = LocalNativeMockEffectProposalIssue::Managed(
        InsufficientCapacity,
      )
      report(issue)
      stop_native_effect_preview(
        Growth,
        managed_reason=native_effect_preview_managed_reason(issue),
      )
    }
    recipe
  } else {
    construction.recipe
  }
  match
    construction.resize_result(
      recipe,
      construction.retained,
      construction.workspace,
    ) {
    Ok(_) => ()
    Err(issue) => {
      report(issue)
      stop_native_effect_preview(
        Growth,
        managed_reason=native_effect_preview_managed_reason(issue),
      )
    }
  }
  construction.recipe = recipe
  let codec = policy.program.checking.compilation.artifacts
  let max_work = policy.effects.max_work
  let encode_with_usage = fn(
    value : Json,
  ) -> (String, Int, Int, Int) raise ClientStop {
    let original = @canonical.from_json(
      value,
      max_nodes,
      max_depth,
      max_bytes,
      data_keys=true,
    ) catch {
      _ => stop("LocalOriginalEffectPreviewEncodingUnavailable")
    }
    @canonical.stringify_value_with_usage(
      original, max_bytes, max_nodes, max_depth,
    ) catch {
      _ => stop("LocalOriginalEffectPreviewEncodingUnavailable")
    }
  }
  let encode = fn(value) raise ClientStop { encode_with_usage(value).0 }
  let digest = fn(value : Json) -> String raise ClientStop {
    "sha256:" +
    @sha.text_hex(encode(value)).unwrap_or_else(() => {
      stop("LocalOriginalEffectPreviewEncodingUnavailable")
    })
  }
  let (key_bytes, key_nodes, key_depth) = @effect.effect_dispatch_key_codec_limits()
  let (observation, invocation, models, source_observations, task_cid) = observe()
  guard proposals.publication_context
    is Some((original_observation, original_invocation, _)) &&
    physical_equal(original_observation, observation) &&
    physical_equal(original_invocation, invocation) &&
    @run_host.prepared_client_effect_request_scope(
      materials.prepared,
      state.first.request,
    )
    is Ok(scope) else {
    stop_native_effect_preview(InvocationScope)
  }
  let definition_cid = @run_host.prepared_client_effect_computation_definition_cid(
    materials.prepared,
  )
  let authoring_wire = encode({
    "version": "actql-authoring-context/0.1",
    "program_definition_cid": Json::string(definition_cid),
    "annotations": [],
  })
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context", authoring_wire, max_bytes, max_nodes, max_depth,
  ).unwrap_or_else(() => stop("LocalOriginalEffectPreviewEncodingUnavailable"))
  let authoring_cid = @publication.run_evidence_value_identity(authoring)
  let run_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  let checked_preview = @checked.effect_program_static_headers(
    @run_host.prepared_client_effect_computation_candidate(materials.prepared),
  )
  let includes_create = @syntax.effect_header_count(checked_preview) == 1 &&
    @syntax.effect_header_at(checked_preview, 0) is Some(header) &&
    @syntax.effect_header_kind(header) == "create"
  let measured_preview = proposals.measured_model_capture || includes_create
  let (
    draft,
    draft_bytes,
    draft_nodes,
    draft_depth,
    sources,
    identities,
    row_count,
  ) = {
    let mut draft_row_bytes = 0L
    let model_cids : Array[String] = []
    let response_cids : Array[String] = []
    for original in models {
      guard native_mock_preview_json(
          @publication.run_evidence_value_json(original),
        )
        is Object(fields) &&
        task_cid is Some(_) &&
        json_text(fields, "model_task_contract_cid") == task_cid &&
        json_text(fields, "structured_response_artifact_cid") is Some(response) else {
        stop("LocalOriginalEffectPreviewModelProvenanceUnavailable")
      }
      model_cids.push(@publication.run_evidence_value_identity(original))
      if !response_cids.contains(response) {
        response_cids.push(response)
      }
    }
    model_cids.sort()
    response_cids.sort()
    let barriers = if state.lookup is Some(lookup) {
      let completed = @run_host.client_keyed_lookup_native_completion(lookup).unwrap_or_else(() => {
          stop("LocalOriginalEffectPreviewLookupUnavailable")
        },
      )
      [
        Json::string(
          @publication.publication_contract_identity(completed.evidence),
        ),
      ]
    } else {
      []
    }
    let effects : Array[Json] = []
    let sources : Array[@publication.PublicationContract] = []
    let identities : Array[@run_host.ClientEffectLocalIdentity] = []
    let pending = "sha256:" + "0".repeat(64)
    let mut target_index = 0
    let mut row_count = 0
    for index, entry in proposals.members {
      let input = @strategy.captured_effect_input_at(proposals.inputs, index).unwrap_or_else(() => {
          stop_native_effect_preview(CapturedInput)
        },
      )
      let stage = @strategy.captured_effect_input_stage(input)
      let headers = @checked.effect_program_static_headers(
        @run_host.prepared_client_effect_computation_candidate(
          materials.prepared,
        ),
      )
      let header = @syntax.effect_header_at(headers, index).unwrap_or_else(() => {
        stop_native_effect_preview(CheckedHeader)
      })
      let descriptor = @run_host.client_effect_member_descriptor(
        materials.prepared,
        stage,
        @syntax.effect_header_id(header),
        max_work,
      ).unwrap_or_else(() => stop_native_effect_preview(MemberDescriptor))
      let deleting = descriptor.2 == "delete"
      let creating = descriptor.2 == "create"
      let upserting = descriptor.2 == "upsert"
      guard descriptor.0 == index &&
        descriptor.6 is Some(result_name) &&
        installations
        .iter()
        .find_first(selected => {
          selected.matches_file_operation(descriptor.2) &&
          selected.target == descriptor.3 &&
          selected.write.mapping.mapping_ref == descriptor.4 &&
          selected.write.mapping.mapping_cid == descriptor.5
        })
        is Some(selected) &&
        entry._retained_artifact is Some(artifact) &&
        native_mock_preview_json(selected.owner.1) is Object(owner) &&
        native_mock_preview_json(selected.write.mapping.body) is Object(mapping) &&
        mapping.get("required_permissions") is Some(permissions) else {
        stop_native_effect_preview(TargetMapping)
      }
      let source = @run_host.issue_client_effect_local_source_artifact(
          materials,
          proposals.inputs,
          index,
          artifact,
          invocation,
          @run_host.client_effect_local_result_retention(artifact),
          selected.binding,
          store_authority_cid,
          max_bytes,
          max_nodes,
          max_depth,
        )
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::PreviewSource(issue)
        })
        .native_effect_proposal_with_cause(report)
      sources.push(source)
      let identity = @run_host.issue_source_free_client_effect_local_identity(
          materials.prepared,
          proposals.inputs,
          index,
          artifact,
          max_work,
          max_bytes,
          max_nodes,
          max_depth,
        )
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::PreviewIdentity(issue)
        })
        .native_effect_proposal_with_cause(report)
      identities.push(identity)
      if measured_preview {
        // Both growing per-member vectors remain live through their digest
        // and member construction. Keep their backing with all earlier rows.
        guard @execution.preparation_array_representation(
            2L,
            2L * entry.rows.length().to_int64(),
            true,
          )
          .bind(@execution.preparation_representation_cost)
          .bind(bytes => {
            @execution.checked_preparation_add_product(
              draft_row_bytes, bytes, 1L,
            )
          })
          is Some(retained) else {
          report(Managed(InsufficientCapacity))
          stop("LocalOriginalEffectPreviewTargetUnavailable")
        }
        draft_row_bytes = retained
        construction
        .prepare_body_result(@execution.execution_capacity(0L, draft_row_bytes))
        .native_effect_proposal_with_cause(report)
      }
      let (changes, requests) = if creating {
        let (changes, requests, retained) = construction.prepare_mock_file_create_preview(
          entry.rows,
          (
            run_cid,
            selected.binding,
            @run_host.client_effect_local_identity_cid(identity),
            descriptor.5,
          ),
          pending,
          { max_wire_bytes: max_bytes, max_nodes, max_depth, },
          draft_row_bytes,
          report,
        )
        draft_row_bytes = retained
        (changes, requests)
      } else {
        let changes : Array[Json] = []
        let requests : Array[Json] = []
        for _ in 0..<entry.rows.length() {
          guard state.targets.get(target_index) is Some(target) &&
            target._retained_request is Some((request_wire, request_cid)) else {
            stop("LocalOriginalEffectPreviewTargetUnavailable")
          }
          if measured_preview {
            draft_row_bytes = construction.fund_preview_target_row(
              request_wire, draft_row_bytes, report,
            )
          }
          guard native_mock_preview_json(request_wire) is Object(request) &&
            request.get("target") is Some(target_value) &&
            (!upserting || target_value is Array(_)) &&
            json_text(request, "binding") == Some(selected.binding) &&
            json_text(request, "mapping") == Some(descriptor.5) else {
            stop("LocalOriginalEffectPreviewTargetUnavailable")
          }
          let (before, target_guard, fields) : (Json, Json, Int) = match
            (request.get("before"), json_text(request, "version")) {
            (Some(before), Some(version)) if !version.is_empty() =>
              (
                { "state": "present", "value": before },
                { "state": "version", "version_cid": Json::string(version) },
                5,
              )
            (None, None) if upserting &&
              target_value is Array(_) &&
              request.get("version") is None =>
              ({ "state": "absent" }, { "state": "not_applicable" }, 3)
            _ => stop("LocalOriginalEffectPreviewTargetUnavailable")
          }
          let value = match request.get("value") {
            None if deleting && request.length() == fields => Json::null()
            Some(value) if !deleting &&
              request.length() == fields + 1 &&
              value is Object(_) => value
            _ => stop("LocalOriginalEffectPreviewTargetUnavailable")
          }
          target_index += 1
          requests.push(Json::string(request_cid))
          changes.push({
            "target_row_identity": target_value,
            "target_guard": target_guard,
            "before": before,
            "after": if deleting {
              { "state": "absent" }
            } else {
              { "state": "present", "value": value }
            },
            "intended_changes": if deleting {
              { "state": "not_applicable" }
            } else {
              { "state": "present", "value": value }
            },
            "row_preview_cid": Json::string(pending),
            "row_idempotency_key": Json::string(pending),
          })
        }
        (changes, requests)
      }
      if changes.length() > max_nodes - row_count {
        stop("LocalOriginalEffectPreviewTargetUnavailable")
      }
      row_count += changes.length()
      // Wire projection of the existing installed row-driver contract: the
      // selected implementation is single-serial without provider idempotency.
      // This identity is not an Account decision, claim or send permission.
      let registration = json_text(owner, "connector_registration").unwrap_or_else(() => {
          stop("LocalOriginalEffectPreviewInstallationUnavailable")
        },
      )
      let capability = digest({
        "version": "actql-installed-row-effect-capability/0.1",
        "connector_registration": Json::string(registration),
        "connector_revision": owner["connector_revision"],
        "runtime_bundle_cid": owner["runtime_bundle_cid"],
        "binding_cid": Json::string(selected.binding),
        "connection": owner["connection"],
        "resource": Json::string(selected.write.mapping.resource),
        "mapping_cid": Json::string(descriptor.5),
        "operation": Json::string(descriptor.2),
        "route": "single_serial",
        "idempotency": "unavailable",
        "request_cids": Json::array(requests),
      })
      let scheme = digest({
        "version": "actql-installed-row-effect-identity-scheme/0.1",
        "connector_registration": Json::string(registration),
        "resource": Json::string(selected.write.mapping.resource),
        "mapping_cid": Json::string(descriptor.5),
        "primary_identity": mapping["primary_identity"],
      })
      let body : Json = {
        "effect_id": Json::string(descriptor.1),
        "effect_kind": Json::string(descriptor.2),
        "target": Json::string(descriptor.3),
        "mapping": Json::string(descriptor.4),
        "resolved_mapping_contract_cid": Json::string(descriptor.5),
        "effect_identity_cid": Json::string(
          @run_host.client_effect_local_identity_cid(identity),
        ),
        "source_result": Json::string(result_name),
        "result_artifact_cid": Json::string(
          @run_host.client_effect_local_result_artifact_cid(artifact),
        ),
        "preview_strength": "full_diff",
        "source_binding_cid": Json::string(selected.binding),
        "capability_evidence_cid": Json::string(capability),
        "authority_scope_cid": Json::string(
          @request_scope.logical_request_scope_authority(scope),
        ),
        "required_permissions": permissions,
        "approval": "required",
        "on_item_failure": Json::string(descriptor.7),
        "write_footprint": {
          "kind": "opaque",
          "provider_namespace": "local-mock-file",
          "provider_boundary_cid": Json::string(selected.binding),
          "resource_kind": Json::string(selected.write.mapping.resource),
          "resource_identity_scheme_cid": Json::string(scheme),
          "provider_object_identity_cids": [],
        },
        "count": Json::number(changes.length().to_double()),
        "max_items": Json::number(changes.length().to_double()),
        "changes": Json::array(changes),
        "row_order": [],
        "effect_member_preview_cid": Json::string(pending),
        "executed": false,
      }
      let rules = @stage_results.effect_static_candidate_mapping_rules(
        @checked.effect_program_static_effects(
          @run_host.prepared_client_effect_computation_candidate(
            materials.prepared,
          ),
        ),
      )
      let terminal = @stage_results.effect_plan_terminal_for_member(
        rules, index, max_fields, max_work,
      ).unwrap_or_else(() => stop("LocalOriginalEffectPreviewPlanUnavailable"))
      if terminal is Some(terminal) {
        let cid = @stage_results.effect_plan_pipeline_cid(
          terminal, max_bytes, max_nodes, max_depth,
        ) catch {
          _ => stop("LocalOriginalEffectPreviewPlanUnavailable")
        }
        guard body is Object(fields) else {
          stop_native_effect_preview(TerminalBody)
        }
        fields["effect_plan_logical_cid"] = Json::string(cid)
      }
      effects.push(body)
    }
    if target_index != state.targets.length() {
      stop("LocalOriginalEffectPreviewTargetUnavailable")
    }
    let draft_json : Json = {
      "version": "actql-effect-preview/0.1",
      "sensitivity": "private",
      "retention_class": "authority-evidence",
      "encryption_required": true,
      "program_semantics_cid": Json::string(
        @run_host.prepared_client_effect_computation_semantics_cid(
          materials.prepared,
        ),
      ),
      "program_definition_cid": Json::string(definition_cid),
      "invocation_cid": Json::string(
        @publication.publication_contract_identity(invocation),
      ),
      "run_identity_cid": Json::string(run_cid),
      "compiled_plan_cid": Json::string(
        @publication.publication_contract_identity(
          @run_host.client_effect_compilation_compiled_plan(
            materials.compilation,
          ),
        ),
      ),
      "check_environment_cid": Json::string(
        @run_host.prepared_client_effect_computation_environment_cid(
          materials.prepared,
        ),
      ),
      "authoring_context": native_mock_preview_json(
        @publication.run_evidence_value_json(authoring),
      ),
      "barrier_provenance_cids": Json::array(barriers),
      "model_derived": Json::boolean(task_cid is Some(_)),
      "model_task_contract_cids": Json::array(
        match task_cid {
          Some(task) => [Json::string(task)]
          None => []
        },
      ),
      "model_invocation_evidence_cids": Json::array(
        model_cids.map(cid => Json::string(cid)),
      ),
      "model_response_artifact_cids": Json::array(
        response_cids.map(cid => Json::string(cid)),
      ),
      "effects": Json::array(effects),
      "executed": false,
      "effect_preview_cid": Json::string(pending),
    }
    if measured_preview {
      construction.fund_preview_draft_encoding(
        draft_json, draft_row_bytes, max_bytes, max_nodes, max_depth, report,
      )
    }
    let (draft, draft_bytes, draft_nodes, draft_depth) = encode_with_usage(
      draft_json,
    )
    (
      draft, draft_bytes, draft_nodes, draft_depth, sources, identities, row_count,
    )
  }
  let (semantic, authored, identity) = if measured_preview {
    // Member/row/digest placeholders use the same 71 ASCII units as their
    // issued CIDs. The emitted shape adds only row_order strings to this
    // draft; row_count includes both authored inserts and observed targets.
    construction
    .prepare_body_result(
      @publication.effect_preview_semantic_authoring_construction_inventory(
        draft_bytes, draft_nodes, draft_depth, row_count, max_bytes, max_nodes,
      ).bind(inventory => {
        @execution.preparation_representation_cost({
          // The authored and later completion carriers stay paid here.
          record_headers: inventory.record_headers + 5L,
          reference_slots: inventory.reference_slots + 7L,
          scalar_words: inventory.scalar_words + 9L,
          owned_utf16_units: inventory.owned_utf16_units +
          draft.length().to_int64(),
          owned_wire_bytes: inventory.owned_wire_bytes,
        }).bind(bytes => @execution.execution_capacity(0L, bytes))
      }),
    )
    .native_effect_proposal_with_cause(report)
    let authored = @publication.prepare_authored_effect_preview(
        draft, run_cid, authoring_cid, max_bytes, max_nodes, max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewBody(issue))
      .native_effect_proposal_with_cause(report)
    let identity = @publication.authored_effect_preview_identity(authored)
    let capacity = native_mock_effect_preview_dispatch_capacity(
      identity, key_bytes, key_nodes, key_depth,
    ).native_effect_proposal_with_cause(report)
    construction
    .prepare_body_result(Some(capacity))
    .native_effect_proposal_with_cause(report)
    ("", Some(authored), identity)
  } else {
    let (semantic, identity) = @publication.author_effect_preview_semantic_wire(
        draft, run_cid, authoring_cid, max_bytes, max_nodes, max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewBody(issue))
      .native_effect_proposal_with_cause(report)
    (semantic, None, identity)
  }
  let keys : Array[Array[@effect.EffectDispatchKey]] = []
  let key_cids : Array[Array[String]] = []
  for index in 0..<@publication.effect_preview_member_count(identity) {
    let row_keys = []
    let row_cids = []
    for
      row in 0..<@publication.effect_preview_row_count(identity, index).unwrap() {
      let key = @effect.prepare_effect_preview_row_dispatch_key(
          identity, scope, index, row, key_bytes, key_nodes, key_depth,
        )
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::PreviewDispatch(issue)
        })
        .native_effect_proposal_with_cause(report)
      row_keys.push(key)
      row_cids.push(@effect.effect_dispatch_key_cid(key))
    }
    keys.push(row_keys)
    key_cids.push(row_cids)
  }
  let (completed, completed_identity) = {
    let completed = match authored {
      Some(original) => {
        let prepared = @publication.prepare_effect_preview_dispatch_completion(
            original, key_cids,
          )
          .map_err(issue => {
            LocalNativeMockEffectProposalIssue::PreviewBody(issue)
          })
          .native_effect_proposal_with_cause(report)
        construction
        .prepare_body_result(
          native_mock_effect_preview_admission_capacity(prepared, key_cids),
        )
        .native_effect_proposal_with_cause(report)
        @publication.admit_prepared_effect_preview_dispatch(prepared)
      }
      None =>
        @publication.complete_effect_preview_dispatch_keys_with_identity(
          semantic, key_cids, run_cid, authoring_cid, max_bytes, max_nodes, max_depth,
        )
    }
    let (wire, identity) = completed
      .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewBody(issue))
      .native_effect_proposal_with_cause(report)
    @effect.check_admitted_effect_preview_apply_keys(identity, scope, keys)
    .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewKeys(issue))
    .native_effect_proposal_with_cause(report)
    (wire, identity)
  }
  let preview = @run_host.bind_admitted_captured_client_effect_preview(
      materials,
      captured,
      proposals.inputs,
      invocation,
      @strategy.captured_effect_input_stage(
        @strategy.captured_effect_input_at(proposals.inputs, 0).unwrap(),
      ),
      completed_identity,
      authoring_cid,
      identities,
      max_work,
      { max_work, max_fields, max_bytes, max_nodes, max_depth, },
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewBinding(issue))
    .native_effect_proposal_with_cause(report)
  if measured_preview {
    // Keep the eventual geometry reference on this same Preview record.
    construction
    .prepare_body_result(
      @execution.preparation_representation_cost({
        record_headers: 1L,
        reference_slots: 2L,
        scalar_words: 2L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }).bind(bytes => @execution.execution_capacity(bytes, bytes)),
    )
    .native_effect_proposal_with_cause(report)
  }
  let held : LocalNativeMockEffectPreview = {
    _retained_observation: observation,
    _retained_invocation: invocation,
    _retained_models: models,
    _retained_source_observations: source_observations,
    _retained_authoring: authoring,
    _retained_sources: sources,
    _retained_identities: identities,
    inputs: preview,
    _retained_wire: completed,
    _retained_keys: keys,
    verifiers: [],
    proofs: [],
    _retained_captured_sources: [],
    _retained_local_sources: [],
    _retained_dependency_inventory: None,
    _retained_dependency_geometry: None,
  }
  // Retain before the verifier or the enclosing original-current callback
  // can fail. Its borrowed pins remain owned by the same proposals record.
  state.preview = Some(held)
  for index, entry in proposals.members {
    if @publication.effect_preview_member_kind(completed_identity, index) ==
      Some("create") {
      // Common validates CREATE content and occurrence IDs in Preview.
      // The verifier below belongs to version-guarded Effect terminals.
      continue
    }
    let verifier = @strategy.prepare_captured_effect_plan_verifier(
        held.inputs,
        index,
        max_fields,
        max_work,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewPlan(issue))
      .native_effect_proposal_with_cause(report)
    held.verifiers.push(verifier)
    guard entry._retained_artifact is Some(artifact) &&
      entry._retained_dependency is Some(capture) &&
      @run_host.client_effect_dependency_capture_relation_rows(
        capture,
        artifact,
        max_bytes,
        codec.nodes,
        codec.depth,
      )
      is Some(rows) else {
      stop("LocalOriginalEffectPreviewSnapshotUnavailable")
    }
    for row_index in 0..<@canonical.array_count(rows) {
      let row = @canonical.array_at(rows, row_index).unwrap()
      @strategy.check_captured_effect_plan_row(
        verifier, row, row_index, max_fields, max_work, max_bytes, max_nodes, max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewPlan(issue))
      .native_effect_proposal_with_cause(report)
      |> ignore
    }
    held.proofs.push(
      @strategy.finish_captured_effect_plan_verifier(verifier)
      .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewPlan(issue))
      .native_effect_proposal_with_cause(report),
    )
  }
}

///|
// Common assigns an occurrence to each original proposed value, including
// repeated values. Only the physical request uses the derived storage key.
fn LocalNativeMockEffectImportConstruction::prepare_mock_file_create_preview(
  self : Self,
  rows : Array[(String, String)],
  originals : (String, String, String, String),
  pending : String,
  limits : @checkpoint.WireLimits,
  prior : Int64,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> (Array[Json], Array[Json], Int64) raise ClientStop {
  let count = rows.length()
  if count == 0 || count > limits.max_nodes {
    stop("LocalOriginalEffectPreviewTargetUnavailable")
  }
  let mut remaining = limits.max_wire_bytes
  let mut largest = 128
  for (selector, wire) in rows {
    guard selector == "null" &&
      @scalar.admit_utf8_length(wire, remaining) is Ok(bytes) else {
      stop("LocalOriginalEffectPreviewTargetUnavailable")
    }
    remaining -= bytes
    largest = Int::max(largest, bytes)
  }
  let nodes = Int::min(limits.max_nodes, largest + 2)
  let depth = Int::min(limits.max_depth, nodes)
  guard native_mock_effect_dependency_body_capacity(largest, nodes, depth)
    is Some(codec) &&
    @encode.hash_writer_construction_inventory(nodes, depth) is Some(hash) &&
    @execution.preparation_representation_cost({
      // Source wires, sortable digest/index pairs, occurrence wire pairs,
      // and the returned draft and request vectors share a live prefix.
      record_headers: hash.record_headers + 24L + 12L * count.to_int64(),
      reference_slots: hash.reference_slots + 64L + 30L * count.to_int64(),
      scalar_words: hash.scalar_words + 16L + 8L * count.to_int64(),
      owned_utf16_units: hash.owned_utf16_units + 320L * count.to_int64(),
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(control) &&
    @execution.checked_preparation_add_product(prior, control, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      retained,
      @execution.execution_capacity_execution_bytes(codec),
      1L,
    )
    is Some(peak) else {
    report(Managed(InsufficientCapacity))
    stop("LocalOriginalEffectPreviewTargetUnavailable")
  }
  self
  .prepare_body_result(@execution.execution_capacity(0L, peak))
  .native_effect_proposal_with_cause(report)
  let inventory = @publication.derive_effect_create_row_inventory(
      rows.map(row => row.1),
      count,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewBody(issue))
    .native_effect_proposal_with_cause(report)
  let changes : Array[Json] = []
  let requests : Array[Json] = []
  let mut retained = retained
  for (index, correlation_wire) in inventory {
    let wire = rows[index].1
    retained = self.fund_preview_target_row(wire, retained, report)
    let (run, binding, identity, mapping) = originals
    let request = native_mock_effect_request_json_capacity(
      "", wire, "", binding, mapping, "",
    )
    self
    .prepare_body_result(
      request.bind(capacity => {
        @execution.checked_preparation_add_product(
          retained,
          @execution.execution_capacity_execution_bytes(capacity),
          1L,
        ).bind(peak => @execution.execution_capacity(0L, peak))
      }),
    )
    .native_effect_proposal_with_cause(report)
    let (change, request_cid) = @local_host.native_local_effect_file_create_preview_row(
      native_mock_preview_json(wire),
      native_mock_preview_json(correlation_wire),
      (run, binding, identity, mapping),
      pending,
      limits,
    ).unwrap_or_else(() => stop("LocalOriginalEffectPreviewTargetUnavailable"))
    changes.push(change)
    requests.push(Json::string(request_cid))
  }
  (changes, requests, retained)
}

///|
// Native File Effect keys retain their admitted correlation Strings and one
// newly owned CID each. Both vectors coexist with one bounded key codec;
// the CID-only vector is a temporary input to Preview completion.
fn native_mock_effect_preview_dispatch_capacity(
  preview : @publication.EffectPreviewIdentity,
  max_key_bytes : Int,
  max_key_nodes : Int,
  max_key_depth : Int,
) -> Result[@execution.ExecutionCapacity, LocalNativeMockEffectProposalIssue] {
  let members = @publication.effect_preview_member_count(preview)
  let mut rows = 0L
  let mut text = 0L
  let mut largest = 1
  for index in 0..<members {
    guard @publication.effect_preview_member_kind(preview, index)
      is Some("create" | "update" | "delete" | "upsert") &&
      @publication.effect_preview_row_count(preview, index) is Some(count) else {
      return Err(PreviewDispatch(InvalidRowKey))
    }
    rows += count.to_int64()
    for row in 0..<count {
      guard @publication.effect_preview_row_correlation_wire(
          preview, index, row,
        )
        is Some(correlation) &&
        @scalar.admit_utf8_length(correlation, max_key_bytes) is Ok(bytes) &&
        bytes > 0 else {
        return Err(PreviewDispatch(InvalidRowKey))
      }
      largest = Int::max(largest, bytes)
      text += correlation.length().to_int64()
    }
  }
  let nodes = Int::min(largest, max_key_nodes)
  let depth = Int::min(nodes, max_key_depth)
  let levels = depth.to_int64()
  let arrays = members.to_int64() + 1L
  let slots = members.to_int64() + rows
  // The dispatch wrapper opens one unordered object of four fields.
  // Its canonical correlation uses ordered objects and a growing parent
  // stack, with one cursor and one parent variant per open container.
  let stack = @shape.collection_construction_extent({
    // Keep both completion carriers' control allowance beside the codec.
    records: 9L + 2L * levels,
    record_references: 15L + 2L * levels,
    record_words: 17L + 2L * levels,
    reference_arrays: 1L,
    reference_items: levels,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
  guard @execution.preparation_array_representation(arrays, slots, true)
    is Some(vectors) &&
    @execution.preparation_representation_cost({
      ..vectors,
      record_headers: vectors.record_headers + 3L * rows,
      reference_slots: vectors.reference_slots + 4L * rows,
      owned_utf16_units: text + 71L * rows,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost(vectors)
    is Some(temporary_vectors) &&
    @local_values.installed_effect_contract_response_construction_capacity(
      largest, nodes, depth,
    )
    is Some(parser) &&
    @encode.hash_writer_live_key_inventory(4, depth + 1) is Some(hash) &&
    stack is Some(stack) &&
    @execution.preparation_representation_cost({
      record_headers: hash.record_headers + stack.record_headers,
      reference_slots: hash.reference_slots + stack.reference_slots,
      scalar_words: hash.scalar_words + stack.scalar_words,
      owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(hash_workspace) &&
    @execution.checked_preparation_add_product(retained, temporary_vectors, 1L)
    .bind(bytes => {
      @execution.checked_preparation_add_product(
        bytes,
        @execution.execution_capacity_execution_bytes(parser),
        1L,
      )
    })
    .bind(bytes => {
      @execution.checked_preparation_add_product(bytes, hash_workspace, 1L)
    })
    .bind(bytes => @execution.execution_capacity(retained, bytes))
    is Some(capacity) else {
    return Err(Managed(InsufficientCapacity))
  }
  Ok(capacity)
}

///|
// The emitter and its parsed semantic tree have returned. The completed wire
// and the caller's CID-only vectors can still coexist with the full validator.
// The original warm basis continues to own the authored and returned Preview
// representations; this quote independently covers the validator's peak.
fn native_mock_effect_preview_admission_capacity(
  prepared : @publication.PreparedEffectPreviewDispatch,
  keys : Array[Array[String]],
) -> @execution.ExecutionCapacity? {
  let (bytes, nodes, depth) = @publication.prepared_effect_preview_dispatch_usage(
    prepared,
  )
  let members = keys.length().to_int64()
  let mut slots = members
  for row_keys in keys {
    slots += row_keys.length().to_int64()
  }
  guard @publication.effect_preview_identity_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(admission) &&
    @execution.preparation_array_representation(members + 1L, slots, true)
    is Some(vectors) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: admission.record_headers + vectors.record_headers + 6L,
    reference_slots: admission.reference_slots + vectors.reference_slots + 7L,
    scalar_words: admission.scalar_words + vectors.scalar_words + 9L,
    owned_utf16_units: admission.owned_utf16_units + bytes.to_int64(),
    owned_wire_bytes: admission.owned_wire_bytes,
  }).bind(bytes => @execution.execution_capacity(0L, bytes))
}

///|
// Keep the actual Native @json.parse route. The closed producer's original
// request limits also bound this size-only scan, which returns no grammar
// tree or authority. Both phases use the same capture reservation.
fn LocalNativeMockEffectImportConstruction::fund_preview_target_row(
  self : Self,
  wire : String,
  prior : Int64,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> Int64 raise ClientStop {
  let preflight = @source.json_source_preflight_control_extent()
  self
  .prepare_body_result(
    @execution.preparation_representation_cost({
      record_headers: preflight.record_headers,
      reference_slots: preflight.reference_slots,
      scalar_words: preflight.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    .bind(bytes => @execution.checked_preparation_add_product(prior, bytes, 1L))
    .bind(bytes => @execution.execution_capacity(0L, bytes)),
  )
  .native_effect_proposal_with_cause(report)
  let geometry = native_mock_effect_preview_target_geometry(wire)
  let capacity = native_mock_effect_preview_target_row_capacity(geometry)
  let result = match capacity {
    Some((retained, workspace)) =>
      @execution.checked_preparation_add_product(prior, retained, 1L).bind(held => {
        @execution.checked_preparation_add_product(held, workspace, 1L).map(peak => {
          (held, peak)
        })
      })
    None => None
  }
  self
  .prepare_body_result(
    result.bind(value => @execution.execution_capacity(0L, value.1)),
  )
  .native_effect_proposal_with_cause(report)
  result.unwrap().0
}

///|
fn native_mock_effect_preview_target_geometry(
  wire : String,
) -> @source.JsonSourceGeometry raise ClientStop {
  let cursor = @source.start_json_source_preflight(
    wire,
    {
      max_input_bytes: local_project_mock_relation_wire_bytes,
      max_nodes: local_project_mock_relation_wire_nodes,
      max_depth: local_project_mock_relation_wire_depth,
    },
    data_keys=true,
  ).unwrap_or_else(() => stop("LocalOriginalEffectPreviewEncodingUnavailable"))
  defer @source.cancel_json_source_preflight(cursor)
  while true {
    match @source.advance_json_source_preflight(cursor, 4096) {
      Ok(@source.JsonSourceReady(value, ..)) => break value
      Ok(@source.JsonSourceContinue(..)) => ()
      _ => stop("LocalOriginalEffectPreviewEncodingUnavailable")
    }
  } nobreak {
    stop("LocalOriginalEffectPreviewEncodingUnavailable")
  }
}

///|
// Native Json retains Map and Array backing. A row adds five objects and
// fifteen fields (row, guard, three presence alternatives) and one request
// CID entry. The parsed request's whole tree bounds the retained subtrees.
// One lexical token, including the pinned 800-byte decimal fallback, is
// temporary. Its scratch coexists with every preceding row prefix.
fn native_mock_effect_preview_target_row_capacity(
  geometry : @source.JsonSourceGeometry,
) -> (Int64, Int64)? {
  let nodes = geometry.node_upper.to_int64()
  let fields = geometry.fields.to_int64()
  let depth = geometry.depth_upper.to_int64()
  let text = geometry.input_utf16_units.to_int64()
  guard @shape.collection_construction_extent({
      records: nodes + geometry.quoted_tokens.to_int64() + 20L,
      record_references: 2L * nodes + 24L,
      record_words: 3L * nodes + 20L,
      reference_arrays: geometry.arrays.to_int64(),
      reference_items: Int64::max(0L, nodes - fields - 1L),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: geometry.objects.to_int64() + 5L,
      map_entries: fields + 15L,
    })
    is Some(tree) &&
    @execution.preparation_representation_cost({
      record_headers: tree.record_headers,
      reference_slots: tree.reference_slots,
      scalar_words: tree.scalar_words,
      owned_utf16_units: text,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      // One Native parser context, lexer result and views, string builder
      // controls, active property/array tokens and failed token controls.
      record_headers: 16L + 2L * depth,
      reference_slots: 22L + 3L * depth,
      scalar_words: 32L + 4L * depth,
      owned_utf16_units: 16L + 4L * text,
      owned_wire_bytes: 800L,
    })
    is Some(workspace) else {
    return None
  }
  Some((retained, workspace))
}

///|
// Counts the input seen by the existing from_json converter. Repeated edges
// are visited again: the same value used for "after" and "intended_changes"
// is converted twice. No output tree or detached field vector is allocated.
priv struct NativePreviewDraftGeometry {
  mut nodes : Int
  mut fields : Int
  mut objects : Int
  mut arrays : Int
  mut depth : Int
  mut text : Int64
}

///|
fn NativePreviewDraftGeometry::observe(
  self : Self,
  value : Json,
  level : Int,
  max_nodes : Int,
  max_depth : Int,
  max_bytes : Int,
) -> Bool {
  if self.nodes >= max_nodes {
    return false
  }
  self.nodes += 1
  match value {
    Object(values) => {
      if level >= max_depth || values.length() > max_nodes - self.nodes {
        return false
      }
      self.objects += 1
      self.fields += values.length()
      self.depth = Int::max(self.depth, level + 1)
      for key, child in values {
        self.text += key.length().to_int64()
        if !self.observe(child, level + 1, max_nodes, max_depth, max_bytes) {
          return false
        }
      }
    }
    Array(values) => {
      if level >= max_depth || values.length() > max_nodes - self.nodes {
        return false
      }
      self.arrays += 1
      self.depth = Int::max(self.depth, level + 1)
      for child in values {
        if !self.observe(child, level + 1, max_nodes, max_depth, max_bytes) {
          return false
        }
      }
    }
    String(text) => self.text += text.length().to_int64()
    _ => ()
  }
  self.text <= max_bytes.to_int64()
}

///|
fn LocalNativeMockEffectImportConstruction::fund_preview_draft_encoding(
  self : Self,
  draft : Json,
  row_backing : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> Unit raise ClientStop {
  let depth = max_depth.to_int64()
  let scan = @execution.preparation_representation_cost({
      // One scalar geometry and the active Map/Array iterators of a bounded
      // traversal. The source Json and original borrowed Strings stay live.
      record_headers: 2L + 8L * depth,
      reference_slots: 15L * depth,
      scalar_words: 12L + 12L * depth,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    .bind(bytes => {
      @execution.checked_preparation_add_product(row_backing, bytes, 1L)
    })
    .bind(bytes => @execution.execution_capacity(0L, bytes))
  self.prepare_body_result(scan).native_effect_proposal_with_cause(report)
  let geometry = {
    nodes: 0,
    fields: 0,
    objects: 0,
    arrays: 0,
    depth: 0,
    text: 0L,
  }
  if !geometry.observe(draft, 0, max_nodes, max_depth, max_bytes) {
    stop("LocalOriginalEffectPreviewEncodingUnavailable")
  }
  self
  .prepare_body_result(
    native_mock_effect_preview_draft_capacity(geometry, row_backing, max_bytes),
  )
  .native_effect_proposal_with_cause(report)
}

///|
fn native_mock_effect_preview_draft_capacity(
  geometry : NativePreviewDraftGeometry,
  row_backing : Int64,
  max_bytes : Int,
) -> @execution.ExecutionCapacity? {
  let nodes = geometry.nodes.to_int64()
  let fields = geometry.fields.to_int64()
  let depth = geometry.depth.to_int64()
  guard @canonical.source_conversion_construction_extent(
      geometry.nodes,
      geometry.fields,
      geometry.objects,
      geometry.arrays,
      geometry.depth,
      geometry.text.to_int(),
    )
    is Some(conversion) &&
    @shape.collection_construction_extent({
      // Retain the current Native Json tree, not unused parse tokens from
      // earlier calls. Counting shared subtrees twice is conservative.
      records: 2L * nodes + fields,
      record_references: 2L * nodes + fields,
      record_words: 3L * nodes + fields,
      reference_arrays: geometry.arrays.to_int64(),
      reference_items: Int64::max(0L, nodes - fields - 1L),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: geometry.objects.to_int64(),
      map_entries: fields,
    })
    is Some(input) &&
    @execution.preparation_representation_cost({
      record_headers: input.record_headers,
      reference_slots: input.reference_slots,
      scalar_words: input.scalar_words,
      owned_utf16_units: geometry.text,
      owned_wire_bytes: 0L,
    })
    is Some(native) else {
    return None
  }
  let output_bytes = Int64::min(
    max_bytes.to_int64(),
    6L * conversion.retained_utf16_units + 32L * nodes + 4L * fields,
  ).to_int()
  // Ordered canonical objects have no unordered-key Map in this writer.
  guard @encode.text_writer_live_key_inventory(output_bytes, 0, geometry.depth)
    is Some(writer) &&
    @shape.collection_construction_extent({
      // from_json's pending BuildFrames, active iterators and sort of one
      // object's field vector. The shared envelope includes normalization and
      // the seen Map inventory. The emission cursor uses the same depth bound.
      records: 12L + nodes + 14L * depth,
      record_references: 20L + 26L * depth,
      record_words: 16L + nodes + 18L * depth,
      reference_arrays: 2L,
      reference_items: 3L * depth + 1L + fields,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(frames) &&
    @execution.preparation_representation_cost({
      record_headers: frames.record_headers +
      conversion.retained.record_headers +
      conversion.scratch.record_headers +
      writer.record_headers,
      reference_slots: frames.reference_slots +
      conversion.retained.reference_slots +
      conversion.scratch.reference_slots +
      writer.reference_slots,
      scalar_words: frames.scalar_words +
      conversion.retained.scalar_words +
      conversion.scratch.scalar_words +
      writer.scalar_words,
      owned_utf16_units: conversion.retained_utf16_units +
      conversion.scratch_utf16_units +
      writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(encoding) else {
    return None
  }
  // The draft's reachable rows are the same prior prefix. Remain
  // conservative about that old peak while the new tree/writer is live.
  @execution.checked_preparation_add_product(
    Int64::max(row_backing, native),
    encoding,
    1L,
  ).bind(bytes => @execution.execution_capacity(0L, bytes))
}

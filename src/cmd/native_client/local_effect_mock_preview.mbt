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
}

///|
fn native_mock_preview_json(wire : String) -> Json raise ClientStop {
  @json.parse(wire) catch {
    _ => stop("LocalOriginalEffectPreviewEncodingUnavailable")
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
    business.model_work.length() == 1 &&
    state.effect_capture is Some(captured) &&
    state.proposals is Some(proposals) &&
    proposals.materials is Some(materials) &&
    state.preview is None &&
    self.original.project is Some(project) &&
    project.mock_declarations is Some(mock) &&
    mock.write_installations is Some(installations) else {
    stop("LocalOriginalEffectPreviewUnavailable")
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
    let policy = @run_host.client_standard_effect_computation_limits()
    let codec = policy.program.checking.compilation.artifacts
    let max_bytes = native_mock_effect_record_bytes(installation)
    let max_nodes = policy.effects.max_admission_nodes
    let max_depth = policy.effects.max_admission_depth
    let max_work = policy.effects.max_work
    let encode = fn(value : Json) -> String raise ClientStop {
      let original = @canonical.from_json(
        value,
        max_nodes,
        max_depth,
        max_bytes,
        data_keys=true,
      ) catch {
        _ => stop("LocalOriginalEffectPreviewEncodingUnavailable")
      }
      @canonical.stringify_value(original, max_bytes, max_nodes, max_depth) catch {
        _ => stop("LocalOriginalEffectPreviewEncodingUnavailable")
      }
    }
    let digest = fn(value : Json) -> String raise ClientStop {
      "sha256:" +
      @sha.text_hex(encode(value)).unwrap_or_else(() => {
        stop("LocalOriginalEffectPreviewEncodingUnavailable")
      })
    }
    let (key_bytes, key_nodes, key_depth) = @effect.effect_dispatch_key_codec_limits()
    let wire = state.first._retained_models[0]._retained_limits.identity.wire
    guard business.model_work[0].completed_observation_originals(
        state.first._retained_models[0]._retained_limits.output_rows,
      )
      is Some((observation, invocation, models, source_observations)) &&
      @run_host.prepared_client_effect_request_scope(
        materials.prepared,
        state.first.request,
      )
      is Ok(scope) else {
      stop("LocalOriginalEffectPreviewUnavailable")
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
    let task_cid = @run_host.client_infer_occurrence_model_task_cid(
      state.graph.occurrence,
    ).unwrap_or_else(() => {
      stop("LocalOriginalEffectPreviewModelProvenanceUnavailable")
    })
    let model_cids : Array[String] = []
    let response_cids : Array[String] = []
    for original in models {
      guard native_mock_preview_json(
          @publication.run_evidence_value_json(original),
        )
        is Object(fields) &&
        json_text(fields, "model_task_contract_cid") == Some(task_cid) &&
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
    for index, entry in proposals.members {
      let input = @strategy.captured_effect_input_at(proposals.inputs, index).unwrap_or_else(() => {
          stop("LocalOriginalEffectPreviewUnavailable")
        },
      )
      let stage = @strategy.captured_effect_input_stage(input)
      let headers = @checked.effect_program_static_headers(
        @run_host.prepared_client_effect_computation_candidate(
          materials.prepared,
        ),
      )
      let header = @syntax.effect_header_at(headers, index).unwrap_or_else(() => {
        stop("LocalOriginalEffectPreviewUnavailable")
      })
      let descriptor = @run_host.client_effect_member_descriptor(
        materials.prepared,
        stage,
        @syntax.effect_header_id(header),
        max_work,
      ).unwrap_or_else(() => stop("LocalOriginalEffectPreviewUnavailable"))
      guard descriptor.0 == index &&
        descriptor.2 == "update" &&
        descriptor.6 is Some(result_name) &&
        installations
        .iter()
        .find_first(selected => {
          selected.target == descriptor.3 &&
          selected.write.mapping.mapping_ref == descriptor.4 &&
          selected.write.mapping.mapping_cid == descriptor.5
        })
        is Some(selected) &&
        entry._retained_artifact is Some(artifact) &&
        native_mock_preview_json(selected.owner.1) is Object(owner) &&
        native_mock_preview_json(selected.write.mapping.body) is Object(mapping) &&
        mapping.get("required_permissions") is Some(permissions) else {
        stop("LocalOriginalEffectPreviewUnavailable")
      }
      let source = @run_host.issue_client_effect_local_source_artifact(
          materials,
          proposals.inputs,
          index,
          artifact,
          invocation,
          @run_host.client_effect_local_result_retention(artifact),
          selected.binding,
          installation.store_authority_cid,
          max_bytes,
          max_nodes,
          max_depth,
        )
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::PreviewSource(issue)
        })
        .native_effect_proposal(self.original)
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
        .native_effect_proposal(self.original)
      identities.push(identity)
      let changes : Array[Json] = []
      let requests : Array[Json] = []
      for _ in 0..<entry.rows.length() {
        guard state.targets.get(target_index) is Some(target) &&
          target._retained_request is Some((request_wire, request_cid)) &&
          native_mock_preview_json(request_wire) is Object(request) &&
          request.get("target") is Some(target_value) &&
          request.get("before") is Some(before) &&
          request.get("value") is Some(value) &&
          json_text(request, "binding") == Some(selected.binding) &&
          json_text(request, "mapping") == Some(descriptor.5) &&
          json_text(request, "version") is Some(version) else {
          stop("LocalOriginalEffectPreviewTargetUnavailable")
        }
        target_index += 1
        requests.push(Json::string(request_cid))
        changes.push({
          "target_row_identity": target_value,
          "target_guard": {
            "state": "version",
            "version_cid": Json::string(version),
          },
          "before": { "state": "present", "value": before },
          "after": { "state": "present", "value": value },
          "intended_changes": { "state": "present", "value": value },
          "row_preview_cid": Json::string(pending),
          "row_idempotency_key": Json::string(pending),
        })
      }
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
        "operation": "update",
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
        rules,
        index,
        wire.max_columns,
        max_work,
      ).unwrap_or_else(() => stop("LocalOriginalEffectPreviewPlanUnavailable"))
      if terminal is Some(terminal) {
        let cid = @stage_results.effect_plan_pipeline_cid(
          terminal, max_bytes, max_nodes, max_depth,
        ) catch {
          _ => stop("LocalOriginalEffectPreviewPlanUnavailable")
        }
        guard body is Object(fields) else {
          stop("LocalOriginalEffectPreviewUnavailable")
        }
        fields["effect_plan_logical_cid"] = Json::string(cid)
      }
      effects.push(body)
    }
    if target_index != state.targets.length() {
      stop("LocalOriginalEffectPreviewTargetUnavailable")
    }
    let draft = encode({
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
      "model_derived": true,
      "model_task_contract_cids": [Json::string(task_cid)],
      "model_invocation_evidence_cids": Json::array(
        model_cids.map(cid => Json::string(cid)),
      ),
      "model_response_artifact_cids": Json::array(
        response_cids.map(cid => Json::string(cid)),
      ),
      "effects": Json::array(effects),
      "executed": false,
      "effect_preview_cid": Json::string(pending),
    })
    let (semantic, identity) = @publication.author_effect_preview_semantic_wire(
        draft, run_cid, authoring_cid, max_bytes, max_nodes, max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewBody(issue))
      .native_effect_proposal(self.original)
    let keys : Array[Array[@effect.EffectDispatchKey]] = []
    let key_cids : Array[Array[String]] = []
    for index in 0..<@publication.effect_preview_member_count(identity) {
      let row_keys = []
      let row_cids = []
      for
        row in 0..<@publication.effect_preview_row_count(identity, index).unwrap() {
        let correlation = @publication.effect_preview_row_correlation_wire(
          identity, index, row,
        ).unwrap()
        let key = @effect.prepare_effect_dispatch_key(
            scope,
            @publication.effect_preview_semantic_identity(identity),
            correlation,
            key_bytes,
            key_nodes,
            key_depth,
          )
          .map_err(issue => {
            LocalNativeMockEffectProposalIssue::PreviewDispatch(issue)
          })
          .native_effect_proposal(self.original)
        row_keys.push(key)
        row_cids.push(@effect.effect_dispatch_key_cid(key))
      }
      keys.push(row_keys)
      key_cids.push(row_cids)
    }
    let completed = @publication.complete_effect_preview_dispatch_keys(
        semantic, key_cids, run_cid, authoring_cid, max_bytes, max_nodes, max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewBody(issue))
      .native_effect_proposal(self.original)
    @effect.admit_effect_preview_apply_identity(
      completed, run_cid, authoring_cid, scope, keys, max_bytes, max_nodes, max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewKeys(issue))
    .native_effect_proposal(self.original)
    |> ignore
    let preview = @run_host.bind_captured_client_effect_preview(
        materials,
        captured,
        proposals.inputs,
        invocation,
        @strategy.captured_effect_input_stage(
          @strategy.captured_effect_input_at(proposals.inputs, 0).unwrap(),
        ),
        completed,
        authoring_cid,
        identities,
        {
          max_work,
          max_wire_bytes: max_bytes,
          max_nodes,
          max_depth,
          plan: {
            max_work,
            max_fields: wire.max_columns,
            max_bytes,
            max_nodes,
            max_depth,
          },
        },
      )
      .map_err(issue => {
        LocalNativeMockEffectProposalIssue::PreviewBinding(issue)
      })
      .native_effect_proposal(self.original)
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
    }
    // Retain before the verifier or the enclosing original-current callback
    // can fail. Its borrowed pins remain owned by the same proposals record.
    state.preview = Some(held)
    for index, entry in proposals.members {
      let verifier = @strategy.prepare_captured_effect_plan_verifier(
          held.inputs,
          index,
          wire.max_columns,
          max_work,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewPlan(issue))
        .native_effect_proposal(self.original)
      held.verifiers.push(verifier)
      let rows = @canonical.from_json(
        native_mock_preview_json(entry._retained_snapshot_wire.unwrap()),
        codec.nodes,
        codec.depth,
        max_bytes,
        data_keys=true,
      ) catch {
        _ => stop("LocalOriginalEffectPreviewSnapshotUnavailable")
      }
      guard rows is @canonical.Array(values) else {
        stop("LocalOriginalEffectPreviewSnapshotUnavailable")
      }
      for row_index, row in @canonical.array_values(values) {
        @strategy.check_captured_effect_plan_row(
          verifier,
          row,
          row_index,
          wire.max_columns,
          max_work,
          max_bytes,
          max_nodes,
          max_depth,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewPlan(issue))
        .native_effect_proposal(self.original)
        |> ignore
      }
      held.proofs.push(
        @strategy.finish_captured_effect_plan_verifier(verifier)
        .map_err(issue => LocalNativeMockEffectProposalIssue::PreviewPlan(issue))
        .native_effect_proposal(self.original),
      )
    }
    self.prepare_mock_effect_dependency_inventory(
      state, proposals, materials, held, retention, installation,
    )
  })
}

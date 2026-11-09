///|
// Merge only already retained original bodies. The existing dependency Owner
// derives/checks every edge and local source root; this caller neither repairs
// missing evidence nor turns metadata into a physical Store holding.
fn LocalCommandBusinessPreparation::prepare_mock_effect_dependency_inventory(
  self : Self,
  state : LocalNativeMockEffectPlan,
  proposals : LocalNativeMockEffectProposals,
  materials : @run_host.ClientEffectRunMaterials,
  preview : LocalNativeMockEffectPreview,
  retention : Array[@publication.CapturedEffectDependencyBody],
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard proposals._retained_local_manifest is Some(manifest) &&
    proposals.invocation is Some(invocation) &&
    state._retained_local_model_observation is Some(model) &&
    state._retained_local_model_dependencies is Some(model_dependencies) &&
    preview._retained_sources.length() == proposals.members.length() &&
    preview._retained_dependency_inventory is None else {
    stop("LocalOriginalEffectDependencyInventoryUnavailable")
  }
  let policy = @run_host.client_standard_effect_computation_limits()
  let max_bytes = native_mock_effect_record_bytes(installation)
  let max_nodes = policy.effects.max_admission_nodes
  let max_depth = policy.effects.max_admission_depth
  let work = state.first._retained_models[0]._retained_limits.output_work
  let limits : @publication.CapturedEffectDependencyLimits = {
    max_entries: Int::min(4096, work),
    max_total_bytes: max_bytes,
    max_depth: 64,
    max_references: Int::min(65536, work),
  }
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  let roots : Array[@publication.CapturedEffectDependencyBody] = []
  let seen : Map[String, String] = Map([])
  let mut remaining = max_bytes
  let refuse = fn(
    issue : @publication.CapturedEffectDependencyIssue,
  ) -> Unit raise ClientStop {
    let result : Result[Unit, LocalNativeMockEffectProposalIssue] = Err(
      Inventory(issue),
    )
    result.native_effect_proposal(self.original)
  }
  let retain = fn(
    body : @publication.CapturedEffectDependencyBody,
  ) -> Unit raise ClientStop {
    let key = @publication.captured_effect_dependency_body_kind(body) +
      "\u0000" +
      @publication.captured_effect_dependency_body_cid(body)
    let wire = @publication.captured_effect_dependency_body_json(body)
    if seen.get(key) is Some(original) {
      if original != wire {
        refuse(DuplicateIdentity)
      }
      return
    }
    if bodies.length() >= limits.max_entries {
      refuse(EntryLimit)
    }
    let bytes = @utf8.encode(wire).length()
    if bytes > remaining {
      refuse(ByteLimit)
    }
    remaining -= bytes
    bodies.push(body)
    seen[key] = wire
  }
  let append = fn(
    kind : String,
    cid : String?,
    wire : String,
  ) -> Unit raise ClientStop {
    let body = @publication.admit_captured_effect_dependency_body(
        kind, cid, wire, max_bytes, max_nodes, max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Inventory(issue))
      .native_effect_proposal(self.original)
    retain(body)
  }
  for body in retention {
    retain(body)
  }
  for body in proposals._retained_lookup_dependencies {
    retain(body)
  }
  // The imported producer's complete original Artifact/Manifest closure is
  // additional to the Model observation and Lookup protocol, never replaced
  // by their CIDs or the narrower contributing Source metadata.
  for source in proposals.source_imports {
    append(
      "local_computation",
      None,
      @run_host.client_effect_local_invocation_json(
        @run_host.client_effect_acquired_invocation(source.source),
      ),
    )
    if source.manifest is Some(original) {
      append(
        "local_manifest",
        None,
        @run_host.client_effect_local_manifest_json(original),
      )
    }
    for capture in source.captures {
      for body in @run_host.client_effect_dependency_capture_bodies(capture) {
        retain(body)
      }
    }
  }
  for observed in proposals.import_observations {
    append(
      "result_import_observation",
      None,
      @run_host.client_effect_result_import_observation_json(observed),
    )
  }
  if proposals.imports is Some(original) {
    append(
      "acquisition_scope",
      None,
      @run_host.client_effect_imported_scope_json(original),
    )
    for relation in @run_host.client_effect_imported_relation_bodies(original) {
      append("acquisition_relation", None, relation)
    }
  }
  retain(model)
  for (kind, wire) in model_dependencies {
    append(kind, None, wire)
  }
  let source_evidence = if proposals.imports is Some(_) {
    proposals.source_imports.map(source => source.source)
  } else {
    proposals._retained_direct_evidence
  }
  for acquired in source_evidence {
    for
      (kind, wire) in @run_host.client_effect_acquired_dependency_bodies(
        acquired,
      ) {
      append(kind, None, wire)
    }
    let catalog = @run_host.client_effect_acquired_catalog_bodies(
        acquired, max_bytes, max_nodes, max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Source(issue))
      .native_effect_proposal(self.original)
    for (kind, cid, wire) in catalog {
      append(kind, Some(cid), wire)
    }
  }
  for index, entry in proposals.members {
    guard entry._retained_artifact is Some(artifact) &&
      entry._retained_dependency is Some(capture) &&
      @run_host.client_effect_dependency_capture_matches_artifact(
        capture, artifact,
      ) else {
      stop("LocalOriginalEffectDependencyInventoryUnavailable")
    }
    for body in @run_host.client_effect_dependency_capture_bodies(capture) {
      retain(body)
    }
    let original_artifact = @run_host.client_effect_local_result_artifact_contract(
      artifact,
    )
    let source = @publication.admit_captured_effect_source_from_result(
        @strategy.captured_effect_preview_ledger_identity(preview.inputs),
        index,
        preview._retained_invocation,
        preview._retained_sources[index],
        original_artifact,
        installation.store_authority_cid,
      )
      .map_err(issue => {
        LocalNativeMockEffectProposalIssue::CapturedSource(issue)
      })
      .native_effect_proposal(self.original)
    preview._retained_captured_sources.push(source)
    let local_source = @run_host.admit_client_effect_local_source_evidence(
        materials.prepared,
        proposals.inputs,
        index,
        manifest,
        invocation,
        artifact,
        source,
        max_bytes,
        max_nodes,
        max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::LocalSource(issue))
      .native_effect_proposal(self.original)
    preview._retained_local_sources.push(local_source)
    let root = @publication.admit_publication_effect_dependency_body(
        "result_artifact",
        @publication.publication_contract_json(original_artifact),
        max_bytes,
        max_nodes,
        max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Inventory(issue))
      .native_effect_proposal(self.original)
    roots.push(root)
  }
  let inventory = @publication.issue_captured_effect_dependency_inventory(
      bodies, roots, limits, max_nodes, max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Inventory(issue))
    .native_effect_proposal(self.original)
  preview._retained_dependency_inventory = Some(
    @publication.admit_captured_effect_source_dependencies(
      preview._retained_local_sources,
      @publication.captured_effect_dependency_inventory_json(inventory),
      max_bytes,
      max_nodes,
      max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Inventory(issue))
    .native_effect_proposal(self.original),
  )
}

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
    let bytes = @publication.captured_effect_dependency_body_bytes(body)
    if bytes > remaining {
      refuse(ByteLimit)
    }
    remaining -= bytes
    bodies.push(body)
    seen[key] = wire
  }
  let retain_capture = fn(
    capture : @run_host.ClientEffectDependencyCapture,
  ) -> Unit raise ClientStop {
    let count = @run_host.client_effect_dependency_capture_body_count(capture)
    for index in 0..<count {
      retain(
        @run_host.client_effect_dependency_capture_body_at(capture, index).unwrap(),
      )
    }
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
      retain_capture(capture)
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
  guard proposals.acquired is Some(acquired) else {
    stop("LocalOriginalEffectDependencyInventoryUnavailable")
  }
  // The Model Artifact retains the combined imported+keyed scope. Individual
  // Source and imported scopes above are its inputs, not that original body.
  append(
    "acquisition_scope",
    None,
    @run_host.client_effect_model_acquired_scope_json(acquired),
  )
  retain(model)
  for (kind, cid, wire) in model_dependencies {
    append(kind, Some(cid), wire)
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
      append(
        kind,
        if kind == "request_values" {
          Some(@run_host.client_effect_acquired_request_cid(acquired))
        } else {
          None
        },
        wire,
      )
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
  // Sibling Results remain retained for the COMPLETE Unit Manifest above.
  // They are not additional Effect sources or roots. Only dependencies of
  // actual consumed members belong in this exact saved Effect closure.
  let construction = proposals.construction.unwrap_or_else(() => {
    stop("LocalOriginalEffectDependencyInventoryUnavailable")
  })
  // Measuring uses the existing bounded Writer frame inventory, conservatively
  // including hash state. It owns no output text. No retained body is invented.
  let measuring = mock_effect_dependency_measurement_bytes(max_nodes, max_depth).unwrap_or_else(() => {
      stop("LocalOriginalEffectDependencyInventoryUnavailable")
    },
  )
  if !construction.resize(
      self.original,
      construction.recipe,
      construction.retained,
      Int64::max(construction.workspace, measuring),
    ) {
    stop("LocalOriginalEffectDependencyInventoryUnavailable")
  }
  let policy_bodies = @run_host.prepared_client_effect_publication_policy_bodies(
      state._retained_prepared,
      max_bytes,
      max_nodes,
      max_depth,
      retained_body_keys=Some(seen),
      before_body=Some((bytes, nodes, depth) => {
        construction.prepare_canonical(self.original, bytes, nodes, depth)
      }),
    )
    .map_err(issue => {
      LocalNativeMockEffectProposalIssue::PolicyDependency(issue)
    })
    .native_effect_proposal(self.original)
  for (kind, cid, wire) in policy_bodies {
    append(kind, Some(cid), wire)
  }
  for index, entry in proposals.members {
    guard entry._retained_artifact is Some(artifact) &&
      entry._retained_dependency is Some(capture) &&
      @run_host.client_effect_dependency_capture_matches_artifact(
        capture, artifact,
      ) else {
      stop("LocalOriginalEffectDependencyInventoryUnavailable")
    }
    retain_capture(capture)
    let original_artifact = @run_host.client_effect_local_result_artifact_contract(
      artifact,
    )
    bind_mock_effect_dependency_source(
      proposals,
      preview,
      index,
      artifact,
      materials,
      manifest,
      invocation,
      installation.store_authority_cid,
      max_bytes,
      max_nodes,
      max_depth,
      issue => {
        self.original.retain_primary(CommandBusinessEffectProposals(issue))
      },
    )
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
  // The original capture holds the live collector. Keep that backing
  // alongside the graph census, copied root/body arrays and measured writer.
  let mut references = roots.length().to_int64()
  let mut key_units = 0L
  for body in bodies {
    let (count, units) = @publication.captured_effect_dependency_body_index_geometry(
      body,
    )
    references += count.to_int64()
    key_units += units
  }
  if references > limits.max_references.to_int64() {
    refuse(ReferenceLimit)
  }
  let graph = @local_values.installed_effect_dependency_graph_capacity(
    bodies.length(),
    roots.length(),
    references.to_int(),
    key_units,
  )
  let held_roots = @execution.preparation_array_representation(
    1L,
    roots.length().to_int64(),
    false,
  ).bind(@execution.preparation_representation_cost)
  // The preparation's body copy, record, limits and measured geometry
  // stay live until the returned inventory takes the root copy.
  let held_bodies = @execution.preparation_array_representation(
    1L,
    bodies.length().to_int64(),
    false,
  ).bind(view => {
    @execution.preparation_representation_cost({
      ..view,
      record_headers: view.record_headers + 3L,
      reference_slots: view.reference_slots + 4L,
      scalar_words: view.scalar_words + 13L,
    })
  })
  let depth = max_depth.to_int64()
  // Each open canonical container owns a cursor and parent variant.
  // The growing parent array coexists with the Writer's own frame array.
  // The fixed margin covers the geometry sink/state, returned nine-word
  // geometry, prepared limits/result and the synchronous work carrier.
  let census_stack = @shape.collection_construction_extent({
    records: 12L + 2L * depth,
    record_references: 16L + 2L * depth,
    record_words: 20L + 2L * depth,
    reference_arrays: 1L,
    reference_items: depth,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).bind(stack => {
    @execution.preparation_representation_cost({
      record_headers: stack.record_headers,
      reference_slots: stack.reference_slots,
      scalar_words: stack.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
  })
  let prepare_capacity = match (graph, held_roots, held_bodies, census_stack) {
    (Some(graph), Some(roots), Some(bodies), Some(stack)) =>
      @execution.checked_preparation_add_product(roots, bodies, 1L)
      .bind(held => {
        @execution.checked_preparation_add_product(held, measuring, 1L)
      })
      .bind(frame => {
        @execution.checked_preparation_add_product(frame, stack, 1L)
      })
      .bind(frame => {
        // The graph validator has returned before the census starts.
        @execution.execution_capacity(
          roots,
          Int64::max(
            @execution.execution_capacity_execution_bytes(graph),
            frame,
          ),
        )
      })
    _ => None
  }
  construction
  .prepare_body_result(prepare_capacity)
  .native_effect_proposal(self.original)
  let prepared = @publication.prepare_captured_effect_dependency_inventory(
      bodies,
      roots,
      max_nodes,
      max_depth,
      _ => true,
      bounded_limits=Some(limits),
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Inventory(issue))
    .native_effect_proposal(self.original)
  // The original prepared vectors and a growing filtered root array can
  // coexist with the comparison Writer, or with another graph validation
  // after the comparison has returned. No emitted inventory exists yet.
  let selected_roots = @execution.preparation_array_representation(
    1L,
    roots.length().to_int64(),
    true,
  ).bind(@execution.preparation_representation_cost)
  let bind_workspace = match
    (graph, held_bodies, selected_roots, held_roots, census_stack) {
    (Some(graph), Some(bodies), Some(roots), Some(copy), Some(stack)) =>
      @execution.checked_preparation_add_product(measuring, stack, 1L)
      .bind(compare => {
        @execution.checked_preparation_add_product(
          Int64::max(
            @execution.execution_capacity_execution_bytes(graph),
            compare,
          ),
          bodies,
          1L,
        )
      })
      .bind(frame => {
        @execution.checked_preparation_add_product(frame, roots, 1L)
      })
      // A filtered result returns a fixed-size copy. Until it has returned,
      // keep the original root vector, growing selection and final copy paid.
      .bind(frame => @execution.checked_preparation_add_product(frame, copy, 1L))
    _ => None
  }
  let prepared = construction
    .bind_dependency_inventory_sources(
      prepared,
      preview._retained_local_sources,
      max_bytes,
      max_nodes,
      max_depth,
      bind_workspace,
    )
    .native_effect_proposal(self.original)
  let envelope = @local_values.installed_effect_dependency_envelope_capacity(
    @publication.prepared_captured_effect_dependency_inventory_geometry(
      prepared,
    ),
    bodies.length(),
    key_units,
  )
  // The prepared body vector is still borrowed by the issuer. Its root
  // vector was charged above and is the same array returned by issuance.
  let issue_capacity = match (envelope, held_bodies) {
    (Some(envelope), Some(view)) =>
      @execution.execution_capacity(0L, view).bind(view => {
        @execution.add_execution_capacity(envelope, view)
      })
    _ => None
  }
  construction
  .prepare_body_result(issue_capacity)
  .native_effect_proposal(self.original)
  preview._retained_dependency_inventory = Some(
    @publication.issue_prepared_captured_effect_dependency_inventory(prepared, _ => {
      true
    })
    .map_err(issue => LocalNativeMockEffectProposalIssue::Inventory(issue))
    .native_effect_proposal(self.original),
  )
}

///|
fn LocalNativeMockEffectImportConstruction::bind_dependency_inventory_sources(
  self : Self,
  prepared : @publication.PreparedCapturedEffectDependencyInventory,
  sources : Array[@publication.CapturedLocalEffectSourceEvidence],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  workspace : Int64?,
) -> Result[
  @publication.PreparedCapturedEffectDependencyInventory,
  LocalNativeMockEffectProposalIssue,
] {
  match
    self.prepare_body_result(
      workspace.bind(bytes => @execution.execution_capacity(0L, bytes)),
    ) {
    Err(issue) => Err(issue)
    Ok(_) =>
      @publication.bind_aligned_prepared_effect_dependency_sources(
        prepared, sources, max_bytes, max_nodes, max_depth,
      ).map_err(issue => LocalNativeMockEffectProposalIssue::Inventory(issue))
  }
}

///|
fn mock_effect_dependency_measurement_bytes(
  max_nodes : Int,
  max_depth : Int,
) -> Int64? {
  @encode.hash_writer_construction_inventory(max_nodes, max_depth).bind(inventory => {
    @execution.preparation_representation_cost({
      record_headers: inventory.record_headers,
      reference_slots: inventory.reference_slots,
      scalar_words: inventory.scalar_words,
      owned_utf16_units: inventory.owned_utf16_units,
      owned_wire_bytes: inventory.owned_wire_bytes,
    })
  })
}

///|
// Feed all selected original members to the existing funded dependency owner.
// That owner checks and deduplicates the Result roots by exact original wire.
fn LocalNativeMockEffectPlan::prepare_direct_mock_effect_dependencies(
  state : Self,
  run : @local_values.ClientInstalledManagedRun,
  retention : Array[@publication.CapturedEffectDependencyBody],
  store_authority : String,
  max_bytes : Int,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> Unit raise ClientStop {
  guard state.first._retained_models.is_empty() &&
    state.direct_sources is Some(direct) &&
    direct.captures.length() == direct.identities.length() &&
    state.proposals is Some(proposals) &&
    proposals.materials is Some(materials) &&
    proposals._retained_combined_source_unit is Some(combined) &&
    proposals._retained_local_manifest is Some(manifest) &&
    proposals.invocation is Some(invocation) &&
    proposals.construction is Some(construction) &&
    state.preview is Some(preview) &&
    preview._retained_dependency_inventory is None &&
    preview._retained_sources.length() == proposals.members.length() &&
    preview._retained_local_sources.is_empty() &&
    preview._retained_captured_sources.is_empty() else {
    stop("LocalOriginalEffectDependencyInventoryUnavailable")
  }
  let prepared = state._retained_prepared
  let limits = @run_host.client_standard_effect_computation_limits().effects
  let measuring = mock_effect_dependency_measurement_bytes(
    limits.max_admission_nodes,
    limits.max_admission_depth,
  ).unwrap_or_else(() => {
    stop("LocalOriginalEffectDependencyInventoryUnavailable")
  })
  construction
  .resize_result(
    construction.recipe,
    construction.retained,
    Int64::max(construction.workspace, measuring),
  )
  .native_effect_proposal_with_cause(report)
  let policy_bodies = @run_host.prepared_client_effect_publication_policy_bodies(
      prepared,
      max_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
      retain_catalog=false,
      before_body=Some((bytes, nodes, depth) => {
        construction
        .prepare_body_result(
          native_mock_effect_canonical_body_capacity(bytes, nodes, depth),
        )
        .retain_mock_effect_proposal_issue(report)
      }),
    )
    .map_err(issue => {
      LocalNativeMockEffectProposalIssue::PolicyDependency(issue)
    })
    .native_effect_proposal_with_cause(report)
  let mut entries = retention.length().to_int64() +
    policy_bodies.length().to_int64() +
    2L * direct.identities.length().to_int64() +
    @run_host.client_effect_combined_source_unit_dependency_body_count(combined)
  for index, entry in proposals.members {
    guard entry._retained_artifact is Some(artifact) &&
      entry._retained_dependency is Some(capture) &&
      @run_host.client_effect_dependency_capture_matches_artifact(
        capture, artifact,
      ) else {
      stop("LocalOriginalEffectDependencyInventoryUnavailable")
    }
    entries += @run_host.client_effect_dependency_capture_body_count(capture).to_int64()
    bind_mock_effect_dependency_source(
      proposals,
      preview,
      index,
      artifact,
      materials,
      manifest,
      invocation,
      store_authority,
      max_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
      report,
    )
  }
  // Preview and its source bindings are complete. Keep their original
  // retained bytes, and return the synchronous constructor scratch before
  // the distinct, already budgeted group enters its own work.
  match
    @local_values.yield_installed_effect_operation_construction_workspace(
      construction.operation,
    ) {
    Ok(_) => ()
    Err(issue) => {
      report(Managed(issue))
      stop("LocalOriginalEffectDependencyWorkspaceUnavailable")
    }
  }
  // The existing group owns the parallel Host vectors plus admission, graph
  // and envelope geometry. Count the actual candidates before copying them.
  if entries > 2147483647L - proposals.members.length().to_int64() {
    stop("LocalOriginalEffectDependencyInventoryUnavailable")
  }
  let request = state.first.request
  let plan = state._retained_plan
  match
    @local_values.reserve_installed_effect_dependency_group(
      run,
      prepared,
      request,
      plan,
      entries.to_int(),
      proposals.members.length(),
    ) {
    Ok(_) => ()
    Err(issue) => {
      report(Managed(issue))
      stop("LocalOriginalEffectDependencyReservationUnavailable")
    }
  }
  let kinds : Array[String] = []
  let identities : Array[String?] = []
  let wires : Array[String] = []
  let roots : Array[@run_host.ClientEffectLocalResultArtifact] = []
  let originals : Array[@run_host.ClientEffectLocalResultArtifact] = []
  let append = (kind, cid, wire) => {
    kinds.push(kind)
    identities.push(Some(cid))
    wires.push(wire)
  }
  let retain = body => {
    append(
      @publication.captured_effect_dependency_body_kind(body),
      @publication.captured_effect_dependency_body_cid(body),
      @publication.captured_effect_dependency_body_json(body),
    )
  }
  for body in retention {
    retain(body)
  }
  for (kind, cid, wire) in policy_bodies {
    append(kind, cid, wire)
  }
  // The Source relations and schemas are distinct from the completed Result.
  // Borrow the preimages already backed by each original Source identity scan.
  for index, identity in direct.identities {
    guard @query.captured_source_relation_dependency_bodies(
        identity,
        direct.captures[index],
      )
      is Some((relation, schema)) else {
      stop("LocalOriginalEffectSourceDependenciesUnavailable")
    }
    append(
      "relation_value",
      @query.captured_source_relation_logical_cid(identity),
      relation,
    )
    append(
      "relation_schema",
      @query.captured_source_relation_schema_cid(identity),
      schema,
    )
  }
  for
    (kind, cid, wire) in @run_host.client_effect_combined_source_unit_dependency_bodies(
      combined,
    ) {
    append(kind, cid, wire)
  }
  for entry in proposals.members {
    let artifact = entry._retained_artifact.unwrap()
    roots.push(artifact)
    if !originals.any(original => physical_equal(original, artifact)) {
      originals.push(artifact)
      for
        body in @run_host.client_effect_dependency_capture_bodies(
          entry._retained_dependency.unwrap(),
        ) {
        retain(body)
      }
    }
  }
  match
    @local_values.prepare_installed_effect_dependency_inventory_retained(
      run,
      prepared,
      request,
      plan,
      kinds,
      identities,
      wires,
      roots,
      max_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
      original_artifacts=originals,
    ) {
    Ok(inventory) => preview._retained_dependency_inventory = Some(inventory)
    Err(issue) => {
      report(Managed(issue))
      stop("LocalOriginalEffectDependencyInventoryUnavailable")
    }
  }
}

///|
// The original entry selects its checked Result and Run binding even when
// several members share its physical export. Each keeps its own source token.
fn bind_mock_effect_dependency_source(
  proposals : LocalNativeMockEffectProposals,
  preview : LocalNativeMockEffectPreview,
  index : Int,
  artifact : @run_host.ClientEffectLocalResultArtifact,
  materials : @run_host.ClientEffectRunMaterials,
  manifest : @run_host.ClientEffectLocalManifest,
  invocation : @run_host.ClientEffectLocalInvocation,
  store_authority : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> Unit raise ClientStop {
  let original_artifact = @run_host.client_effect_local_result_artifact_contract(
    artifact,
  )
  let source = @publication.admit_captured_effect_source_from_result(
      @strategy.captured_effect_preview_ledger_identity(preview.inputs),
      index,
      preview._retained_invocation,
      preview._retained_sources[index],
      original_artifact,
      store_authority,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::CapturedSource(issue))
    .native_effect_proposal_with_cause(report)
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
    .native_effect_proposal_with_cause(report)
  preview._retained_local_sources.push(local_source)
}

///|
// Native placement from original measured wire/container facts, independently
// of the byte tariff. No policy maximum or unused R/E becomes a raw request.
fn saved_effect_compiler_native_raw(
  value : @run_host.ClientPureCompilationConstruction,
) -> Int64? {
  let mut bytes = 0L
  let mut nodes = 0L
  for
    extent in [
      value.nodes,
      value.edges,
      value.roots,
      value.graph,
      value.program,
      value.material,
      value.fact_manifest,
      value.executable_plan,
    ] {
    bytes = Int64::max(bytes, extent.0.to_int64())
    nodes = Int64::max(nodes, extent.1.to_int64())
  }
  for
    group in [
      value.borrowed_inputs,
      value.results,
      value.facts.limits,
      value.facts.bindings,
      value.facts.entries,
      value.witnesses.bodies,
    ] {
    for extent in group {
      bytes = Int64::max(bytes, extent.0.to_int64())
      nodes = Int64::max(nodes, extent.1.to_int64())
    }
  }
  for fragment in value.fragments {
    for
      extent in [
        fragment.initial_pipeline,
        fragment.pipeline,
        fragment.fragment,
        fragment.output_contract,
      ] {
      bytes = Int64::max(bytes, extent.0.to_int64())
      nodes = Int64::max(nodes, extent.1.to_int64())
    }
    for extent in fragment.input_contracts {
      bytes = Int64::max(bytes, extent.0.to_int64())
      nodes = Int64::max(nodes, extent.1.to_int64())
    }
  }
  for projection in value.projections {
    for
      extent in [
        projection.pipeline,
        projection.node,
        projection.edge,
        projection.root,
        projection.parts,
        projection.direct_root,
      ] {
      bytes = Int64::max(bytes, extent.0.to_int64())
      nodes = Int64::max(nodes, extent.1.to_int64())
    }
  }
  @local_host.native_saved_effect_constructor_placement(bytes, 16L + 4L * nodes)
}

///|
// The existing full recovery envelope already covers input+compiler. Only
// temporary measurement metadata extends its phase peak; never add a second
// compiler allowance to that whole-operation reservation.
fn LocalCommandPreparationOriginal::prepare_saved_effect_compiler_placement(
  self : Self,
  work : LocalNativeSavedEffectFileWork,
  input : @run_host.ClientEffectCompilationConstructionInput,
  limits : @run_host.ClientValuesRunMaterialsLimits,
) -> Result[Unit, @run_host.ClientEffectRunMaterialsIssue] {
  guard work.entry is Some(entry) else { return Err(Compilation(Encoding)) }
  let selected : @run_host.ClientPureCompilationLimits = {
    max_facts: limits.max_sequence_steps,
    max_witnesses: limits.max_sequence_work,
    max_wire_bytes: limits.max_evidence_bytes,
    max_nodes: limits.max_evidence_nodes,
    max_depth: limits.max_evidence_depth,
  }
  let storage = match
    @run_host.prepared_client_effect_measurement_storage(input, selected) {
    // Unmeasured families keep their existing complete conservative recipe;
    // observation support must not become another semantic admission guard.
    Err(_) => return Ok(())
    Ok(value) => value
  }
  guard @execution.preparation_representation_cost(storage) is Some(metadata) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_retained_bytes(work.capacity),
      metadata,
      1L,
    )
    is Some(peak) &&
    @execution.execution_capacity(
      @execution.execution_capacity_retained_bytes(work.capacity),
      Int64::max(
        @execution.execution_capacity_execution_bytes(work.capacity),
        peak,
      ),
    )
    is Some(capacity) &&
    @local_host.native_saved_effect_constructor_placement(
      Int64::max(storage.owned_utf16_units, storage.owned_wire_bytes),
      16L + 4L * Int64::max(storage.reference_slots, storage.scalar_words),
    )
    is Some(raw) else {
    self.retain_primary(CommandUnavailable)
    return Err(Compilation(Encoding))
  }
  work.capacity = capacity
  match
    entry.prepare_constructor_in_entered_scope(
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
      raw,
    ) {
    Err(issue) => {
      self.retain_primary(CommandSavedFileEntry(issue))
      // Unwind only. The actual original Native cause remains primary above.
      return Err(Compilation(Encoding))
    }
    Ok(_) => ()
  }
  let measured = match
    @run_host.measure_prepared_client_effect_compilation_construction(
      input,
      native_request_manifests,
      limits.sequence,
      selected,
    ) {
    Err(_) => return Ok(())
    Ok(value) => value
  }
  guard saved_effect_compiler_native_raw(
      @run_host.client_effect_compilation_construction_geometry(measured),
    )
    is Some(raw) else {
    self.retain_primary(CommandUnavailable)
    return Err(Compilation(Encoding))
  }
  match
    entry.prepare_constructor_in_entered_scope(
      @execution.execution_capacity_retained_bytes(work.capacity),
      @execution.execution_capacity_execution_bytes(work.capacity),
      raw,
    ) {
    Err(issue) => {
      self.retain_primary(CommandSavedFileEntry(issue))
      Err(Compilation(Encoding))
    }
    Ok(_) => Ok(())
  }
}

///|
// Both initial Request and Saved restoration use the SAME subject recipe.
// Retain these actual constructor extents on the original business entry;
// there is no spare-capacity guess, new Request, or second compiler envelope.
fn LocalCommandPreparationOriginal::reserve_saved_effect_policy_inventory(
  self : Self,
  work : LocalNativeSavedEffectFileWork,
  inventory : @execution.PreparationRepresentationUnits,
) -> Result[Unit, @run_host.ClientEffectComputationIssue] {
  guard !self.closing &&
    !self.closed &&
    self.business is Some(business) &&
    business.saved_effect_files is Some(original) &&
    physical_equal(original, work) &&
    work.entry is Some(entry) &&
    @execution.preparation_representation_cost(inventory) is Some(bytes) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_retained_bytes(work.capacity),
      bytes,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(work.capacity),
      bytes,
      1L,
    )
    is Some(execution) &&
    @execution.execution_capacity(retained, execution) is Some(capacity) &&
    @local_host.native_saved_effect_constructor_placement(
      Int64::max(inventory.owned_utf16_units, inventory.owned_wire_bytes),
      16L + 4L * Int64::max(inventory.reference_slots, inventory.scalar_words),
    )
    is Some(raw) else {
    return Err(@run_host.RequestValuePolicyConstruction)
  }
  work.capacity = capacity
  match entry.prepare_constructor_in_entered_scope(retained, execution, raw) {
    Ok(_) => Ok(())
    Err(issue) => {
      self.retain_primary(CommandSavedFileEntry(issue))
      Err(@run_host.RequestValuePolicyConstruction)
    }
  }
}

///|
// One pure Host verification per original subject, BEFORE restored Graph and
// compiler construction. A decline still advances the original binder. The
// existing nominal matcher and independent Plan/Run/Request checks remain the
// only admission route; no attestation is serialized or inferred from a CID.
fn local_saved_effect_request_value_policies(
  computation : @checked.EffectComputationCandidate,
  limits : @checked.CompileLimits,
  reserve : (@execution.PreparationRepresentationUnits) -> Result[
    Unit,
    @run_host.ClientEffectComputationIssue,
  ],
  verify : (String) -> String?,
) -> Result[
  Array[@checked.HostRequestValuePolicyEvidence],
  @run_host.ClientEffectComputationIssue,
] {
  let original = @checked.effect_computation_checked_program(computation)
  guard @local_values.request_policy_subject_prelude_inventory(
      original,
      @checked.effect_computation_supplied(computation),
      limits,
    )
    is Some((inventory, inspection)) &&
    @local_values.request_policy_subject_work_limit(inspection, limits)
    is Some(maximum) else {
    return Err(@run_host.RequestValuePolicyConstruction)
  }
  match reserve(inventory) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let subjects = @checked.begin_request_policy_subjects(
    original,
    limits,
    cumulative_work=Some(maximum - inspection.to_int64()),
  ) catch {
    issue => return Err(@run_host.RequestValuePolicies(issue))
  }
  defer @checked.retire_request_policy_subjects(subjects)
  try {
    @checked.measure_request_policy_subjects(subjects)
    guard @local_values.request_policy_subject_output_inventory(subjects)
      is Some(inventory) else {
      return Err(@run_host.RequestValuePolicyConstruction)
    }
    match reserve(inventory) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    @checked.construct_request_policy_subjects(subjects)
    let evidence = []
    for index in 0..<@checked.request_policy_subject_count(subjects) {
      // Refuse an exhausted prefix before another Host verifier runs.
      if @checked.request_policy_subjects_spent_work(subjects) >=
        maximum - inspection.to_int64() {
        return Err(@run_host.RequestValuePolicyConstruction)
      }
      let wire = @checked.request_policy_subject_wire(subjects, index)
      let policy = verify(wire)
      match
        @checked.bind_prepared_request_policy_subject(subjects, index, policy) {
        Some(proof) => evidence.push(proof)
        None => ()
      }
    }
    Ok(evidence)
  } catch {
    issue => Err(@run_host.RequestValuePolicies(issue))
  }
}

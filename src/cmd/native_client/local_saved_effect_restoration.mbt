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

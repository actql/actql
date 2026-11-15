///|
/// Measure and issue the Source-only keyed component on its actual Request.
/// The existing four-reference domain-input slot retains the lowering before
/// the next fallible reservation. No Model occurrence, compiler or Root is
/// manufactured for this checked Effect.
pub fn[I] prepare_request_effect_keyed_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  keyed : @publication_host.ClientKeyedAcquisition,
  contracts : ClientInstalledSequenceContracts,
  declarations : Array[@row_source_host.RowDeclaration],
) -> Result[
  @publication_host.ClientEffectKeyedPlanGraph,
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == EffectPlanReserved &&
    owner.compiled_effect is Some(prepared) &&
    owner.effect_capacity is Some(_) &&
    owner.effect_plan is None &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs is None &&
    @publication_host.client_keyed_acquisition_matches_effect_program(
      keyed, prepared,
    ) &&
    @publication_host.prepared_client_effect_infer_count(prepared) == Some(0) else {
    return Err(Preparation(ForeignOriginal))
  }
  guard @publication_host.client_keyed_acquisition_source_evidence_facts(keyed)
    is Some(facts) else {
    return Err(Preparation(ForeignOriginal))
  }
  let mut profile = None
  for declaration in declarations {
    if @row_source_host.row_declaration_file_read_profile(
        declaration,
        facts.source_ref,
      )
      is Some(selected) {
      guard profile is None &&
        @publication.file_read_profile_contract_bindings(selected)
        is Some((original_cid, _, _)) &&
        original_cid == facts.source_contract_cid else {
        return Err(Preparation(ForeignOriginal))
      }
      profile = Some(selected)
    }
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      guard @publication_host.prepared_client_effect_keyed_plan_measurement_storage(
          prepared,
          keyed,
          generic=profile is None,
        )
        is Some(storage) &&
        @execution.compose_preparation_representation([
          storage,
          @publication_host.client_effect_allowed_keyed_run_construction_inventory(),
          keyed_initial_definition_view_representation(),
          // Node's compact nominal token (1H1R), its existing WeakMap entry
          // (1H3R1W), and immutable selected tuple (1H5R). Two existing
          // Request/Run fields borrow those exact selected originals. The actual
          // Source identity and managed-parent tuple add two borrowed slots.
          {
            record_headers: 3L,
            reference_slots: 13L,
            scalar_words: 1L,
            owned_utf16_units: 0L,
            owned_wire_bytes: 0L,
          },
        ])
        is Some(storage) &&
        @execution.preparation_representation_cost(storage) is Some(bytes) &&
        owner.program_data is Some(data) &&
        program_check_data_extent_cost(data) is Some(variable) &&
        // The selected Source component has two actual Fragment lowerings.
        @execution.checked_preparation_add_product(bytes, variable, 2L)
        is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_model_graph_construction(
          owner,
          input,
          Effect(prepared),
          bytes,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let measurement = match profile {
        Some(profile) =>
          @publication_host.measure_client_effect_keyed_plan_construction(
            prepared,
            keyed,
            profile,
            client_local_owner_sequence_limits(Effect(prepared)),
            100000,
            10000,
            100,
          )
        None =>
          // The compiler itself checks actual file-content facts and Carrier.
          // No absent Native profile is replaced by a declaration or permission.
          @publication_host.measure_client_effect_generic_keyed_plan_construction(
            prepared,
            keyed,
            client_local_owner_sequence_limits(Effect(prepared)),
            100000,
            10000,
            100,
          )
      }
      let measured = match measurement {
        Err(issue) => return Err(ModelGraph(issue))
        Ok(value) => value
      }
      owner.program_domain_compilation_inputs = Some(
        RequestEffectKeyedGraphConstruction(
          prepared, keyed, contracts, measured,
        ),
      )
      guard effect_keyed_graph_construction_cost(measured) is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_model_graph_construction(
          owner,
          input,
          Effect(prepared),
          bytes,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard owner.program_domain_compilation_inputs
        is Some(RequestEffectKeyedGraphConstruction(p, k, c, original)) &&
        physical_equal(p, prepared) &&
        physical_equal(k, keyed) &&
        physical_equal(c, contracts) &&
        physical_equal(original, measured) else {
        return Err(Preparation(ForeignOriginal))
      }
      let graph = match
        @publication_host.issue_client_effect_keyed_plan_graph(
          original, 100000, 10000, 100,
        ) {
        Err(issue) => return Err(ModelGraph(issue))
        Ok(value) => value
      }
      owner.program_domain_compilation_inputs = Some(
        RequestEffectKeyedGraph(prepared, keyed, contracts, graph),
      )
      owner.program_domain_quote = None
      owner.phase = EffectPlanReserved
      Ok(graph)
    },
    () => if owner.phase == Selecting { owner.phase = EffectBodyFailed },
  )
}

///|
// Actual measured parser/writer coexistence, never max codec bytes. Reuse the
// same compiler layout recipes and tariff as the existing Model/Content graph.
fn effect_keyed_graph_construction_cost(
  value : @publication_host.ClientEffectKeyedPlanConstruction,
) -> Int64? {
  let bodies = [value.barrier, value.node]
  let wires = [value.node]
  let mut labels = 0L
  for fragment in value.fragments {
    bodies.push(fragment.initial_pipeline)
    bodies.push(fragment.pipeline)
    bodies.push(fragment.fragment)
    bodies.push(fragment.output_contract)
    for contract in fragment.input_contracts {
      bodies.push(contract)
    }
    wires.push(fragment.fragment)
    labels += fragment.node_id.length().to_int64()
  }
  let mut held : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let mut scratch = held
  for body in bodies {
    guard program_artifact_parse_layout(body) is Some(parsed) &&
      @execution.compose_preparation_representation([held, parsed.value])
      is Some(next) &&
      compilation_writer_ancestry_layout(body.1, body.2, body.1, 1, 1, body.0)
      is Some(writer) &&
      compilation_canonical_emitter_layout(body.2) is Some(emitter) &&
      @execution.compose_preparation_representation([writer, emitter])
      is Some(active) else {
      return None
    }
    held = next
    scratch = compilation_scratch_max(
      scratch,
      compilation_scratch_max(parsed.temporary, active),
    )
  }
  let mut text = labels
  for wire in wires {
    guard @execution.checked_preparation_add_product(
        text,
        wire.0.to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
  }
  guard @execution.compose_preparation_representation([
      held,
      scratch,
      {
        record_headers: 3L * wires.length().to_int64(),
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: text,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(peak) else {
    return None
  }
  @execution.preparation_representation_cost(peak)
}

///|
// The selected Node preparation borrows the SAME initial checked Definition
// through the existing publication-control view before compiled/Plan binding.
// Four records coexist: admission view H1R1, contract view H1R4, three bound
// scalars H1W3, return pair H1R2; three existing WeakMap entries each H1R3W1.
// One more existing per-handle compiler-thunk reference carries that checked
// tuple from admission to the winning start claim; it is deleted on transfer.
// Wire/name/CID strings remain borrowed; no parser or new admission is funded.
fn keyed_initial_definition_view_representation() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 7L,
    reference_slots: 17L,
    scalar_words: 6L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

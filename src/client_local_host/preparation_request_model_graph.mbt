///|
// Select the original capacity family before the same measured constructor.
// This is neither another Resource owner nor an Effect-free Program view.
fn[I] reserve_request_model_graph_construction(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : ClientLocalSequenceOwner,
  bytes : Int64,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  match prepared {
    Pure(original) =>
      reserve_request_domain_graph_construction(owner, input, original, bytes)
    Effect(original) => {
      guard bytes >= 0L &&
        owner.phase == Selecting &&
        owner.input is Some(selected) &&
        physical_equal(selected, input) &&
        owner.compiled_effect is Some(body) &&
        physical_equal(body, original) &&
        owner.effect_capacity is Some(capacity) else {
        return Err(Preparation(ForeignOriginal))
      }
      let (r, e) = match
        @resources.preparation_capacity_working_extents(capacity, input) {
        Err(issue) => return Err(Preparation(Capacity(issue)))
        Ok(value) => value
      }
      guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
        @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
        return Err(Preparation(Policy))
      }
      owner.program_domain_quote = Some((r, e))
      let result = @resources.reserve_working_preparation_phase(
        capacity, input, r, e,
      )
      guard owner.phase == Selecting &&
        owner.input is Some(selected) &&
        physical_equal(selected, input) &&
        owner.compiled_effect is Some(body) &&
        physical_equal(body, original) &&
        owner.effect_capacity is Some(selected_capacity) &&
        physical_equal(selected_capacity, capacity) &&
        owner.program_domain_quote == Some((r, e)) else {
        return Err(Preparation(ForeignOriginal))
      }
      result.map_err(issue => Preparation(Capacity(issue)))
    }
  }
}

///|
/// Fund the selected single Model Graph on its SAME Request before
/// request/prefix/barrier/suffix/Result construction. Original compiled input
/// and provider/execution originals remain separate; this grants no Model I/O.
/// Module/provider/Scope/output/failed-child backing is not inferred from the
/// Graph debit, and no independent Root or compiler is created.
pub fn[I] prepare_request_model_graph(
  owner : ClientRequestPreparation[I],
  input : I,
  occurrence : @publication_host.ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  serialization? : @publication_host.ClientSerializationPlanGraph? = None,
) -> Result[
  @publication_host.ClientInferPlanGraph,
  ClientRequestProgramPlanIssue,
] {
  let prepared : ClientLocalSequenceOwner = match owner.phase {
    ModelPlanReserved => {
      guard owner.compiled_program is Some(prepared) &&
        owner.program_capacity is Some(_) &&
        @publication_host.client_infer_occurrence_matches(occurrence, prepared) else {
        return Err(Preparation(ForeignOriginal))
      }
      Pure(prepared)
    }
    EffectPlanReserved => {
      guard owner.compiled_effect is Some(prepared) &&
        owner.effect_capacity is Some(_) &&
        owner.effect_plan is None &&
        @publication_host.client_infer_occurrence_matches_effect(
          occurrence, prepared,
        ) else {
        return Err(Preparation(ForeignOriginal))
      }
      Effect(prepared)
    }
    _ => return Err(Preparation(ForeignOriginal))
  }
  let original_phase = owner.phase
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_quote is None &&
    owner.program_compilation is None &&
    owner.program_model is None &&
    !owner.program_body_attempted else {
    return Err(Preparation(ForeignOriginal))
  }
  // Keep earlier original graphs alive across this constructor/current and
  // its failure path. The existing Request debit is never replaced or reset.
  let previous = owner.program_domain_compilation_inputs
  let prior_count = match previous {
    Some(RequestModelGraph(_, _, _, _)) => 1
    Some(RequestModelGraphs(_, _, _, graphs)) => graphs.length()
    _ => 0
  }
  let multi = match prepared {
    Pure(original) =>
      @publication_host.prepared_client_composed_infer_occurrences(original)
    Effect(original) =>
      @publication_host.prepared_client_effect_infer_occurrences(original)
  }
  if multi is Some(occurrences) && occurrences.length() > 1 {
    guard prior_count < occurrences.length() &&
      @publication_host.client_infer_occurrence_coordinates(occurrence) ==
      @publication_host.client_infer_occurrence_coordinates(
        occurrences[prior_count],
      ) else {
      return Err(Preparation(ForeignOriginal))
    }
  }
  match (serialization, owner.program_domain_compilation_inputs) {
    (None, None) =>
      // The same original occurrence selects this construction profile before
      // its Graph exists. It grants no acquisition, Model read or adoption.
      match prepared {
        Pure(original) =>
          if !installed_managed_owner_shape_supported(
              prepared,
              true,
              model_occurrence=Some(occurrence),
              model_occurrences=match multi {
                Some(occurrences) =>
                  if occurrences.length() > 1 {
                    Some(occurrences)
                  } else {
                    None
                  }
                None => None
              },
            ) ||
            !@publication_host.prepared_client_serialization_occurrences(
              original,
            ).is_empty() {
            return Err(Installed(Unsupported))
          }
        Effect(original) =>
          // A Content component must first be retained by its existing owner.
          // An unselected serialized prefix cannot be reconstructed here.
          if !@publication_host.prepared_client_effect_serialization_occurrences(
              original,
            ).is_empty() {
            return Err(Installed(Unsupported))
          }
      }
    (
      None,
      Some(
        RequestModelGraph(old_manifests, old_limits, old_contracts, original)
      ),
    ) => {
      guard multi is Some(occurrences) &&
        occurrences.length() > 1 &&
        physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) &&
        @publication_host.client_infer_occurrence_coordinates(
          original.occurrence,
        ) ==
        @publication_host.client_infer_occurrence_coordinates(occurrences[0]) else {
        return Err(Preparation(ForeignOriginal))
      }
    }
    (
      None,
      Some(
        RequestModelGraphs(old_manifests, old_limits, old_contracts, originals)
      ),
    ) => {
      guard multi is Some(occurrences) &&
        originals.length() < occurrences.length() &&
        physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) else {
        return Err(Preparation(ForeignOriginal))
      }
    }
    (
      Some(component),
      Some(
        RequestSerializationGraph(
          old_manifests,
          old_limits,
          old_contracts,
          original_component
        )
      ),
    ) => {
      guard physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) &&
        physical_equal(original_component, component) &&
        (match prepared {
          Pure(original) => physical_equal(component.owner, original)
          Effect(original) =>
            @publication_host.client_infer_occurrence_matches_effect(
              occurrence, original,
            ) &&
            physical_equal(component.owner, occurrence.owner)
        }) &&
        component.task ==
        @publication_host.client_infer_occurrence_coordinates(occurrence).1 &&
        component.step <
        @publication_host.client_infer_occurrence_coordinates(occurrence).2 else {
        return Err(Preparation(ForeignOriginal))
      }
    }
    _ => return Err(Preparation(ForeignOriginal))
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      guard @publication_host.prepared_client_infer_graph_measurement_storage(
          occurrence,
          serialization~,
        )
        is Some(storage) &&
        @execution.preparation_representation_cost(storage)
        is Some(storage_bytes) &&
        owner.program_data is Some(data) &&
        program_check_data_extent_cost(data) is Some(variable_data) &&
        @publication_host.client_infer_occurrence_output_step(occurrence)
        is Some(terminal) else {
        return Err(Preparation(Policy))
      }
      let step = @publication_host.client_infer_occurrence_coordinates(
          occurrence,
        ).2
      if terminal < step {
        return Err(Preparation(Policy))
      }
      // One real Infer-input preparation and one real prefix/suffix lowering
      // per selected Fragment. Reuse the SAME compiler/Plan variable-data
      // envelope already owned by this Request, with the actual call count.
      // These products coexist until issuance, including a refused current.
      // No codec maximum, JS estimate, second policy or new tariff is used.
      let calls = match serialization {
        None => 2L + (terminal - step).to_int64()
        Some(component) => {
          if component.step >= step {
            return Err(Preparation(Policy))
          }
          // One mapping preparation plus each actual Content consumer and
          // post-Infer Fragment. The component's own lowering is already held
          // by this SAME Request and is not constructed or priced again.
          (terminal - component.step).to_int64()
        }
      }
      guard @execution.checked_preparation_add_product(
          storage_bytes, variable_data, calls,
        )
        is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      let bytes = if multi is Some(occurrences) && occurrences.length() > 1 {
        // New immutable graph vector plus its old/new backing. The same
        // shared Array inventory covers actual append/copy overlap, not a
        // manually guessed Model budget or a second graph/compiler quote.
        guard @execution.preparation_representation_cost(
            closed_values_program_arrays(1L, (prior_count + 1).to_int64(), true),
          )
          is Some(vector_bytes) &&
          @execution.checked_preparation_add_product(bytes, vector_bytes, 1L)
          is Some(total) else {
          return Err(Preparation(Policy))
        }
        total
      } else {
        bytes
      }
      match
        reserve_request_model_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let geometry = match
        @publication_host.measure_installed_client_composed_infer_graph_construction(
          occurrence,
          execution,
          client_local_owner_sequence_limits(prepared),
          100000,
          10000,
          100,
          serialization~,
        ) {
        Err(issue) => return Err(ModelGraph(issue))
        Ok(value) => value
      }
      // The existing four-reference Request slot retains the original lowered
      // inputs before the next reservation/current/issuer can fail.
      owner.program_domain_compilation_inputs = Some(
        RequestModelGraphConstruction(
          manifests, compilation_limits, contracts, geometry,
        ),
      )
      guard model_graph_construction_cost(geometry) is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_model_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard owner.program_domain_compilation_inputs
        is Some(
          RequestModelGraphConstruction(
            original_manifests,
            original_limits,
            original_contracts,
            original
          )
        ) &&
        physical_equal(original_manifests, manifests) &&
        original_limits == compilation_limits &&
        physical_equal(original_contracts, contracts) &&
        physical_equal(original, geometry) else {
        return Err(Preparation(ForeignOriginal))
      }
      let issued = match serialization {
        None =>
          @publication_host.issue_installed_client_composed_infer_plan_graph(
            occurrence,
            execution,
            client_local_owner_sequence_limits(prepared),
            100000,
            10000,
            100,
            construction=Some(original),
          )
        Some(component) =>
          @publication_host.issue_prepared_client_serialized_infer_plan_graph(
            occurrence,
            component,
            execution,
            client_local_owner_sequence_limits(prepared),
            100000,
            10000,
            100,
            include_results=false,
            construction=Some(original),
          )
      }
      let graph = match issued {
        Err(issue) => return Err(ModelGraph(issue))
        Ok(value) => value
      }
      owner.program_domain_compilation_inputs = Some(
        if multi is Some(occurrences) && occurrences.length() > 1 {
          let graphs = match previous {
            Some(RequestModelGraph(_, _, _, original)) => [original, graph]
            Some(RequestModelGraphs(_, _, _, originals)) => {
              let graphs = originals.copy()
              graphs.push(graph)
              graphs
            }
            _ => [graph]
          }
          RequestModelGraphs(manifests, compilation_limits, contracts, graphs)
        } else {
          RequestModelGraph(manifests, compilation_limits, contracts, graph)
        },
      )
      owner.program_domain_quote = None
      owner.phase = original_phase
      Ok(graph)
    },
    () => {
      if owner.phase == Selecting {
        owner.phase = if original_phase == EffectPlanReserved {
          EffectBodyFailed
        } else {
          ProgramBodyFailed
        }
      }
    },
  )
}

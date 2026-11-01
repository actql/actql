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
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    @publication_host.client_infer_occurrence_matches(occurrence, prepared) &&
    owner.program_capacity is Some(_) &&
    owner.program_domain_quote is None &&
    owner.program_compilation is None &&
    owner.program_model is None &&
    !owner.program_body_attempted else {
    return Err(Preparation(ForeignOriginal))
  }
  match (serialization, owner.program_domain_compilation_inputs) {
    (None, None) =>
      // The same original occurrence selects this construction profile before
      // its Graph exists. It grants no acquisition, Model read or adoption.
      if !installed_managed_owner_shape_supported(
          Pure(prepared),
          true,
          model_occurrence=Some(occurrence),
        ) ||
        !@publication_host.prepared_client_serialization_occurrences(prepared).is_empty() {
        return Err(Installed(Unsupported))
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
        physical_equal(component.owner, prepared) &&
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
      match
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let geometry = match
        @publication_host.measure_installed_client_composed_infer_graph_construction(
          occurrence,
          execution,
          @publication_host.prepared_client_values_sequence_limits(prepared),
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
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
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
            @publication_host.prepared_client_values_sequence_limits(prepared),
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
            @publication_host.prepared_client_values_sequence_limits(prepared),
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
        RequestModelGraph(manifests, compilation_limits, contracts, graph),
      )
      owner.program_domain_quote = None
      owner.phase = ModelPlanReserved
      Ok(graph)
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
/// Fund the existing selected Mock Model Graph on its SAME Request before
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
    owner.program_domain_compilation_inputs is None &&
    owner.program_domain_quote is None &&
    owner.program_compilation is None &&
    owner.program_model is None &&
    !owner.program_body_attempted else {
    return Err(Preparation(ForeignOriginal))
  }
  // Preserve the actual existing Mock entrance's purpose. A serialized or
  // different provider profile cannot borrow this constructor's backing.
  if !installed_managed_run_shape_supported(prepared, true) ||
    !@publication_host.prepared_client_serialization_occurrences(prepared).is_empty() {
    return Err(Installed(Unsupported))
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      guard @publication_host.prepared_client_infer_graph_measurement_storage(
          occurrence,
        )
        is Some(storage) &&
        @execution.preparation_representation_cost(storage) is Some(bytes) else {
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
        ) {
        Err(issue) => return Err(ModelGraph(issue))
        Ok(value) => value
      }
      guard model_graph_construction_cost(geometry) is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let graph = match
        @publication_host.issue_installed_client_composed_infer_plan_graph(
          occurrence,
          execution,
          @publication_host.prepared_client_values_sequence_limits(prepared),
          100000,
          10000,
          100,
        ) {
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

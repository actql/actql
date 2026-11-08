///|
// Per-invocation selection retained by the existing command, not another
// Model, Resource or cleanup owner. The provider and profile are the original
// admitted Project objects; the Limits are selected once from this Graph.
priv struct LocalProjectMockEffectModelInput {
  graph : @run_host.ClientInferPlanGraph
  _retained_provider : @model.ModelProvider
  _retained_profile : @compiler_environment.ModelMockProfile
  _retained_limits : @infer.Limits
}

///|
// The metadata Read retains the selected original execution contract. The
// SAME Request funds and retains every measured Graph before the first Task
// compiler consumes it. No Model call, resource grant or new input is issued.
fn[I] LocalProjectMockDeclarations::prepare_effect_models(
  self : Self,
  parent : @local_values.ClientRequestPreparation[I],
  input : I,
  prepared : @run_host.PreparedClientEffectComputation,
  environment : @checked.CheckEnvironment,
  contracts : @local_values.ClientInstalledSequenceContracts,
) -> Array[LocalProjectMockEffectModelInput] raise ClientStop {
  guard !self.closing &&
    !self.retired &&
    self.model_environment is Some((_, original_environment)) &&
    physical_equal(original_environment, environment) &&
    self.model_profile is Some(profile) &&
    @run_host.prepared_client_effect_infer_occurrences(prepared)
    is Some(occurrences) else {
    stop("LocalOriginalModelUnavailable")
  }
  let models = []
  for occurrence in occurrences {
    let mut selected : LocalProjectMockModelOriginal? = None
    for entry in self.models {
      if entry.execution is Some(execution) &&
        @run_host.client_infer_occurrence_model_task_cid(occurrence) ==
        Some(
          @compiler_environment.model_task_identity(
            @compiler_environment.model_execution_task(execution),
          ).2,
        ) {
        guard selected is None else { stop("LocalOriginalModelUnavailable") }
        selected = Some(entry)
      }
    }
    let selected = selected.unwrap_or_else(() => {
      stop("LocalOriginalModelUnavailable")
    })
    guard selected.execution is Some(execution) &&
      selected.normalized is Some(normalized) &&
      selected.installation is Some(_) &&
      @compiler_environment.model_mock_execution_matches(
        profile, normalized, execution,
      ) else {
      stop("LocalOriginalModelUnavailable")
    }
    let provider = self
      .model_provider(execution)
      .unwrap_or_else(() => stop("LocalOriginalModelUnavailable"))
    let graph = @local_values.prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      contracts,
      manifests=native_request_manifests,
      compilation_limits=@run_host.client_standard_pure_compilation_limits(),
    ).unwrap_or_else(() => stop("LocalOriginalModelGraphUnavailable"))
    let limits = @infer.prepared_composed_bounds(occurrence, graph).unwrap_or_else(() => {
        stop("LocalOriginalModelBoundsUnavailable")
      },
    )
    models.push({
      graph,
      _retained_provider: provider,
      _retained_profile: profile,
      _retained_limits: limits,
    })
  }
  models
}

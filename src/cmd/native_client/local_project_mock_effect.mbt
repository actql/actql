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
  occurrences : Array[@run_host.ClientInferOccurrence],
  environment : @checked.CheckEnvironment,
  contracts : @local_values.ClientInstalledSequenceContracts,
) -> Array[LocalProjectMockEffectModelInput] raise ClientStop {
  guard !self.closing &&
    !self.retired &&
    self.model_environment is Some((_, original_environment)) &&
    physical_equal(original_environment, environment) &&
    self.model_profile is Some(profile) else {
    stop("LocalOriginalModelUnavailable")
  }
  let models = []
  for index, occurrence in occurrences {
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
    let keyed_native_profile = match
      @run_host.client_infer_occurrence_keyed_source_identity(occurrence) {
      None => None
      Some((source_ref, view_cid)) => {
        guard self.file_sources is Some(files) else {
          stop("LocalOriginalModelKeyedPlanUnavailable")
        }
        let mut selected = None
        for file in files {
          for pair in file._retained_listings {
            let binding = pair.1
            if binding.content.source_ref == source_ref &&
              binding.content.view_cid == view_cid {
              guard selected is None else {
                stop("LocalOriginalModelKeyedPlanUnavailable")
              }
              selected = Some(binding._retained_read_profile.contract())
            }
          }
        }
        guard selected is Some(profile) else {
          stop("LocalOriginalModelKeyedPlanUnavailable")
        }
        Some(profile)
      }
    }
    let graph = @local_values.prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      contracts,
      manifests=native_request_manifests,
      compilation_limits=@run_host.client_standard_pure_compilation_limits(),
      keyed_native_profile~,
      caller_material=Some(
        native_mock_effect_model_selection_storage(
          if index == 0 {
            occurrences.length()
          } else {
            0
          },
        ),
      ),
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

///|
// Same domain inventories, before their actual constructors. Each selected
// provider/profile/Graph is borrowed; the new holder owns four references.
// The first occurrence also backs selection, Graph projection and Native Work
// Arrays with their actual checked count. Every later occurrence adds only its
// own bounds and holder; prior debits survive all failures and parent cleanup.
fn native_mock_effect_model_selection_storage(
  vector_count : Int,
) -> @execution.PreparationRepresentationUnits raise ClientStop {
  let holder : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 4L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let arrays = @execution.preparation_array_representation(
    if vector_count > 0 {
      3L
    } else {
      0L
    },
    3L * vector_count.to_int64(),
    true,
  ).unwrap_or_else(() => stop("LocalOriginalModelBoundsUnavailable"))
  // One actual ClientCompiledRun record, Effects/Result/Some wrappers, and
  // their slots. This view is created once after the first compiler and kept
  // for all original Model children; no Run/admission or payload is copied.
  let compiled_view : @execution.PreparationRepresentationUnits = {
    record_headers: if vector_count > 0 {
      4L
    } else {
      0L
    },
    reference_slots: if vector_count > 0 {
      12L
    } else {
      0L
    },
    scalar_words: if vector_count > 0 {
      3L
    } else {
      0L
    },
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  @execution.compose_preparation_representation([
    compiled_view,
    @infer.prepared_composed_bounds_construction(),
    @local_host.native_client_mock_model_work_construction(),
    holder,
    arrays,
  ]).unwrap_or_else(() => stop("LocalOriginalModelBoundsUnavailable"))
}

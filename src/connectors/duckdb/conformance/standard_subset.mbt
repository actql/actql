///|
/// Fixture setup only; the standard generated bridge and installed modules own
/// every execution operation. No unused Compute provider configuration is built.
#export_name("strategyFixtureModuleSubset")
pub fn strategy_fixture_module_subset(
  f : StrategyFixture,
  mode : Int,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let generated = Array::makei(@strategy.graph_task_count(f.graph) - 1, i => {
    fixture_generated_with_ordered(
      @strategy.graph_task_owner(f.graph, i + 1).unwrap(),
      f.registry_json,
      f.values_json,
      f.fragment_json,
      true,
      f.ordered_json,
    ) catch {
      _ => abort("invalid fixture generation for task " + (i + 1).to_string())
    }
  })
  @connector_conformance.configure_subset(f.run.unwrap(), generated, mode)
}

///|
/// Explicit SGA-enabled conformance artifact. The ordinary module subset does
/// not import or install this family provider.
#export_name("strategyFixtureSgaSubset")
pub fn strategy_fixture_sga_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let generated = Array::makei(@strategy.graph_task_count(f.graph) - 1, i => {
    fixture_generated(
      @strategy.graph_task_owner(f.graph, i + 1).unwrap(),
      f.registry_json,
      f.values_json,
      f.fragment_json,
      true,
    ) catch {
      _ => abort("invalid SGA fixture generation")
    }
  })
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
      output_values: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
    },
    max_work: 100000,
    max_frames: 100,
  }
  let provider = @local_sga_provider.provider(
    {
      max_input_rows: 100,
      max_nodes: 100,
      max_edges: 100,
      max_value_bytes: 10000,
      max_total_value_bytes: 100000,
      max_retained_value_bytes: 100000,
      max_value_nodes: 10000,
      max_value_depth: 100,
      max_contract_work: 10000,
      max_work: 100000,
      max_workspace_slots: 10000,
    },
    100000L,
    @execution.generated_sequence_capacity(generated[1], execution, {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
  )
  if !@local_connector.managed_provider_accepts(provider, generated[1]) {
    abort("SGA fixture provider rejected its graph sequence")
  }
  @conformance.configure_subset(f.run.unwrap(), generated, 0, managed_providers=[
    provider,
  ])
}

///|
/// Explicit TEA-enabled conformance artifact. The ordinary module subset does
/// not import or install this family provider.
#export_name("strategyFixtureTeaSubset")
pub fn strategy_fixture_tea_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let generated = Array::makei(@strategy.graph_task_count(f.graph) - 1, i => {
    fixture_generated(
      @strategy.graph_task_owner(f.graph, i + 1).unwrap(),
      f.registry_json,
      f.values_json,
      f.fragment_json,
      true,
    ) catch {
      _ => abort("invalid TEA fixture generation")
    }
  })
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
      output_values: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
    },
    max_work: 100000,
    max_frames: 100,
  }
  let storage : @record_storage.Limits = {
    max_input_records: 100,
    max_records: 100,
    max_fields_per_record: 10,
    max_value_bytes: 10000,
    max_total_value_bytes: 100000,
    max_retained_value_bytes: 100000,
    max_value_nodes: 10000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
  let providers = []
  for sequence in generated {
    let capacity = @execution.generated_sequence_capacity(sequence, execution, {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap()
    let events = @local_tea_provider.provider(storage, 100000L, capacity)
    if @local_connector.managed_provider_accepts(events, sequence) {
      providers.push(events)
    }
    let time_series = @local_tea_provider.time_series_provider(
      storage, capacity,
    )
    if @local_connector.managed_provider_accepts(time_series, sequence) {
      providers.push(time_series)
    }
  }
  if providers.is_empty() {
    abort("TEA fixture providers rejected every generated sequence")
  }
  @conformance.configure_subset(
    f.run.unwrap(),
    generated,
    0,
    managed_providers=providers,
  )
}

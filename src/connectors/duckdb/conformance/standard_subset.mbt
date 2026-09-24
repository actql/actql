///|
fn fixture_max_capacity(
  generated : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
) -> @execution.ExecutionCapacity {
  let mut retained = 0L
  let mut active = 0L
  for sequence in generated {
    let capacity = @execution.generated_sequence_capacity(sequence, execution, {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap()
    retained = retained.max(
      @execution.execution_capacity_retained_bytes(capacity),
    )
    active = active.max(@execution.execution_capacity_execution_bytes(capacity))
  }
  @execution.execution_capacity(retained, active).unwrap()
}

///|
fn register_used_provider(
  providers : Array[@local_connector.ManagedProvider],
  provider : @local_connector.ManagedProvider,
  generated : Array[@execution.GeneratedSequence],
) -> Unit {
  for sequence in generated {
    if @local_connector.managed_provider_accepts(provider, sequence) {
      providers.push(provider)
      return
    }
  }
}

///|
fn fixture_task_sequences(
  graph : @strategy.CheckedDAG,
  generated : Array[@execution.GeneratedSequence],
) -> Array[@execution.GeneratedSequence] {
  Array::makei(generated.length(), index => {
    let task = index + 1
    match @strategy.graph_task_prefix_end(graph, task) {
      Some(end) =>
        @execution.select_generated_sequence_prefix(generated[index], end).unwrap()
      None =>
        match @strategy.graph_task_selected_step(graph, task) {
          Some(step) =>
            @execution.select_generated_sequence_step(generated[index], step).unwrap()
          None => generated[index]
        }
    }
  })
}

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
  @connector_gate.configure_subset(f.run.unwrap(), generated, mode)
}

///|
/// Explicit SGA-enabled conformance artifact. The ordinary module subset does
/// not import or install this family provider.
#export_name("strategyFixtureSgaSubset")
pub fn strategy_fixture_sga_subset(
  f : StrategyFixture,
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
  let task_sequences = fixture_task_sequences(f.graph, generated)
  let provider = @local_sga_provider.provider(
    {
      // The largest fixture has 100 declared nodes and 100 edge rows.
      max_input_rows: 200,
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
    fixture_max_capacity(task_sequences, execution),
  )
  if !@local_connector.managed_provider_accepts(provider, task_sequences[1]) {
    abort("SGA fixture provider rejected its graph sequence")
  }
  @connector_gate.configure_subset(f.run.unwrap(), generated, 0, managed_providers=[
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
  let task_sequences = fixture_task_sequences(f.graph, generated)
  let providers = []
  let capacity = fixture_max_capacity(task_sequences, execution)
  register_used_provider(
    providers,
    @local_tea_provider.provider(storage, 100000L, capacity),
    task_sequences,
  )
  register_used_provider(
    providers,
    @local_tea_provider.time_series_provider(storage, capacity),
    task_sequences,
  )
  register_used_provider(
    providers,
    @local_tea_provider.interval_join_provider(storage, capacity),
    task_sequences,
  )
  register_used_provider(
    providers,
    @local_tea_provider.asof_join_provider(storage, capacity),
    task_sequences,
  )
  register_used_provider(
    providers,
    @local_tea_provider.sequence_match_provider(storage, capacity),
    task_sequences,
  )
  if providers.is_empty() {
    abort("TEA fixture providers rejected every generated sequence")
  }
  @connector_gate.configure_subset(
    f.run.unwrap(),
    generated,
    0,
    managed_providers=providers,
  )
}

///|
/// Explicit VecA-enabled conformance artifact. The ordinary module subset does
/// not import or install this family provider.
#export_name("strategyFixtureVecaSubset")
pub fn strategy_fixture_veca_subset(
  f : StrategyFixture,
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
      _ => abort("invalid VecA fixture generation")
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
  let task_sequences = fixture_task_sequences(f.graph, generated)
  let providers = []
  let capacity = fixture_max_capacity(task_sequences, execution)
  register_used_provider(
    providers,
    @local_veca_provider.provider(storage, 100000L, capacity),
    task_sequences,
  )
  if providers.is_empty() {
    abort("VecA fixture provider rejected every generated sequence")
  }
  @connector_gate.configure_subset(
    f.run.unwrap(),
    generated,
    0,
    managed_providers=providers,
  )
}

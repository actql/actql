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
    for index in 0..<@execution.generated_sequence_step_count(sequence) {
      if @execution.generated_sequence_step_index_at(sequence, index)
        is Some(step) &&
        @execution.select_generated_sequence_step(sequence, step) is Some(child) &&
        @local_connector.managed_provider_accepts(provider, child) {
        providers.push(provider)
        return
      }
    }
  }
}

///|
fn fixture_task_sequences(
  graph : @strategy.CheckedDAG,
  generated : Array[@execution.GeneratedSequence],
  first_task? : Int = 1,
) -> Array[@execution.GeneratedSequence] {
  Array::makei(generated.length(), index => {
    let task = index + first_task
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
/// Reuse the checked source-free Program and the installed retained driver.
/// The fixture configures Compute only; the standard Host owns publication.
#export_name("strategyFixtureSourceFreeRetainedSubset")
pub fn strategy_fixture_source_free_retained_subset(
  prepared : @publication_host.PreparedClientProgram,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  execution_work : Int,
  operation_entries : Int,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let run = @publication_host.open_prepared_source_free_client_run(prepared, {
    planning_work: 100000,
    attempts: 100,
    holdings: 100,
    transfer_bytes: 10000000L,
    retained_bytes: 200000000L,
    execution_bytes: 268435456L,
  }).unwrap()
  fixture_retained_client_subset(
    run, registry_json, values_json, fragment_json, execution_work, operation_entries,
    0,
  )
}

///|
/// Bind budget injection to the same checked acquisition and retained owner.
#export_name("strategyFixtureCapturedRetainedSubset")
pub fn strategy_fixture_captured_retained_subset(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  execution_work : Int,
  operation_entries : Int,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let run = @publication_host.open_prepared_captured_client_run(
    prepared,
    source,
    {
      planning_work: 100000,
      attempts: 100,
      holdings: 100,
      transfer_bytes: 10000000L,
      retained_bytes: 200000000L,
      execution_bytes: 268435456L,
    },
  ).unwrap()
  fixture_retained_client_subset(
    run, registry_json, values_json, fragment_json, execution_work, operation_entries,
    1,
  )
}

///|
fn fixture_retained_client_subset(
  run : @strategy.CapturedDAG,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  execution_work : Int,
  operation_entries : Int,
  first_task : Int,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let graph = @strategy.captured_dag_graph(run)
  let generated = Array::makei(@strategy.graph_task_count(graph) - first_task, index => {
    let task = index + first_task
    fixture_generated_with_ordered(
      @strategy.graph_task_owner(graph, task).unwrap(),
      registry_json,
      values_json,
      fragment_json,
      true,
      None,
    ) catch {
      _ =>
        abort(
          "invalid retained fixture generation for task " + task.to_string(),
        )
    }
  })
  @connector_gate.configure_subset(
    run,
    fixture_task_sequences(graph, generated, first_task~),
    0,
    retained_output=true,
    execution_work~,
    operation_entries~,
  )
}

///|
/// Observe physical task boundaries without substituting a fixture DAG.
#export_name("strategyFixtureConfiguredTaskStepCount")
pub fn strategy_fixture_configured_task_step_count(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
) -> Int? {
  let graph = @strategy.captured_dag_graph(
    @physical_host.dispatch_driver_run(@builtin.configured_host_driver(setup)),
  )
  @strategy.graph_task_owner(graph, task).map(owner => {
    match @strategy.graph_task_selected_step(graph, task) {
      Some(_) => 1
      None =>
        match @strategy.graph_task_prefix_end(graph, task) {
          Some(end) => end + 1
          None =>
            @pipeline.step_count(
              @lower.pipeline(@lower.bound_preparation(owner)),
            )
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
/// Local-only subset with a configured retained Store output: every Local task
/// runs through the retained-output driver.
#export_name("strategyFixtureRetainedLocalSubset")
pub fn strategy_fixture_retained_local_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_retained_local_limits(f, 100000, 10000)
}

///|
/// Exercise the same installed retained driver with explicit kernel budgets.
#export_name("strategyFixtureRetainedLocalLimits")
pub fn strategy_fixture_retained_local_limits(
  f : StrategyFixture,
  execution_work : Int,
  operation_entries : Int,
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
  @connector_gate.configure_subset(
    f.run.unwrap(),
    generated,
    0,
    retained_output=true,
    execution_work~,
    operation_entries~,
  )
}

///|
/// Match the retained materializing driver's typed provider failure without
/// relying on compiler-specific JavaScript enum tags or constructor names.
#export_name("strategyFixtureRetainedRowLimit")
pub fn strategy_fixture_retained_row_limit(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  issue
  is @local_driver.Preparation(
    @local_connector.Materializing(
      @local_connector.Candidate(
        @connector.Execution(@execution.Rows(_, @execution.RowLimit))
      )
    )
  )
}

///|
/// Match the retained nest provider's per-parent item limit without relying
/// on JavaScript's representation of the typed failure.
#export_name("strategyFixtureRetainedNestItemLimit")
pub fn strategy_fixture_retained_nest_item_limit(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  issue
  is @local_driver.Preparation(
    @local_connector.Materializing(
      @local_connector.Candidate(
        @connector.Execution(@execution.Rows(_, @execution.NestItemLimit(_)))
      )
    )
  )
}

///|
#export_name("strategyFixtureRetainedInputLimit")
pub fn strategy_fixture_retained_input_limit(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  issue
  is @local_driver.Preparation(
    @local_connector.Materializing(
      @local_connector.Candidate(@connector.Execution(@execution.InputLimit))
    )
  )
}

///|
/// Identify the authored filter's division failure, not merely an arbitrary
/// managed task failure that happens before the retained output is published.
#export_name("strategyFixtureRetainedChainFilterArithmetic")
pub fn strategy_fixture_retained_chain_filter_arithmetic(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  retained_filter_arithmetic_at(issue, 1)
}

///|
/// The acquired producer begins with the filter, not a Values child.
#export_name("strategyFixtureRetainedCapturedFilterArithmetic")
pub fn strategy_fixture_retained_captured_filter_arithmetic(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  retained_filter_arithmetic_at(issue, 0)
}

///|
fn retained_filter_arithmetic_at(
  issue : @local_driver.LocalDispatchIssue,
  expected_step : Int,
) -> Bool {
  guard issue
    is @local_driver.Preparation(
      @local_connector.Materializing(
        @local_connector.Candidate(
          @connector.Execution(
            @execution.Rows(step, @execution.Evaluation(0, 0, evaluation))
          )
        )
      )
    ) &&
    step == expected_step &&
    evaluation.kind is @execution.Scalar(@execution.ArithmeticFailure) else {
    return false
  }
  let location = @lower.expression_location(evaluation.expression)
  guard @decode.text(location.source) is Ok("1 / (id - id) > 0") &&
    location.range is Some(range) else {
    return false
  }
  range.start == 0 && range.end == 13
}

///|
/// Match the selected filter after an Events construction and as-of step.
#export_name("strategyFixtureRetainedEventsAsOfArithmetic")
pub fn strategy_fixture_retained_events_asof_arithmetic(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  guard issue
    is @local_driver.Configuration(
      @connector.Execution(
        @execution.Rows(2, @execution.Evaluation(0, 0, evaluation))
      )
    ) &&
    evaluation.kind is @execution.Scalar(@execution.ArithmeticFailure) else {
    return false
  }
  let location = @lower.expression_location(evaluation.expression)
  guard @decode.text(location.source) is Ok("1 / (id - id) > 0") &&
    location.range is Some(range) else {
    return false
  }
  range.start == 0 && range.end == 13
}

///|
/// Count the physical task, not all steps retained by its source owner.
#export_name("strategyFixtureTaskStepCount")
pub fn strategy_fixture_task_step_count(
  f : StrategyFixture,
  task : Int,
) -> Int? {
  @strategy.graph_task_owner(f.graph, task).map(owner => {
    match @strategy.graph_task_selected_step(f.graph, task) {
      Some(_) => 1
      None =>
        match @strategy.graph_task_prefix_end(f.graph, task) {
          Some(end) => end + 1
          None =>
            @pipeline.step_count(
              @lower.pipeline(@lower.bound_preparation(owner)),
            )
        }
    }
  })
}

///|
/// Explicit SGA-enabled conformance artifact. The ordinary module subset does
/// not import or install this family provider.
fn strategy_fixture_sga_subset_with_retention(
  f : StrategyFixture,
  retained_output : Bool,
  max_graph_nodes? : Int = 100,
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
      max_nodes: max_graph_nodes,
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
  let mut graph_sequence_found = false
  for sequence in task_sequences {
    if @local_connector.managed_provider_accepts(provider, sequence) {
      graph_sequence_found = true
      break
    }
  }
  if !graph_sequence_found {
    abort("SGA fixture provider rejected its graph sequence")
  }
  @connector_gate.configure_subset(
    f.run.unwrap(),
    generated,
    0,
    managed_providers=[provider],
    retained_output~,
  )
}

///|
#export_name("strategyFixtureSgaSubset")
pub fn strategy_fixture_sga_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_sga_subset_with_retention(f, false)
}

///|
/// Retained row output is configured without changing the SGA provider set.
#export_name("strategyFixtureSgaRetainedSubset")
pub fn strategy_fixture_sga_retained_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_sga_subset_with_retention(f, true)
}

///|
#export_name("strategyFixtureSgaRetainedNodeLimit")
pub fn strategy_fixture_sga_retained_node_limit(
  f : StrategyFixture,
  max_graph_nodes : Int,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_sga_subset_with_retention(f, true, max_graph_nodes~)
}

///|
/// The SGA provider reports its bounded construction failure through the
/// managed dispatch channel before a Carrier completion exists.
#export_name("strategyFixtureSgaConstructionLimitFailure")
pub fn strategy_fixture_sga_construction_limit_failure(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  issue
  is @local_driver.Configuration(@connector.Execution(@execution.InputSet))
}

///|
#export_name("strategyFixtureSgaConsumerFilterArithmetic")
pub fn strategy_fixture_sga_consumer_filter_arithmetic(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  guard issue
    is @local_driver.Configuration(
      @connector.Execution(
        @execution.Rows(0, @execution.Evaluation(0, 0, evaluation))
      )
    ) &&
    evaluation.kind is @execution.Scalar(@execution.ArithmeticFailure) else {
    return false
  }
  let location = @lower.expression_location(evaluation.expression)
  guard @decode.text(location.source) is Ok("1 / (id - id) > 0") &&
    location.range is Some(range) else {
    return false
  }
  range.start == 0 && range.end == 13
}

///|
#export_name("strategyFixtureVecaConsumerFilterArithmetic")
pub fn strategy_fixture_veca_consumer_filter_arithmetic(
  issue : @local_driver.LocalDispatchIssue,
) -> Bool {
  guard issue
    is @local_driver.Configuration(
      @connector.Execution(
        @execution.Rows(0, @execution.Evaluation(0, 0, evaluation))
      )
    ) &&
    evaluation.kind is @execution.Scalar(@execution.ArithmeticFailure) else {
    return false
  }
  let location = @lower.expression_location(evaluation.expression)
  guard @decode.text(location.source)
    is Ok("1 / (candidate_id - candidate_id) > 0") &&
    location.range is Some(range) else {
    return false
  }
  range.start == 0 && range.end == 33
}

///|
/// Explicit TEA-enabled conformance artifact. The ordinary module subset does
/// not import or install this family provider.
fn strategy_fixture_tea_subset_with_retention(
  f : StrategyFixture,
  retained_output : Bool,
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
    retained_output~,
  )
}

///|
#export_name("strategyFixtureTeaSubset")
pub fn strategy_fixture_tea_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_tea_subset_with_retention(f, false)
}

///|
#export_name("strategyFixtureTeaRetainedSubset")
pub fn strategy_fixture_tea_retained_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_tea_subset_with_retention(f, true)
}

///|
/// Explicit VecA-enabled conformance artifact. The ordinary module subset does
/// not import or install this family provider.
fn strategy_fixture_veca_subset_with_retention(
  f : StrategyFixture,
  retained_output : Bool,
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
    retained_output~,
  )
}

///|
#export_name("strategyFixtureVecaSubset")
pub fn strategy_fixture_veca_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_veca_subset_with_retention(f, false)
}

///|
#export_name("strategyFixtureVecaRetainedSubset")
pub fn strategy_fixture_veca_retained_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_veca_subset_with_retention(f, true)
}

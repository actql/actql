///|
fn captured_requirements_branch() -> @publication_host.PreparedClientProgram {
  single_installed_prepared(
    document=(
      #|{"version":"actql/0.1","id":"captured-branch-capacity","stages":[{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","filter":"id > 0"},{"select":["id"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"records","filter":"id > 1"},{"select":["id"],"as":"selected"},{"from":"records","select":["id"],"as":"complete"},{"from":"complete","group":{"by":[],"aggregates":{"id":{"fn":"count"}}},"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
}

///|
test "captured requirements quote the simultaneous original suffix without changing maxima" {
  let prepared = captured_tasks_prepared()
  let requirements = captured_tasks_requirements(prepared).unwrap()
  let quoted = requirements.simultaneous_limits().unwrap()
  let maximum = requirements.maximum_limits()
  assert_eq(maximum.retained_bytes, 200000000L)
  assert_eq(maximum.execution_bytes, 536870912L)
  assert_true(quoted.retained_bytes > 0L)
  assert_true(quoted.execution_bytes >= quoted.retained_bytes)
  assert_eq(quoted.attempts, maximum.attempts)
  assert_eq(quoted.holdings, maximum.holdings)
  assert_eq(quoted.transfer_bytes, maximum.transfer_bytes)
  // Source acquisition and transport are separately composed by this nominal
  // test owner. The Common quote never supplies their physical backing.
  let value = captured_tasks_fixture(original=Some(prepared), simultaneous=true)
  let before = @resources.ledger_usage(value.ledger)
  let execution = execute_captured_local_tasks_guarded(
    value.setup,
    value.capture,
    value.requirements,
    64,
    100000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":2}"])
  assert_true(execution.close())
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  captured_tasks_close_source(value)
}

///|
test "captured simultaneous quote selects original step occurrences after the Source offset" {
  let prepared = captured_requirements_branch()
  let requirements = captured_tasks_requirements(prepared).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(@strategy.graph_task_count(graph), 5)
  let plan = requirements.capacity_plan
  assert_eq(plan.graph_offset, 1)
  assert_eq(plan.sequences.length(), 4)
  let imported = @local.local_import_retention_capacity(plan.imports).unwrap()
  let exported = @local.local_export_retention_capacity(plan.exports).unwrap()
  let mut retained = 0L
  let mut executing = 0L
  // This independent branch has four distinct selected steps, including a
  // different final count provider, and one input per task. Task zero is the captured Source, never a Compute provider.
  for step in 0..<4 {
    assert_eq(@strategy.graph_task_selected_step(graph, step + 1), Some(step))
    assert_eq(@strategy.graph_task_input_count(graph, step + 1), Some(1))
    let selected = @execution.select_generated_sequence_step(
      plan.sequences[step],
      step,
    ).unwrap()
    let provider = @local.local_bounded_relation_provider(
      plan.execution,
      plan.measurement,
      selected,
    ).unwrap()
    let capacity = @local.managed_provider_capacity(provider, selected).unwrap()
    let task_retained = @execution.execution_capacity_retained_bytes(capacity) +
      plan.metadata_retained_bytes +
      imported +
      exported
    retained += task_retained
    executing += task_retained +
      @execution.execution_capacity_execution_bytes(capacity)
  }
  let quoted = requirements.simultaneous_limits().unwrap()
  assert_eq(quoted.retained_bytes, retained)
  assert_eq(quoted.execution_bytes, executing)
  let value = captured_tasks_fixture(original=Some(prepared), simultaneous=true)
  let execution = execute_captured_local_tasks_guarded(
    value.setup,
    value.capture,
    value.requirements,
    64,
    100000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":3}"])
  assert_true(execution.close())
  captured_tasks_close_source(value)
}

///|
test "simultaneous capacity refuses a same-byte foreign graph selector" {
  let prepared = captured_tasks_prepared()
  let requirements = captured_tasks_requirements(prepared).unwrap()
  let foreign = @publication_host.prepared_client_graph(
    captured_tasks_prepared(),
  )
  assert_true(
    client_local_sequence_capacity_original(
      requirements.capacity_plan.sequences,
      3,
      capacity_plan=Some(requirements.capacity_plan),
      retained_inputs=Some([1, 1]),
      max_rows=@publication_host.prepared_client_values_max_rows(prepared),
      include_simultaneous=true,
      simultaneous_graph=Some(foreign),
    )
    is None,
  )
}

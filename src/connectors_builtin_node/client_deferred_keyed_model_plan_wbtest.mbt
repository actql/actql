///|
// Static authored constructor inputs from the existing declared-project keyed
// graph fixture. No rows, answers, live installation, Run or Ledger is loaded.
extern "js" fn deferred_keyed_model_input(index : Int) -> String =
  #|(index) => { const fs = process.getBuiltinModule('node:fs'); const data = JSON.parse(fs.readFileSync(process.cwd() + '/src/connectors_builtin_node/fixtures/readme-deferred-keyed-input.json', 'utf8')); return [data.environmentWire, data.publicationWire, data.source, data.task, JSON.parse(data.environmentWire).evidence_bundle_cid][index]; }

///|
// Negative-only mutations of actual checked originals. They cannot issue a
// Source proof or physical producer; the planned predicate must reject them.
extern "js" fn deferred_keyed_missing_edge(
  graph : @strategy.CheckedDAG,
) -> @strategy.CheckedDAG =
  #|(graph) => ({...graph, data: graph.data.slice(1)})

///|
extern "js" fn deferred_keyed_foreign_program(
  graph : @strategy.CheckedDAG,
  foreign : @strategy.CheckedDAG,
) -> @strategy.CheckedDAG =
  #|(graph, foreign) => ({...graph, program: foreign.program})

///|
fn deferred_keyed_model_fixture() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientInferOccurrence,
  @publication_host.ClientInferPlanGraph,
) raise {
  let wire = deferred_keyed_model_input(0)
  let environment = client_program_check_environment(
    wire,
    deferred_keyed_model_input(4),
    false,
    false,
    true,
    false,
    false,
    false,
    false,
  ).unwrap()
  let outcome = client_program_prepare_source_computation_with_parameters(
    deferred_keyed_model_input(2),
    "sql",
    environment,
    deferred_keyed_model_input(1),
    None,
    None,
    true,
    [],
  )
  let effect = client_program_source_computation_effect(outcome).unwrap()
  let owner = client_program_effect_preparation_ready(effect).unwrap()
  let occurrence = client_program_effect_infer_occurrence(owner).unwrap()
  let bounds = (65536, 4096, 64, 256, 4096, 64, 65536, 2097152)
  let profile = client_program_install_mock_profile(
    bounds.0,
    bounds.1,
    bounds.2,
    bounds.3,
    bounds.4,
    bounds.5,
    bounds.6,
    bounds.7,
  ).unwrap()
  let task = client_program_read_public_model_task(
    deferred_keyed_model_input(3),
    "yaml",
    bounds.0,
    bounds.1,
    bounds.2,
    bounds.3,
    bounds.4,
    bounds.5,
    bounds.6,
    bounds.7,
  ).unwrap()
  let normalized = client_program_normalize_mock_task(
    task,
    profile,
    bounds.0,
    bounds.1,
    bounds.2,
    bounds.3,
    bounds.4,
    bounds.5,
    bounds.6,
    bounds.7,
  ).unwrap()
  let material = client_program_mock_execution_materials(
    profile,
    normalized,
    bounds.0,
    bounds.1,
    bounds.2,
    bounds.3,
    bounds.4,
    bounds.5,
    bounds.6,
    bounds.7,
  ).unwrap()
  let execution = client_program_read_composed_infer_model_execution(
    occurrence,
    material.0,
    material.1,
  ).unwrap()
  let component = client_program_installed_composed_infer_plan_graph(
    occurrence, execution,
  ).unwrap()
  assert_true(client_program_retire_mock_profile(profile))
  (owner, occurrence, component)
}

///|
test "README deferred keyed producer completes a Model plan without claiming live Source input" {
  let (owner, occurrence, component) = deferred_keyed_model_fixture()
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(owner),
  )
  let (task, stage, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  assert_eq((task, stage, step), (2, 2, 5))
  assert_eq(@strategy.graph_captured_prefix(graph), 2)
  let slots = graph.supplied_slots_count()
  assert_false(@strategy.graph_ordered_inputs_complete(graph))
  let lookup = client_program_effect_prepare_keyed_acquisition(
    owner,
    stage,
    0,
    Some(1),
  ).unwrap()
  let coordinates = client_program_keyed_acquisition_input_coordinates(lookup).unwrap()
  let bound = @lower.bound_preparation(
    @strategy.graph_task_owner(graph, task).unwrap(),
  )
  let join = @lower.node_at(bound, coordinates[3]).unwrap()
  let binding = @publication_host.client_keyed_acquisition_binding(lookup)
  let subject = @program_check.source_execution_subject(
    @publication_host.client_keyed_acquisition_check(lookup),
  )
  assert_true(
    @strategy.graph_keyed_model_plan_inputs_complete(graph, task, step),
    msg="original keyed port: inputs=" +
      @lower.node_input_count(join).to_string() +
      ", left=" +
      @debug.to_string(@lower.node_input_target(join, 0)) +
      ", right=" +
      @debug.to_string(@lower.node_input_target(join, 1)) +
      ", request_index=" +
      subject.input.to_string() +
      ", join_index=" +
      @acquisition.keyed_join_input(binding.join).to_string() +
      ", keyed_left=" +
      @debug.to_string(@acquisition.keyed_join_left(binding.join)) +
      ", selected=" +
      @debug.to_string(@strategy.graph_task_selected_step(graph, task)) +
      ", prefix=" +
      @debug.to_string(@strategy.graph_task_prefix_end(graph, task)),
  )
  assert_true(
    client_program_compile_local_effects_with_infer(owner, component) is Ok(_),
  )
  assert_eq(graph.supplied_slots_count(), slots)
  assert_false(@strategy.graph_ordered_inputs_complete(graph))
  assert_false(
    @strategy.graph_keyed_model_plan_inputs_complete(graph, task, step - 1),
  )
  assert_false(
    @strategy.graph_keyed_model_plan_inputs_complete(graph, task, -1),
  )
  assert_false(
    @strategy.graph_keyed_model_plan_inputs_complete(
      deferred_keyed_missing_edge(graph),
      task,
      step,
    ),
  )
  let (foreign, _, _) = deferred_keyed_model_fixture()
  let foreign_graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(foreign),
  )
  assert_false(
    @strategy.graph_keyed_model_plan_inputs_complete(
      deferred_keyed_foreign_program(graph, foreign_graph),
      task,
      step,
    ),
  )
  assert_true(
    client_program_compile_local_effects_with_infer(foreign, component)
    is Err(Compilation(ForeignInferOwner)),
  )
}

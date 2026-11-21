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
  let checked = @strategy.graph_program(graph)
  let identity = @program_check.source_identity(checked)
  let sources = []
  for i in 0..<@program_check.source_execution_count(checked) {
    let original = @program_check.source_execution_at(checked, i).unwrap()
    if @program_check.source_execution_kind(original)
      is @program_check.CarrierResponse {
      let subject = @program_check.source_execution_subject(original)
      assert_true(physical_equal(subject.owner, identity))
      let declaration = @acquisition.declaration(subject.source)
      assert_eq(declaration.stage_index, subject.stage)
      sources.push(
        (
          subject.stage,
          subject.input,
          declaration.connector,
          declaration.resource,
          @acquisition.selected_cid(subject.source),
          subject.request is @acquisition.Keyed(_, _),
        ),
      )
    }
  }
  assert_eq(sources, [
    (
      0, 0, "salesforce", "Opportunity", "sha256:3dfd92bc95dda82beeb5416b54a4a7994f8637a8d142272d5b92de7c50d83fb9",
      false,
    ),
    (
      1, 0, "drive", "files", "sha256:82bf54fe47cc1c4e4f1cecc7350c189e9f7d94dd354e1fd2330becf45d659f7b",
      false,
    ),
    (
      2, 0, "drive", "contents", "sha256:6ced0971e3bc0fe2dfa5980f093e88431833a61fc31f76194279c98cdc5e680e",
      true,
    ),
  ])
  let compiled = client_program_compile_local_effects_with_infer(
    owner, component,
  ).unwrap()
  let wire = @publication_host.client_effectful_static_plan_view(
    owner, compiled, 65536, 8192, 64,
  ).unwrap()
  assert_true(
    @publication_host.check_client_effectful_static_plan_view_binding(
      owner, compiled, wire, 65536, 8192, 64,
    )
    is Ok(_),
  )
  let view = @publication.parse_interactive_run_control_shape(
    "effectful_static_plan_view", wire, 65536, 8192, 64,
  ).unwrap()
  let computation = @identity.object_field(view, "computation").unwrap()
  let plan = @identity.object_field(computation, "plan_view").unwrap()
  let map = @identity.object_field(plan, "logical_map").unwrap()
  guard @identity.object_field(map, "steps") is Some(@identity.Array(steps)) else {
    fail("Missing original logical steps")
  }
  let matched = [false, false, false]
  for step_index in 0..<@identity.array_count(steps) {
    let logical_step = @identity.array_at(steps, step_index).unwrap()
    guard @identity.object_field(logical_step, "ports")
      is Some(@identity.Array(ports)) else {
      fail("Missing original logical ports")
    }
    for port_index in 0..<@identity.array_count(ports) {
      let port = @identity.array_at(ports, port_index).unwrap()
      guard @identity.object_field(port, "source") is Some(source) &&
        @identity.object_field(source, "kind")
        is Some(@identity.String("stage_input")) &&
        @identity.object_field(source, "stage_ordinal")
        is Some(@identity.Number(stage)) &&
        @identity.object_field(source, "input_port_ordinal")
        is Some(@identity.Number(input)) &&
        input == 0.0 else {
        continue
      }
      let index = stage.to_int()
      if index >= 0 && index < matched.length() {
        matched[index] = true
      }
    }
  }
  assert_eq(matched, [true, true, true])
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

///|
extern "js" fn static_explanation_source_links_match(
  plan_wire : String,
  context_wire : String,
) -> Bool =
  #|(planWire, contextWire) => {
  #|  const view = JSON.parse(planWire);
  #|  const steps = view.computation.plan_view.logical_map.steps;
  #|  const sources = JSON.parse(contextWire).items.filter(item => item.kind === 'source');
  #|  const expected = [['salesforce', 'Opportunity', 'direct'], ['drive', 'files', 'direct'], ['drive', 'contents', 'keyed']];
  #|  if (view.provider_io !== 0 || sources.length !== expected.length) return false;
  #|  return sources.every(({source_view, stage_input, request_kind, link_state, consuming_ports}, stage) => {
  #|    const [connector, resource, mode] = expected[stage];
  #|    const links = steps.flatMap(step => step.ports.filter(port =>
  #|      port.role === 'input' && port.source?.kind === 'stage_input' &&
  #|      port.source.stage_ordinal === stage && port.source.input_port_ordinal === 0
  #|    ).map(port => ({port_id: port.port_id, step_id: step.step_id})));
  #|    return source_view.connector === connector && source_view.resource === resource &&
  #|      stage_input.kind === 'stage_input' && stage_input.stage_ordinal === stage && stage_input.input_port_ordinal === 0 &&
  #|      request_kind === mode && link_state === 'linked' && links.length > 0 &&
  #|      JSON.stringify(consuming_ports) === JSON.stringify(links);
  #|  });
  #|}

///|
test "Static explanation Source rows retain the exact consuming ports of one Effect Plan" {
  let (owner, _, model) = deferred_keyed_model_fixture()
  let compiled = client_program_compile_local_effects_with_infer(owner, model).unwrap()
  let (original, plan) = @publication_host.capture_client_static_effect_explanation_original(
    owner, compiled, 65536, 8192, 64,
  ).unwrap()
  let writer = @encode.writer(65536, 8192, 64)
  @publication_host.write_client_static_effect_explanation_context(
    original, owner, compiled, writer, 10000,
  ).unwrap()
  assert_true(
    static_explanation_source_links_match(plan, @encode.finish(writer)),
  )
  let too_small = @encode.writer(65536, 8192, 64)
  assert_true(
    @publication_host.write_client_static_effect_explanation_context(
      original, owner, compiled, too_small, 1,
    )
    is Err(WorkLimit),
  )
  let foreign = client_program_compile_local_effects_with_infer(owner, model).unwrap()
  let rejected = @encode.writer(65536, 8192, 64)
  assert_true(
    @publication_host.write_client_static_effect_explanation_context(
      original, owner, foreign, rejected, 10000,
    )
    is Err(ForeignOriginal),
  )
}

///|
extern "js" fn static_explanation_context_matches(
  plan_wire : String,
  context_wire : String,
) -> Bool =
  #|(planWire, contextWire) => {
  #|  const plan = JSON.parse(planWire);
  #|  const context = JSON.parse(contextWire);
  #|  const view = plan.computation.plan_view;
  #|  const map = view.logical_map;
  #|  const b = context.binding;
  #|  if (context.version !== 'actql-explanation-context/0.1' || context.disclosure !== 'structural' ||
  #|      b.compiled_plan_cid !== view.compiled_plan_cid || b.logical_map_cid !== map.self_cid ||
  #|      b.check_environment_cid !== plan.check_environment_cid ||
  #|      b.parameter_values_cid !== plan.parameter_values_cid || b.program_definition_cid !== plan.program_definition_cid) return false;
  #|  const kinds = context.items.map(item => item.kind);
  #|  if (kinds.join(',') !== 'source,source,source,model_task,result,effect_set') return false;
  #|  const [, , , model, result, effects] = context.items;
  #|  const modelStep = map.steps.find(step => step.step_id === model.producer.step_id);
  #|  if (modelStep?.operator !== 'infer' || !modelStep.ports.some(port => port.port_id === model.producer.port_id && port.role === 'output') ||
  #|      model.task_id !== 'model-task:deal-review.v1' || model.dispatch_unit !== 'input_row' ||
  #|      model.input_bindings.map(input => [input.role, input.binding.name, input.binding.state].join(':')).sort().join(',') !==
  #|        'NextStep:NextStep:field,StageName:StageName:field,notes:notes:field' ||
  #|      model.output_fields.map(field => field.name).join(',') !== 'changed,next_step,stage') return false;
  #|  const resultStep = map.steps.find(step => step.step_id === result.producer.step_id);
  #|  if (result.name !== 'updates' || !resultStep?.ports.some(port => port.port_id === result.producer.port_id &&
  #|        port.role === 'output')) return false;
  #|  const member = effects.members[0];
  #|  return effects.unit_id === plan.effect_set.unit_id && effects.members.length === 1 &&
  #|    member.declaration.effect_id === plan.effect_set.members[0].effect_id &&
  #|    member.declaration.effect_kind === 'update' &&
  #|    member.declaration.input.result_name === 'aql_private_update' &&
  #|    member.write_fields.state === 'declared' &&
  #|    member.write_fields.fields.slice().sort().join(',') === 'NextStep,StageName' &&
  #|    !contextWire.includes('review.outcome') && !contextWire.includes('"prompt"') &&
  #|    !contextWire.includes('"instructions"');
  #|}

///|
test "Static Effect explanation Context keeps original Model, Result and write declarations" {
  let (owner, _, model) = deferred_keyed_model_fixture()
  let compiled = client_program_compile_local_effects_with_infer(owner, model).unwrap()
  let (original, plan) = @publication_host.capture_client_static_effect_explanation_original(
    owner, compiled, 65536, 8192, 64,
  ).unwrap()
  let writer = @encode.writer(65536, 8192, 64)
  @publication_host.write_client_static_effect_explanation_context(
    original, owner, compiled, writer, 10000,
  ).unwrap()
  let context = @encode.finish(writer)
  assert_true(static_explanation_context_matches(plan, context))
  assert_true(
    @publication.parse_interactive_run_control_shape(
      "explanation_context", context, 65536, 8192, 64,
    )
    is Ok(_),
  )
  let small_writer = @encode.writer(128, 8192, 64)
  assert_true(
    @publication_host.write_client_static_effect_explanation_context(
      original, owner, compiled, small_writer, 10000,
    )
    is Err(Encoding(@encode.OutputLimit)),
  )
}

///|
test "Static Effect Context measurement matches the original writer at exact limits" {
  let (owner, _, model) = deferred_keyed_model_fixture()
  let compiled = client_program_compile_local_effects_with_infer(owner, model).unwrap()
  let (original, plan) = @publication_host.capture_client_static_effect_explanation_original(
    owner, compiled, 65536, 8192, 64,
  ).unwrap()
  let geometry = @publication_host.measure_client_static_effect_explanation_context(
    original, owner, compiled, 65536, 8192, 64, 10000,
  ).unwrap()
  let (bytes, nodes, depth) = @encode.construction_geometry_usage(geometry)
  let writer = @encode.writer(bytes, nodes, depth)
  @publication_host.write_client_static_effect_explanation_context(
    original, owner, compiled, writer, 10000,
  ).unwrap()
  let context = @encode.finish(writer)
  assert_true(static_explanation_source_links_match(plan, context))
  assert_true(static_explanation_context_matches(plan, context))
  assert_true(
    @publication.parse_interactive_run_control_shape(
      "explanation_context", context, bytes, nodes, depth,
    )
    is Ok(_),
  )
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      @publication_host.measure_client_static_effect_explanation_context(
        original, owner, compiled, b, n, d, 10000,
      )
      is Err(Encoding(@encode.OutputLimit)),
    )
  }
  assert_true(
    @publication_host.measure_client_static_effect_explanation_context(
      original, owner, compiled, bytes, nodes, depth, 1,
    )
    is Err(WorkLimit),
  )
  let foreign = client_program_compile_local_effects_with_infer(owner, model).unwrap()
  assert_true(
    @publication_host.measure_client_static_effect_explanation_context(
      original, owner, foreign, bytes, nodes, depth, 10000,
    )
    is Err(ForeignOriginal),
  )
}

///|
extern "js" fn static_explanation_facts_mismatch(
  plan_wire : String,
  facts_wire : String,
) -> String =
  #|(planWire, factsWire) => {
  #|  const plan = JSON.parse(planWire);
  #|  const facts = JSON.parse(factsWire);
  #|  const view = plan.computation.plan_view;
  #|  const map = view.logical_map;
  #|  if (facts.version !== 'actql-explanation-facts/0.1' || facts.disclosure !== 'structural') return 'profile';
  #|  if (facts.program_definition_cid !== plan.program_definition_cid ||
  #|      facts.parameter_values_cid !== plan.parameter_values_cid ||
  #|      facts.compiled_plan_cid !== view.compiled_plan_cid ||
  #|      facts.logical_map_cid !== map.self_cid) return 'original binding';
  #|  if (facts.steps.length !== map.steps.length) return 'step count';
  #|  const joins = facts.steps.filter(step => step.meaning.kind === 'join');
  #|  const rightKeys = step => step.meaning.keys.map(key => key.right).join(',');
  #|  // Two authored Source JOINs plus the compiler's INFER join-back on id.
  #|  if (joins.map(rightKeys).join(';') !== 'name;resource,version;id' ||
  #|      joins[0].meaning.keys[0].left !== 'name' ||
  #|      joins[2].meaning.keys[0].left !== 'id') return 'checked JOIN keys';
  #|  for (let index = 0; index < facts.steps.length; index++) {
  #|    const step = facts.steps[index], original = map.steps[index];
  #|    const ports = role => original.ports.filter(port => port.role === role).map(port => port.port_id);
  #|    if (step.step_id !== original.step_id || step.operator !== original.operator ||
  #|        JSON.stringify(step.input_ports) !== JSON.stringify(ports('input')) ||
  #|        JSON.stringify(step.output_ports) !== JSON.stringify(ports('output'))) return 'step or ports: ' + index;
  #|  }
  #|  return '';
  #|}

///|
test "Static Effect Facts keep the original Source JOINs and INFER join-back" {
  let (owner, _, model) = deferred_keyed_model_fixture()
  let compiled = client_program_compile_local_effects_with_infer(owner, model).unwrap()
  let (original, plan) = @publication_host.capture_client_static_effect_explanation_original(
    owner, compiled, 65536, 8192, 64,
  ).unwrap()
  let geometry = @publication_host.measure_client_static_effect_explanation_facts(
    original, owner, compiled, 65536, 8192, 64,
  ).unwrap()
  let (bytes, nodes, depth) = geometry.complete
  let facts = @publication_host.seal_client_static_effect_explanation_facts(
    original, owner, compiled, bytes, nodes, depth,
  ).unwrap()
  let wire = @publication.run_evidence_value_json(facts)
  assert_eq(wire.length(), bytes)
  assert_eq(static_explanation_facts_mismatch(plan, wire), "")
  assert_true(
    @publication_host.seal_client_static_effect_explanation_facts(
      original, owner, compiled, 128, 8192, 64,
    )
    is Err(Encoding(@encode.OutputLimit)),
  )
  let foreign = client_program_compile_local_effects_with_infer(owner, model).unwrap()
  assert_true(
    @publication_host.seal_client_static_effect_explanation_facts(
      original, owner, foreign, 65536, 8192, 64,
    )
    is Err(ForeignOriginal),
  )
}

///|
// Inspect the original exported Array representation without a conversion.
#warnings("-deprecated")
extern "js" fn direct_source_coordinates_js_arrays(
  coordinates : Array[Array[Int]],
) -> Bool =
  #|(coordinates) => Array.isArray(coordinates) && coordinates.length === 2 && coordinates.every((row, slot) => Array.isArray(row) && row.length === 4 && row[2] === slot && row.every(Number.isSafeInteger))

///|
test "Effect Direct source coordinate bridge emits real JavaScript arrays" {
  let (prepared, _, _) = deferred_keyed_model_fixture()
  let coordinates = client_program_effect_direct_source_coordinates(prepared).unwrap()
  assert_true(direct_source_coordinates_js_arrays(coordinates))
  assert_eq(coordinates, [[0, 0, 0, 0], [1, 0, 1, 1]])
}

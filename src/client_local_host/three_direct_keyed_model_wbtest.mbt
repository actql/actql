///|
// Genuine three-Direct checked graph and original keyed/Model ports. This
// does not open Sources, execute a Model, reserve a Host or issue evidence.
test "three original Direct Sources prepare the complete keyed Model graph under the existing task bound" {
  let (declaration, wire) = original_keyed_declaration_environment(
    relation_versions=true,
  )
  guard @json.parse(wire) is Object(fields) &&
    fields["host_policy_profile"] is Object(policy) else {
    fail("original finite keyed policy")
  }
  let (environment, _) = effect_model_plan_source(
    declaration=Some(declaration),
    lookup_policy=Some(policy["lookup_execution"]),
  )
  let document =
    #|{"version":"actql/0.1","id":"three-direct-keyed-model","stages":[{"id":"left","inputs":{"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["name","resource","version"]}}},{"id":"right","inputs":{"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["name","resource","version"]}}},{"id":"third","inputs":{"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["name","resource","version"]}}},{"id":"classify","inputs":{"a":{"result":{"stage":"left","result":"rows"}},"b":{"result":{"stage":"right","result":"rows"}},"contents":{"connector":"content-fixture","resource":"contents"},"c":{"result":{"stage":"third","result":"rows"}}},"steps":[{"from":"a","join":{"with":"b","kind":"inner","on":[{"left":"name","right":"name"}],"select":{"name":"left.name","resource":"left.resource","version":"left.version"}},"as":"paired"},{"from":"paired","join":{"with":"c","kind":"inner","on":[{"left":"name","right":"name"}],"select":{"name":"left.name","resource":"left.resource","version":"left.version"}},"as":"joined"},{"from":"joined","join":{"with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"captured"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"},{"derive":{"id":{"literal":1}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"classify","result":"rows"}}}}
  let limits = @publication_host.client_standard_effect_computation_limits()
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  assert_eq(@strategy.graph_captured_prefix(graph), 3)
  let occurrence = @publication_host.prepared_client_effect_infer_occurrence(
    prepared,
  ).unwrap()
  let (_, task, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  assert_eq(
    @publication_host.client_infer_occurrence_coordinates(occurrence),
    (3, 3, 4),
  )
  assert_true(
    @strategy.graph_keyed_model_plan_inputs_complete(graph, task, step),
  )
  let direct = @publication_host.select_client_effect_direct_acquisition_occurrences(
    prepared, 1000,
  ).unwrap()
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_count(direct),
    3,
  )
  for slot in 0..<3 {
    assert_eq(
      @publication_host.client_direct_acquisition_occurrence_at(direct, slot),
      Some((slot, 0, slot)),
    )
  }
  let bounded = { ..limits, program: { ..limits.program, max_tasks: 3, }, }
  assert_true(
    @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      bounded,
    )
    is Err(@publication_host.Graph(@strategy.GraphIssue::TaskLimit)),
  )
}

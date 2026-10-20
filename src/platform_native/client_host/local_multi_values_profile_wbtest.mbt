///|
// Two independently checked tasks remain two physical occurrences. Native
// profile selection cannot collapse them to the first task or admit a Run.
test "Native source-free Values profile retains every original task" {
  let document =
    #|{"version":"actql/0.1","id":"native-multi-values-profile","stages":[{"id":"first","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"second","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"first":{"from":{"stage":"first","result":"rows"}},"second":{"from":{"stage":"second","result":"rows"}}}}
  let prepared = @host.prepare_effect_free_client_program(
    document,
    Json,
    preparation_environment(),
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let graph = @host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(@host.prepared_client_result_count(prepared), 2)
  assert_eq(@host.prepared_client_acquisition_count(prepared), 0)
  assert_true(@strategy.graph_source_free_inputs_complete(graph))
  assert_false(@strategy.graph_program_has_effects(graph))
  assert_true(native_client_local_values_profile_supported(prepared))
}

///|
fn cross_stage_capture_serialization_owner() -> PreparedClientProgram raise {
  let serialized = multi_source_program
    .replace(
      old="\"fields\":[\"id\",\"left_amount\",\"right_amount\"],\"from\":\"ordered\"",
      new="\"fields\":[\"name\",\"content\"],\"from\":\"attachment\"",
    )
    .replace(
      old="{\"as\":\"ordered\",\"sort\":[{\"id\":\"asc\"},{\"left_amount\":\"asc\"},{\"right_amount\":\"asc\"}]}",
      new="{\"as\":\"attachment\",\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\"],\"name\":\"joined.jsonl\",\"order_by\":[{\"id\":\"asc\"}],\"bounds\":{\"max_rows\":10,\"max_bytes\":1024}}}",
    )
  // Preserve both original Direct occurrences, but serialize the left only.
  // An unrelated captured task does not provide input coverage.
  multi_source_prepared(
    serialized
    .replace(
      old=",\"right_rows\":{\"result\":{\"result\":\"rows\",\"stage\":\"acquire_right\"}}",
      new="",
    )
    .replace(
      old="{\"from\":\"left_rows\",\"join\":{\"kind\":\"inner\",\"max_output_rows\":100,\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\",\"left_amount\":\"left.amount\",\"right_amount\":\"right.amount\"},\"with\":\"right_rows\"}}",
      new="{\"from\":\"left_rows\",\"select\":[\"id\",\"amount\"]}",
    ),
  )
}

///|
test "terminal serialization refuses an unrelated ordinary Source capture" {
  let owner = cross_stage_capture_serialization_owner()
  let task = @strategy.graph_stage_operation_task(owner.graph, 2, 1).unwrap()
  assert_eq(@strategy.graph_captured_prefix(owner.graph), 2)
  assert_true(
    issue_prepared_client_acquired_serialization_plan_graph(
      owner,
      task,
      1,
      10,
      1024,
      10000,
      run_materials_limits().sequence,
      1000000,
      100000,
      100,
    )
    is Err(UnsupportedGraph),
  )
}

///|
test "terminal serialization distinguishes two Whole inputs in one original task" {
  let document =
    #|{"version":"actql/0.1","id":"whole-join-content","stages":[{"id":"joined","inputs":{"left_rows":{"connector":"crm/main","resource":"r"},"right_rows":{"connector":"crm/right","resource":"r"}},"steps":[{"from":"left_rows","join":{"with":"right_rows","kind":"inner","max_output_rows":10,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","left_amount":"left.amount","right_amount":"right.amount"}}},{"as":"unique","assert_rows":{"unique_by":["id"]}},{"as":"attachment","serialize":{"format":"jsonl","fields":["id","left_amount","right_amount"],"name":"joined.jsonl","order_by":[{"id":"asc"},{"left_amount":"asc"},{"right_amount":"asc"}],"bounds":{"max_rows":10,"max_bytes":1024}}}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"joined","result":"file"}}}}
  let owner = multi_source_prepared(document)
  let task = @strategy.graph_stage_operation_task(owner.graph, 0, 2).unwrap()
  let component = issue_prepared_client_acquired_serialization_plan_component(
    owner,
    task,
    2,
    10,
    1024,
    10000,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let direct = client_serialization_plan_direct_occurrences(component, owner).unwrap()
  let left = client_direct_acquisition_occurrence_at(direct, 0).unwrap()
  let right = client_direct_acquisition_occurrence_at(direct, 1).unwrap()
  assert_true(left.0 == right.0 && left.2 == right.2 && left.1 != right.1)
  assert_true(
    client_serialization_plan_direct_occurrences(
      component,
      multi_source_prepared(document),
    )
    is None,
  )
}

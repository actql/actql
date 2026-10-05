///|
test "original DAG charges every root Result alias before binding" {
  let program = query_checked_program_fixture(
    program_text=Some(
      (
        #|{"version":"actql/0.1","id":"root-result-work","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}}],"results":{"first":{"from":{"stage":"a","result":"r"}},"second":{"from":{"stage":"a","result":"r"}},"third":{"from":{"stage":"a","result":"r"}}}}
      ),
    ),
  )
  let owners = physical_graph_owners(program)
  // One stage owner, one input-completeness visit, one owner snapshot,
  // three distinct root publication occurrences, one classification visit.
  // The captured stage exits classification before scanning any Results.
  for work in [3, 4, 5, 6] {
    assert_true(
      @strategy.prepare_checked_dag(program, owners, 1, work) is Err(WorkLimit),
    )
  }
  let graph = @strategy.prepare_checked_dag(program, owners, 1, 7).unwrap()
  assert_eq(@strategy.graph_result_count(graph), 3)
  assert_eq(@strategy.graph_task_count(graph), 1)
  assert_eq(@strategy.graph_data_count(graph), 0)
  for index in 0..<3 {
    assert_eq(@strategy.graph_result_task(graph, index), Some(0))
  }
  assert_true(
    physical_equal(@strategy.graph_task_owner(graph, 0).unwrap(), owners[0]),
  )
}

///|
test "original DAG spends obligation inventory without relying on expansion" {
  let program = query_checked_program_fixture(
    program_text=Some(
      (
        #|{"version":"actql/0.1","id":"requirement-work","stages":[{"id":"a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"r":{"from":"seed","fields":["id"]}}}],"results":{"out":{"from":{"stage":"a","result":"r"}}}}
      ),
    ),
    parameter_json="{}",
  )
  let owners = physical_graph_owners(program)
  // Original DAG: stage, owner snapshot, Values obligation, root Result = 4.
  // Classification: stage, Result, Values Step = 3. No split or remapping.
  for work in [5, 6] {
    assert_true(
      @strategy.prepare_checked_dag(
        program,
        owners,
        1,
        work,
        source_free_root=true,
      )
      is Err(WorkLimit),
    )
  }
  let graph = @strategy.prepare_checked_dag(
    program,
    owners,
    1,
    7,
    source_free_root=true,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 1)
  assert_eq(@strategy.graph_task_operation_count(graph, 0), Some(1))
  assert_eq(@strategy.graph_task_selected_step(graph, 0), None)
  assert_eq(@strategy.graph_result_count(graph), 1)
  assert_eq(@strategy.graph_data_count(graph), 0)
}

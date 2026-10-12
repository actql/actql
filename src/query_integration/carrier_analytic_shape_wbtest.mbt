///|
fn carrier_analytic_shape_document(variant : String) -> String {
  let before =
    #|{"version":"actql/0.1","id":"late-analytic-shape","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"from":"seed","analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"functions":{"n":{"fn":"row_number"}}},"as":"numbered"},
  let steps = match variant {
    "late_values" | "late_carrier" =>
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"n":{"type":"number","nullable":false}},"rows":[{"id":2,"n":1}]},"as":"later"},{"from":"numbered","append":{"with":"later"},"as":"combined"}
      )
    "late_binary" =>
      (
        #|{"from":"numbered","select":["id"],"as":"selected"},{"from":"selected","append":{"with":"seed"},"as":"combined"}
      )
    "repeated_analytic" =>
      (
        #|{"from":"numbered","analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"functions":{"m":{"fn":"row_number"}}},"as":"renumbered"},{"from":"renumbered","select":["id"],"as":"selected"},{"from":"selected","append":{"with":"seed"},"as":"combined"}
      )
    _ => abort("unknown late analytic shape fixture")
  }
  let carrier = if variant == "late_carrier" {
    (
      #|,{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"combined","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","where":"true","fields":["id"]},"as":"out"}
    )
  } else {
    ""
  }
  let result = if variant == "late_carrier" { "out" } else { "combined" }
  before +
  steps +
  carrier +
  "],\"results\":{\"rows\":{\"from\":\"" +
  result +
  "\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
}

///|
fn check_carrier_analytic_shape(
  variant : String,
  expected_operations : Array[Int],
  expected_edges : Array[(Int, Int, Int)],
  expected_work : Int,
) -> Unit raise {
  let program = query_checked_program_fixture(
    program_text=Some(carrier_analytic_shape_document(variant)),
    local_values_analytic_chain=true,
  )
  let owners = physical_graph_owners(program)
  // Literal Values owns one obligation, ROW_NUMBER owns four, Append owns
  // four, and Select owns none. There are no imported producer occurrences.
  let mut requirements = 0
  for count in expected_operations {
    requirements += count
  }
  assert_eq(
    @context.operation_closure_count(
      @context.stage_requirement_operations(
        @program_check.requirements(program),
      ),
    ),
    requirements,
  )
  // For N selected nodes and P internal ports: admission 9 + R;
  // classification 3 + 3 * (N + P), including exactly one full shape scan;
  // task mapping 3 + N; edges 2 + N + P; control 1; operations 2 + R;
  // final Result 1. The Content-fusion probe visits all N Steps (none
  // Serialize), adding N to the former 21 + 5N + 4P + 2R calculation.
  // Thus the independent current bound is 21 + 6N + 4P + 2R.
  // The shape scan alone is respectively 7, 8, and 10 visits below.
  assert_eq(
    expected_work,
    21 +
    6 * expected_operations.length() +
    4 * expected_edges.length() +
    2 * requirements,
  )
  // Retain the exact former bound as a refusal, not a weaker graph oracle.
  assert_true(
    @strategy.prepare_checked_dag(
      program, owners, 10, expected_work - expected_operations.length(),
    ) is Err(WorkLimit),
  )
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 10, expected_work - 1)
    is Err(WorkLimit),
  )
  let graph = checkpoint_graph_issue(@strategy.prepare_checked_dag(program, owners, 10, expected_work))
  assert_eq(@strategy.graph_task_count(graph), expected_operations.length() + 1)
  assert_eq(@strategy.graph_task_selected_step(graph, 0), None)
  assert_eq(@strategy.graph_task_operation_count(graph, 0), Some(0))
  assert_true(
    physical_equal(@strategy.graph_task_owner(graph, 0).unwrap(), owners[0]),
  )
  for step, operation_count in expected_operations {
    let task = step + 1
    assert_eq(@strategy.graph_task_selected_step(graph, task), Some(step))
    assert_eq(
      @strategy.graph_task_target(graph, task),
      Some(@pipeline.Step(step)),
    )
    assert_eq(@strategy.graph_task_prefix_end(graph, task), None)
    assert_eq(
      @strategy.graph_task_operation_count(graph, task),
      Some(operation_count),
    )
    assert_true(
      physical_equal(
        @strategy.graph_task_owner(graph, task).unwrap(),
        owners[1],
      ),
    )
  }
  assert_eq(@strategy.graph_data_count(graph), expected_edges.length())
  for index, (producer, consumer, input) in expected_edges {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq(
      (edge.producer, edge.consumer, edge.input),
      (producer + 1, consumer + 1, input),
    )
    assert_eq(edge.target, @pipeline.Step(producer))
    assert_eq(
      @strategy.data_edge_operation_input(edge),
      Some((consumer, input)),
    )
  }
  assert_eq(@strategy.graph_control_count(graph), 1)
  let control = @strategy.graph_control_at(graph, 0).unwrap()
  assert_eq((control.predecessor, control.consumer), (0, 1))
  assert_eq(@strategy.graph_result_count(graph), 1)
  assert_eq(
    @strategy.graph_result_task(graph, 0),
    Some(expected_operations.length()),
  )
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "later analytic classification sees a Values root after the analytic" {
  check_carrier_analytic_shape(
    "late_values",
    [1, 4, 1, 4],
    [(0, 1, 0), (1, 3, 0), (2, 3, 1)],
    77,
  )
}

///|
test "later analytic classification sees a binary consumer after the analytic" {
  check_carrier_analytic_shape(
    "late_binary",
    [1, 4, 0, 4],
    [(0, 1, 0), (1, 2, 0), (2, 3, 0), (0, 3, 1)],
    79,
  )
}

///|
test "later analytic classification charges the complete shape only once" {
  check_carrier_analytic_shape(
    "repeated_analytic",
    [1, 4, 4, 0, 4],
    [(0, 1, 0), (1, 2, 0), (2, 3, 0), (3, 4, 0), (0, 4, 1)],
    97,
  )
}

///|
test "later analytic classification sees a Carrier output after the analytic" {
  let program = query_checked_program_fixture(
    program_text=Some(carrier_analytic_shape_document("late_carrier")),
    local_values_analytic_chain=true,
    local_carrier_graph_chain=true,
  )
  let owners = physical_graph_owners(program)
  // Two Values + one ROW_NUMBER + Append + constructor + predicate MATCH:
  // 2 + 4 + 4 + 5 + 5 = 20 independent contextual obligations.
  assert_eq(
    @context.operation_closure_count(
      @context.stage_requirement_operations(
        @program_check.requirements(program),
      ),
    ),
    20,
  )
  // Admission 29; classification: two stage visits, one Result, two selected
  // inquiries, the complete six-node/five-port shape scan, one suffix visit.
  // A Relation prefix must not hide the later Graph output. No remap occurs.
  // Content-fusion scans all six Steps before that classification: 46 + 6
  // = 52. None of the six operations is Serialize.
  for work in [45, 46, 51] {
    assert_true(
      @strategy.prepare_checked_dag(program, owners, 10, work) is Err(WorkLimit),
    )
  }
  let graph = checkpoint_graph_issue(@strategy.prepare_checked_dag(program, owners, 10, 52))
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(@strategy.graph_task_selected_step(graph, 1), None)
  assert_eq(@strategy.graph_task_prefix_end(graph, 1), None)
  assert_eq(@strategy.graph_task_operation_count(graph, 1), Some(20))
  assert_eq(@strategy.graph_task_target(graph, 1), Some(@pipeline.Step(5)))
  assert_eq(@strategy.graph_result_task(graph, 0), Some(1))
  assert_eq(@strategy.graph_data_count(graph), 0)
  assert_eq(@strategy.graph_control_count(graph), 1)
  assert_true(
    physical_equal(@strategy.graph_task_owner(graph, 1).unwrap(), owners[1]),
  )
}

///|
fn physical_graph_owners(
  program : @program_check.CheckedProgram,
) -> Array[@lower.BoundPrepared] {
  let identity = @program_check.source_identity(program)
  Array::makei(@program_check.unit_count(program), stage => {
    let pipeline = @program_check.unit_pipeline(program, stage).unwrap()
    let prepared = @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    }).unwrap()
    let values = @parameter_refs.bound_values(
      @context.stage_identity_parameter_values(
        @context.program_identity_stage_at(identity, stage).unwrap(),
      ),
    )
    @lower.bind_parameters(
      prepared,
      Some(values),
      max_parameters=100,
      max_name_bytes=10000,
      expression_profiles=checked_expression_profile_admission(program),
    ).unwrap()
  })
}

///|
test "physical DAG reads checked data and control edges separately" {
  let program = query_checked_program_fixture(dag=true)
  let owners = physical_graph_owners(program)
  let graph = @strategy.prepare_checked_dag(program, owners, 4, 1000).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_data_count(graph), 3)
  assert_eq(@strategy.graph_control_count(graph), 3)
  for (edge, producer, consumer) in [(0, 0, 1), (1, 0, 2), (2, 1, 3)] {
    let actual = @strategy.graph_data_at(graph, edge).unwrap()
    assert_eq(
      (actual.producer, actual.consumer, actual.input),
      (producer, consumer, 0),
    )
    assert_eq(actual.target, @pipeline.Step(1))
  }
  // B reads X, but must still wait for A's checked Stage-success barrier.
  for i in 0..<3 {
    let control = @strategy.graph_control_at(graph, i).unwrap()
    assert_eq((control.predecessor, control.consumer), (i, i + 1))
  }
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 3, 1000) is Err(TaskLimit),
  )
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 4, 0) is Err(WorkLimit),
  )
  let other = query_checked_program_fixture(dag=true)
  let foreign = physical_graph_owners(other)
  assert_true(
    @strategy.prepare_checked_dag(program, foreign, 4, 1000)
    is Err(ForeignPipeline(0)),
  )
  owners[1] = foreign[1]
  assert_false(
    physical_equal(@strategy.graph_task_owner(graph, 1).unwrap(), foreign[1]),
  )
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 4, 1000)
    is Err(ForeignPipeline(1)),
  )
}

///|
test "physical DAG retains fused session and segments Relation consumers" {
  for (variant, expected_steps) in [("session", 0), ("session_filter", 4)] {
    let program = query_checked_program_fixture(
      dag=true,
      local_carrier_events_chain=true,
      local_carrier_events_variant=variant,
    )
    let owners = physical_graph_owners(program)
    let physical = @strategy.prepare_checked_dag(
      program,
      owners,
      @program_check.unit_count(program) + 10,
      10000,
    ).unwrap()
    let selected = []
    for task in 0..<@strategy.graph_task_count(physical) {
      if @strategy.graph_task_selected_step(physical, task) is Some(step) {
        selected.push((task, step))
        assert_eq(
          @strategy.graph_task_target(physical, task),
          Some(@pipeline.Step(step)),
        )
      }
    }
    assert_eq(
      selected.map(pair => pair.1),
      Array::makei(expected_steps, i => i),
    )
    // Each selected step keeps its Stage-to-task ownership.
    for (task, step) in selected {
      assert_eq(
        @strategy.graph_stage_target_task(physical, 2, @pipeline.Step(step)),
        Some(task),
      )
    }
    let operation_edges = []
    for edge in 0..<@strategy.graph_data_count(physical) {
      let value = @strategy.graph_data_at(physical, edge).unwrap()
      if @strategy.data_edge_operation_input(value) is Some(position) {
        operation_edges.push(position)
      }
    }
    assert_eq(operation_edges, Array::makei(expected_steps, i => (i, 0)))
    assert_true(@strategy.graph_ordered_inputs_complete(physical))
  }
}

///|
test "physical DAG segments typed Carrier and Relation operation edges" {
  let program = query_checked_program_fixture(
    dag=true,
    local_carrier_graph_chain=true,
    local_carrier_graph_variant="normalize_filter",
  )
  let owners = physical_graph_owners(program)
  let physical = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  let selected = []
  for task in 0..<@strategy.graph_task_count(physical) {
    if @strategy.graph_task_selected_step(physical, task) is Some(step) {
      selected.push((task, step))
    }
  }
  assert_eq(selected.map(pair => pair.1), [0, 1, 2, 3])
  let operation_edges = []
  for edge in 0..<@strategy.graph_data_count(physical) {
    let value = @strategy.graph_data_at(physical, edge).unwrap()
    if @strategy.data_edge_operation_input(value) is Some(position) {
      operation_edges.push(position)
    }
  }
  assert_eq(operation_edges, [(0, 0), (0, 1), (1, 0), (2, 0), (3, 0)])
  assert_true(@strategy.graph_ordered_inputs_complete(physical))
}

///|
test "physical DAG retains an unselected Carrier prefix before Relation filter" {
  let program = query_checked_program_fixture(
    dag=true,
    local_carrier_graph_chain=true,
    local_carrier_graph_variant="subgraph_filter",
  )
  let owners = physical_graph_owners(program)
  let graph = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 6)
  assert_eq(@strategy.graph_task_prefix_end(graph, 2), Some(2))
  assert_eq(@strategy.graph_task_target(graph, 2), Some(@pipeline.Step(2)))
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(3))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 5, 10000)
    is Err(@strategy.TaskLimit),
  )
}

///|
test "physical DAG retains Events and Vectors prefixes before Relation filter" {
  for
    (events, variant) in [(true, "dedupe_filter"), (false, "normalize_filter")] {
    let program = query_checked_program_fixture(
      dag=true,
      local_carrier_events_chain=events,
      local_carrier_events_variant=variant,
      local_carrier_vectors_chain=!events,
      local_carrier_vectors_variant=variant,
    )
    let graph = @strategy.prepare_checked_dag(
      program,
      physical_graph_owners(program),
      @program_check.unit_count(program) + 10,
      10000,
    ).unwrap()
    assert_eq(@strategy.graph_task_count(graph), 6)
    assert_eq(@strategy.graph_task_prefix_end(graph, 2), Some(2))
    assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(3))
    assert_true(@strategy.graph_ordered_inputs_complete(graph))
  }
}

///|
test "physical DAG segments Events projection before Relation filter" {
  let program = query_checked_program_fixture(
    dag=true,
    local_carrier_events_chain=true,
    local_carrier_events_variant="session_filter",
  )
  let owners = physical_graph_owners(program)
  let graph = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG segments Vectors projection before Relation filter" {
  let program = query_checked_program_fixture(
    dag=true,
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant="bridge_filter",
  )
  let owners = physical_graph_owners(program)
  let graph = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 7)
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG separates bounded cross join from Relation filter" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_cross_external_chain=true,
    local_values_cross_external_filter=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 7)
  assert_eq(@strategy.graph_task_prefix_end(graph, 3), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 4), Some(1))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG separates bounded values from Relation filter" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_filter=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(@strategy.graph_task_prefix_end(graph, 1), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG separates bounded values from Relation assertion" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_assert=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(@strategy.graph_task_prefix_end(graph, 1), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG separates bounded values from unique assertion" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_assert_unique=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(@strategy.graph_task_prefix_end(graph, 1), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG separates bounded values from select take and derive" {
  for variant in ["select", "take", "derive"] {
    let program = query_checked_program_fixture(
      dag=true,
      local_values_two_consumer_chain=true,
      local_values_two_consumer_relation_variant=variant,
    )
    let graph = @strategy.prepare_checked_dag(
      program,
      physical_graph_owners(program),
      @program_check.unit_count(program) + 10,
      10000,
    ).unwrap()
    assert_eq(@strategy.graph_task_count(graph), 5)
    assert_eq(@strategy.graph_task_prefix_end(graph, 1), Some(0))
    assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
    assert_true(@strategy.graph_ordered_inputs_complete(graph))
  }
}

///|
test "physical DAG separates independent bounded Relation branches" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_relation_variant="independent_branches",
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 7)
  for step in 0..<4 {
    assert_eq(@strategy.graph_task_selected_step(graph, step + 1), Some(step))
  }
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG retains both append input occurrences after values split" {
  for variant in ["local", "self", "aligned"] {
    let program = query_checked_program_fixture(
      dag=true,
      local_values_append_chain=true,
      local_values_append_variant=variant,
    )
    let graph = @strategy.prepare_checked_dag(
      program,
      physical_graph_owners(program),
      @program_check.unit_count(program) + 10,
      10000,
    ).unwrap()
    assert_eq(@strategy.graph_task_count(graph), 6)
    for step in 0..<3 {
      assert_eq(@strategy.graph_task_selected_step(graph, step + 1), Some(step))
    }
    let sources = []
    for edge in 0..<@strategy.graph_data_count(graph) {
      let data = @strategy.graph_data_at(graph, edge).unwrap()
      if data.consumer == 3 {
        sources.push((data.input, data.producer))
      }
    }
    assert_eq(
      sources,
      if variant == "self" {
        [(0, 1), (1, 1)]
      } else {
        [(0, 1), (1, 2)]
      },
    )
    assert_true(@strategy.graph_ordered_inputs_complete(graph))
  }
}

///|
test "physical DAG splits two values before bounded cross join" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_cross_chain=true,
    local_values_cross_direct=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 6)
  for step in 0..<3 {
    assert_eq(@strategy.graph_task_selected_step(graph, step + 1), Some(step))
  }
  let sources = []
  for edge in 0..<@strategy.graph_data_count(graph) {
    let data = @strategy.graph_data_at(graph, edge).unwrap()
    if data.consumer == 3 {
      sources.push((data.input, data.producer))
    }
  }
  assert_eq(sources, [(0, 1), (1, 2)])
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG selects distinct inputs before same-stage cross join" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_cross_chain=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 8)
  for step in 0..<5 {
    assert_eq(@strategy.graph_task_selected_step(graph, step + 1), Some(step))
  }
  let sources = []
  for edge in 0..<@strategy.graph_data_count(graph) {
    let data = @strategy.graph_data_at(graph, edge).unwrap()
    if data.consumer == 5 {
      sources.push((data.input, data.producer))
    }
  }
  assert_eq(sources, [(0, 2), (1, 4)])
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG separates bounded values from sort and take" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_sort_take=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 6)
  assert_eq(@strategy.graph_task_prefix_end(graph, 1), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(2))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG splits an indexed Relation input before take" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_relation_variant="separate_sort_take",
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 6)
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(1))
  assert_eq(@strategy.graph_task_target(graph, 2), Some(@pipeline.Step(0)))
  assert_eq(@strategy.graph_task_target(graph, 3), Some(@pipeline.Step(1)))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG splits unary Relation steps after bounded values" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_relation_variant="separate_filter_sort_take",
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 7)
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(1))
  assert_eq(@strategy.graph_task_selected_step(graph, 4), Some(2))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG splits a chain of bounded Relation Stages" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_relation_variant="chained_filter_sort_take",
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 7)
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 4), Some(1))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG splits supplied Relation rows into bounded tasks" {
  let program = query_checked_program_fixture(
    dag=true,
    local_supplied_relation_chain=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 7)
  for step in 0..<4 {
    assert_eq(@strategy.graph_task_selected_step(graph, step + 1), Some(step))
  }
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG separates bounded values from distinct" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_two_consumer_chain=true,
    local_values_two_consumer_relation_variant="distinct",
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(@strategy.graph_task_prefix_end(graph, 1), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG splits imported full join sources at distinct" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_join_chain=true,
    local_values_join_kind="full",
    local_values_join_imported_full=true,
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_eq(@strategy.graph_task_prefix_end(graph, 1), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  assert_eq(@strategy.graph_task_prefix_end(graph, 3), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 4), Some(1))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG selects both branches of a same-stage equality join" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_join_chain=true,
    local_values_join_kind="full",
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 10)
  for step in 0..<7 {
    assert_eq(@strategy.graph_task_selected_step(graph, step + 1), Some(step))
  }
  let sources = []
  for edge in 0..<@strategy.graph_data_count(graph) {
    let data = @strategy.graph_data_at(graph, edge).unwrap()
    if data.consumer == 5 {
      sources.push((data.input, data.producer))
    }
  }
  assert_eq(sources, [(0, 2), (1, 4)])
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  assert_true(
    @strategy.prepare_checked_dag(
      program,
      physical_graph_owners(program),
      9,
      10000,
    )
    is Err(@strategy.TaskLimit),
  )
}

///|
test "physical DAG selects keyed count after an internal Values producer" {
  let program = query_checked_program_fixture(
    dag=true,
    local_values_group_chain=true,
    local_values_group_variant="keyed_same_stage",
  )
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    5,
    10000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(@strategy.graph_task_prefix_end(graph, 1), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  let edges = []
  for index in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    edges.push((edge.producer, edge.consumer))
  }
  assert_eq(edges.length(), 3)
  assert_true(edges.contains((1, 2)))
  assert_true(edges.contains((2, 3)))
  assert_true(edges.contains((2, 4)))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "physical DAG admits Carrier segmentation before allocation" {
  let program = query_checked_program_fixture(
    dag=true,
    local_carrier_events_chain=true,
    local_carrier_events_variant="session",
  )
  let owners = physical_graph_owners(program)
  let expanded = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program) + 10,
    10000,
  ).unwrap()
  let required = @strategy.graph_task_count(expanded)
  assert_true(
    @strategy.prepare_checked_dag(program, owners, required - 1, 10000)
    is Err(@strategy.TaskLimit),
  )
  assert_true(
    @strategy.expand_internal_carrier_tasks(expanded, required - 1, 10000)
    is Ok(_),
  )
}

///|
fn captured_graph_fixture(
  dag_two_consumers_of_compute_a? : Bool = false,
  count? : Bool = false,
  count_filter_chain? : Bool = false,
  keyed_count_filter_chain? : Bool = false,
  window_filter_chain? : Bool = false,
  unpivot_filter_chain? : Bool = false,
  dedupe_filter_chain? : Bool = false,
  collections? : Bool = false,
  join? : Bool = false,
  self_join? : Bool = false,
  numeric_dag? : Bool = false,
  sort_take? : Bool = false,
  values? : Bool = false,
  local_values_two_consumer_chain? : Bool = false,
  local_values_two_consumer_filter? : Bool = false,
  local_values_two_consumer_assert? : Bool = false,
  local_values_two_consumer_assert_unique? : Bool = false,
  local_values_two_consumer_sort_take? : Bool = false,
  local_values_two_consumer_relation_variant? : String = "",
  local_values_managed_variant? : String = "",
  local_values_group_chain? : Bool = false,
  local_values_group_variant? : String = "keyed",
  local_values_window_chain? : Bool = false,
  local_values_window_variant? : String = "fixed",
  local_values_window_group_chain? : Bool = false,
  local_values_window_group_variant? : String = "fixed_keyed",
  local_values_lag_chain? : Bool = false,
  local_values_lag_variant? : String = "literal",
  local_values_watermark_chain? : Bool = false,
  local_values_watermark_variant? : String = "fixed_mark",
  local_carrier_events_chain? : Bool = false,
  local_carrier_events_variant? : String = "watermark",
  local_carrier_graph_chain? : Bool = false,
  local_carrier_graph_variant? : String = "projection",
  local_time_series_chain? : Bool = false,
  local_carrier_vectors_chain? : Bool = false,
  local_carrier_vectors_variant? : String = "normalize",
  local_supplied_ranking_chain? : Bool = false,
  local_supplied_relation_chain? : Bool = false,
  local_supplied_relation_variant? : String = "baseline",
  local_supplied_ranking_policy? : String = "\"max\"",
  local_vector_expression_chain? : Bool = false,
  local_values_analytic_chain? : Bool = false,
  local_values_analytic_variant? : String = "baseline",
  local_values_append_chain? : Bool = false,
  local_values_append_variant? : String = "local",
  local_values_cross_chain? : Bool = false,
  local_values_cross_direct? : Bool = false,
  local_values_cross_external_chain? : Bool = false,
  local_values_cross_external_filter? : Bool = false,
  local_values_cross_singleton? : Bool = false,
  local_values_cross_output_guard? : Int? = None,
  local_values_set_operation? : String = "",
  local_values_set_duplicates? : String = "all",
  local_values_join_chain? : Bool = false,
  local_values_join_kind? : String = "inner",
  local_values_join_imported_full? : Bool = false,
  local_values_interval_chain? : Bool = false,
  local_values_asof_chain? : Bool = false,
  local_values_sequence_chain? : Bool = false,
  local_values_nest_chain? : Bool = false,
  local_values_nest_unwrap_chain? : Bool = false,
  local_values_unary_chain? : String? = None,
  local_select_qualified_chain? : Bool = false,
  linear_compute_stages? : Int = 0,
  join_steps? : Array[Int] = [0],
  managed_publication? : Bool = false,
  nullable? : Bool = false,
  rows? : Array[String]? = None,
  retention? : @mock.MockRetentionLimits = query_retention_limits(),
  ledger_limits? : @resources.LedgerLimits? = None,
  compute_filter? : String = "id > 2",
  parameter_json? : String = "{\"minimum\":1}",
  supplied_local_rows? : Array[(Int, Int, Array[String])] = [],
) -> (@strategy.CapturedDAG, @mock.MockQueryIssuer) raise {
  let program = query_checked_program_fixture(
    nullable~,
    dag=true,
    dag_two_consumers_of_compute_a~,
    dag_count=count,
    dag_count_filter_chain=count_filter_chain,
    dag_keyed_count_filter_chain=keyed_count_filter_chain,
    dag_window_filter_chain=window_filter_chain,
    dag_unpivot_filter_chain=unpivot_filter_chain,
    dag_dedupe_filter_chain=dedupe_filter_chain,
    dag_collections=collections,
    dag_join=join,
    self_join~,
    numeric_dag~,
    sort_take~,
    dag_values=values,
    local_values_two_consumer_chain~,
    local_values_two_consumer_filter~,
    local_values_two_consumer_assert~,
    local_values_two_consumer_assert_unique~,
    local_values_two_consumer_sort_take~,
    local_values_two_consumer_relation_variant~,
    local_values_managed_variant~,
    local_values_group_chain~,
    local_values_group_variant~,
    local_values_window_chain~,
    local_values_window_variant~,
    local_values_window_group_chain~,
    local_values_window_group_variant~,
    local_values_lag_chain~,
    local_values_lag_variant~,
    local_values_watermark_chain~,
    local_values_watermark_variant~,
    local_carrier_events_chain~,
    local_carrier_events_variant~,
    local_carrier_graph_chain~,
    local_carrier_graph_variant~,
    local_time_series_chain~,
    local_carrier_vectors_chain~,
    local_carrier_vectors_variant~,
    local_supplied_ranking_chain~,
    local_supplied_relation_chain~,
    local_supplied_relation_variant~,
    local_supplied_ranking_policy~,
    local_vector_expression_chain~,
    local_values_analytic_chain~,
    local_values_analytic_variant~,
    local_values_append_chain~,
    local_values_append_variant~,
    local_values_cross_chain~,
    local_values_cross_direct~,
    local_values_cross_external_chain~,
    local_values_cross_external_filter~,
    local_values_cross_singleton~,
    local_values_cross_output_guard~,
    local_values_set_operation~,
    local_values_set_duplicates~,
    local_values_join_chain~,
    local_values_join_kind~,
    local_values_join_imported_full~,
    local_values_interval_chain~,
    local_values_asof_chain~,
    local_values_sequence_chain~,
    local_values_nest_chain~,
    local_values_nest_unwrap_chain~,
    local_values_unary_chain~,
    local_select_qualified_chain~,
    linear_compute_stages~,
    join_steps~,
    managed_publication~,
    compute_filter~,
    parameter_json~,
  )
  let sequence = query_checked_sequence(program)
  let owners = physical_graph_owners(program)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program) + 100,
    1000,
  ).unwrap()
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(program),
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "dag-test", 100,
  ).unwrap()
  let attempt = query_issuer_attempt(issuer, sequence, @mock.NativeQuery, rows~)
  query_issuer_run(attempt, retention~)
  let records = @mock.issue_mock_query_records(attempt, query_material_limits()).unwrap()
  let observation = @mock.capture_mock_query(
    issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let source = @mock.mock_captured_source(issuer, attempt, observation).unwrap()
  let ledger = @resources.create_ledger(
    ledger_limits.unwrap_or({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 300000L,
      retained_bytes: 32000000L,
      execution_bytes: 134217728L,
    }),
  ).unwrap()
  let supplied = supplied_local_rows.map(entry => {
    let (stage, input, rows) = entry
    @execution.capture_input(
      owners[stage],
      input,
      rows.map(input_cursor),
      max_rows=100,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    ).unwrap()
  })
  (
    @strategy.open_captured_dag(graph, source, ledger, supplied~).unwrap(),
    issuer,
  )
}

///|
test "captured DAG admits a checked zero-input Compute without a dummy edge" {
  let (run, issuer) = captured_graph_fixture(values=true)
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_data_count(graph), 2)
  let owner = @strategy.graph_task_owner(graph, 2).unwrap()
  assert_eq(
    @pipeline.input_count(@lower.pipeline(@lower.bound_preparation(owner))),
    0,
  )
  assert_eq(@strategy.next_captured_task(run), Some(1))
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}

///|
fn captured_graph_local(
  run : @strategy.CapturedDAG,
  task : Int,
  limits? : @execution.SequenceExecutionLimits = compute_test_limits(),
  supplied_registry? : @connector.CapabilityRegistry? = None,
) -> Result[Unit, @strategy.RunIssue] raise {
  let owner = @strategy.graph_task_owner(
    @strategy.captured_dag_graph(run),
    task,
  ).unwrap()
  let input_count = @pipeline.input_count(
    @lower.pipeline(@lower.bound_preparation(owner)),
  )
  let inputs = Array::makei(input_count, port => {
    @strategy.captured_task_input(run, task, 100, 10000, input_index=port).unwrap()
  })
  let request = @connector.prepare_fixed_compute_request(inputs, {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  let registry = match supplied_registry {
    Some(registry) => registry
    None =>
      @connector.prepare_capability_registry(
        [
          {
            name: "local",
            acquisition: false,
            fixed_compute: true,
            effect: false,
          },
        ],
        1,
        100,
      ).unwrap()
  }
  let generated = task_test_generated(owner)
  let generated = match
    @strategy.graph_task_selected_step(@strategy.captured_dag_graph(run), task) {
    Some(step) =>
      @execution.select_generated_sequence_step(generated, step).unwrap()
    None => generated
  }
  let prepared = @local_connector.local_fixed_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    generated,
    [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(5L), }],
    { transfer_bytes: Some(0L), retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("local candidate")
  }
  let join_output_ceilings = []
  let join_count = @strategy.captured_task_join_output_count(run, task).unwrap()
  for index in 0..<join_count {
    join_output_ceilings.push(
      @strategy.captured_task_join_output_at(run, task, index).unwrap(),
    )
  }
  let compute = match
    @local_connector.prepare_local_compute_execution(
      choice,
      prepared,
      limits,
      { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
      join_output_ceilings~,
    ) {
    Ok(value) => value
    Err(InvalidLimits) => return Err(Physical(InvalidLimits))
    Err(issue) => return Err(Compute(issue))
  }
  @strategy.execute_captured_synchronous_task(run, task, compute)
}

///|
test "captured checked DAG runs shared X A B C in checked control order" {
  let (run, issuer) = captured_graph_fixture()
  assert_eq(@strategy.next_captured_task(run), Some(1))
  assert_true(
    @strategy.captured_task_input(run, 2, 100, 10000) is Err(NotReady),
  )
  captured_graph_local(run, 1).unwrap()
  assert_eq(@strategy.next_captured_task(run), Some(2))
  captured_graph_local(run, 2).unwrap()
  // C consumes completed A, not the now closed original acquisition.
  @mock.close_mock_query_issuer(issuer)
  captured_graph_local(run, 3).unwrap()
  assert_true(@strategy.next_captured_task(run) is None)
  for (task, expected) in [(1, [3.0]), (2, [3.0, 2.0]), (3, [3.0])] {
    let output = @strategy.captured_task_output(run, task, Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), expected.length())
    for i, value in expected {
      assert_true(
        @execution.completed_cell(output, i, 0) is Some(Number(actual)) &&
        actual == value,
      )
    }
  }
}

///|
test "captured count DAG binds its exact single step port and survives source close" {
  let (run, issuer) = captured_graph_fixture(count=true)
  assert_eq(@strategy.captured_task_target(run, 0), None)
  assert_eq(@strategy.captured_task_target(run, -1), None)
  assert_eq(@strategy.captured_task_target(run, 4), None)
  assert_eq(@strategy.captured_task_target(run, 1), Some(Step(0)))
  assert_eq(@strategy.captured_task_target(run, 3), Some(Step(1)))
  let edge = @strategy.graph_data_at(@strategy.captured_dag_graph(run), 2).unwrap()
  assert_eq((edge.producer, edge.consumer, edge.target), (1, 3, Step(0)))
  captured_graph_local(run, 1).unwrap()
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  let counted = @strategy.captured_task_output(run, 1, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(counted), 1)
  assert_true(@execution.completed_cell(counted, 0, 0) is Some(Number(2)))
  captured_graph_local(run, 2).unwrap()
  @mock.close_mock_query_issuer(issuer)
  captured_graph_local(run, 3).unwrap()
  let downstream = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(2)))
  @strategy.close_captured_task_output(run, 1)
  assert_true(@strategy.captured_task_output(run, 1, Step(0)) is None)
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(2)))
}

///|
test "captured DAG cancellation stops new branches but keeps independent completed tasks" {
  let (run, issuer) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  let pending = @strategy.captured_task_input(run, 2, 100, 10000).unwrap()
  @mock.close_mock_query_issuer(issuer)
  assert_false(@execution.producer_read_available(pending))
  assert_true(
    @strategy.captured_task_input(run, 2, 100, 10000)
    is Err(Read(ProducerUnavailable)),
  )
  @strategy.stop_captured_dag(run)
  assert_true(@strategy.captured_task_input(run, 2, 100, 10000) is Err(Stopped))
  assert_true(@strategy.next_captured_task(run) is None)
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@strategy.captured_task_output(run, 2, Step(1)) is None)
}

///|
test "captured DAG latches execution failure without revoking previous task success" {
  let (run, _issuer) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  assert_true(
    captured_graph_local(run, 2, limits={
      ..compute_test_limits(),
      max_work: 0,
    })
    is Err(Compute(_)),
  )
  assert_true(@strategy.next_captured_task(run) is None)
  assert_true(@strategy.captured_task_input(run, 3, 100, 10000) is Err(Stopped))
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
  assert_true(@strategy.captured_task_output(run, 2, Step(1)) is None)
  assert_true(@strategy.captured_dag_failure(run) is Some((2, Compute(_))))
  @strategy.stop_captured_dag(run)
  assert_true(@strategy.captured_dag_failure(run) is Some((2, Compute(_))))
}

///|
fn mean_source_owner() -> @lower.BoundPrepared {
  bind(
    @pipeline.check_carriers(
      cursor("[{\"from\":\"g\",\"normalize_graph\":true}]"),
      [("g", empty_graph_contract())],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn mean_owner(
  first : @lower.BoundPrepared,
  second : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"mean_graphs\":{" +
        "\"with\":[\"a\",\"b\",\"a\"]," +
        "\"weights\":[1,3,2]," +
        "\"support\":{\"nodes\":0.5,\"edges\":0.5}," +
        "\"properties\":{\"nodes\":{},\"edges\":{}}},\"as\":\"m\"}]",
      ),
      [
        (
          "a",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(first)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "b",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(second)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn mean_graph(
  owner : @lower.BoundPrepared,
  nodes : Array[Double],
  edges : Array[(Double, Double)],
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  for identity in nodes {
    @graph.append_node(output, number(identity), []).unwrap()
  }
  for (source, target) in edges {
    @graph.append_edge(
      output,
      number(source),
      number(target),
      Some(text("edge", nullable=true)),
      [],
    ).unwrap()
  }
  @graph.finish_output(output).unwrap()
}

///|
fn mean_views(
  owner : @lower.BoundPrepared,
  first_owner : @lower.BoundPrepared,
  second_owner : @lower.BoundPrepared,
  first : @graph.Completed,
  second : @graph.Completed,
) -> Array[@lifecycle.ProducerView] {
  let first_read = @graph.prepare_producer_read(owner, 0, first_owner, first).unwrap()
  let second_read = @graph.prepare_producer_read(owner, 1, second_owner, second).unwrap()
  [
    @graph.producer_read_view(first_read).unwrap(),
    @graph.producer_read_view(second_read).unwrap(),
    @graph.producer_read_view(first_read).unwrap(),
  ]
}

///|
fn finish_mean(execution : MeanExecution) -> @graph.Completed {
  while true {
    match advance_mean(execution, 1).unwrap() {
      MeanContinue(_) => ()
      MeanComplete(output, ..) => return output
      MeanFailed(_, ..) => abort("mean failed")
      MeanStopped(_, ..) => abort("mean stopped")
    }
  }
  abort("unreachable")
}

///|
fn mean_scale_limits(count : Int) -> @storage.Limits {
  {
    max_input_rows: count,
    max_nodes: count,
    max_edges: count,
    max_value_bytes: 1000,
    max_total_value_bytes: 1000000,
    max_retained_value_bytes: 1000000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 100000,
    max_work: 100000,
    max_workspace_slots: count * 8 + 16,
  }
}

///|
fn mean_graph_with_limits(
  owner : @lower.BoundPrepared,
  nodes : Array[Double],
  limits : @storage.Limits,
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    limits,
    1000000L,
    fn() { true },
  ).unwrap()
  for identity in nodes {
    @graph.append_node(output, number(identity), []).unwrap()
  }
  @graph.finish_output(output).unwrap()
}

///|
fn mean_scale_work(count : Int) -> Int64 raise {
  let first_owner = mean_source_owner()
  let second_owner = mean_source_owner()
  let owner = mean_owner(first_owner, second_owner)
  let limits = mean_scale_limits(count)
  let first = mean_graph_with_limits(
    first_owner,
    Array::makei(count, index => (count - index).to_double()),
    limits,
  )
  let second = mean_graph_with_limits(second_owner, [], limits)
  let execution = start_mean_views(
    @bounded.control(),
    sequence(owner),
    0,
    mean_views(owner, first_owner, second_owner, first, second),
    limits,
    1000000L,
    4096,
    fn() { true },
  ).unwrap()
  let work = match advance_mean(execution, 100000).unwrap() {
    MeanComplete(_, work~, ..) => work
    _ => abort("mean scale execution did not complete")
  }
  assert_true(cleanup_mean(execution).unwrap())
  work
}

///|
test "graph mean retains exact support in canonical identity order" {
  let first_owner = mean_source_owner()
  let second_owner = mean_source_owner()
  let owner = mean_owner(first_owner, second_owner)
  let first = mean_graph(first_owner, [3.0, 2.0], [(2.0, 3.0)])
  let second = mean_graph(second_owner, [2.0, 1.0], [(1.0, 2.0)])
  let execution = start_mean_views(
    @bounded.control(),
    sequence(owner),
    0,
    mean_views(owner, first_owner, second_owner, first, second),
    storage_limits(),
    4096L,
    4096,
    fn() { true },
  ).unwrap()
  let completed = finish_mean(execution)
  let storage = @graph.completed_storage(completed).unwrap()
  assert_eq(@storage.node_count(storage), 3)
  assert_eq(@storage.edge_count(storage), 2)
  for index, expected in [1.0, 2.0, 3.0] {
    assert_eq(
      @value.canonical_scalar_text(
        @storage.node_identity(storage, index).unwrap(),
        10,
      ),
      Some(expected.to_string()),
    )
  }
  assert_eq(@storage.edge_endpoints(storage, 0), Some((0, 1)))
  assert_eq(@storage.edge_endpoints(storage, 1), Some((1, 2)))
  assert_true(mean_stopped(execution))
  assert_true(mean_cleanup_pending(execution))
  assert_eq(cleanup_mean(execution), Ok(true))
}

///|
test "graph mean cancellation stops before cleanup" {
  let first_owner = mean_source_owner()
  let second_owner = mean_source_owner()
  let owner = mean_owner(first_owner, second_owner)
  let first = mean_graph(first_owner, [1.0, 2.0], [])
  let second = mean_graph(second_owner, [2.0, 3.0], [])
  let control = @bounded.control()
  let execution = start_mean_views(
    control,
    sequence(owner),
    0,
    mean_views(owner, first_owner, second_owner, first, second),
    storage_limits(),
    4096L,
    4096,
    fn() { true },
  ).unwrap()
  assert_true(advance_mean(execution, 1).unwrap() is MeanContinue(_))
  @bounded.request_cancel(control) |> ignore
  assert_true(advance_mean(execution, 1).unwrap() is MeanStopped(_))
  assert_true(mean_stopped(execution))
  assert_true(mean_cleanup_pending(execution))
  assert_eq(cleanup_mean(execution), Ok(true))
  assert_false(mean_cleanup_pending(execution))
}

///|
fn mean_numeric_contract() -> @carrier.Carrier {
  let number = @contract.primitive(@contract.NumberType, nullable=true)
  let properties = @carrier.rows(
    [(@schema.Unqualified("score"), Some(number))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  @carrier.graph(
    @contract.primitive(@contract.NumberType, nullable=false),
    properties,
    properties,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
fn mean_numeric_source_owner() -> @lower.BoundPrepared {
  bind(
    @pipeline.check_carriers(
      cursor("[{\"from\":\"g\",\"normalize_graph\":true}]"),
      [("g", mean_numeric_contract())],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn mean_numeric_owner(
  first : @lower.BoundPrepared,
  second : @lower.BoundPrepared,
  third : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  mean_numeric_policy_owner(first, second, third, "zero", "zero")
}

///|
fn mean_numeric_policy_owner(
  first : @lower.BoundPrepared,
  second : @lower.BoundPrepared,
  third : @lower.BoundPrepared,
  missing : String,
  nulls : String,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"mean_graphs\":{" +
        "\"with\":[\"a\",\"b\",\"c\"]," +
        "\"weights\":[1,2,3]," +
        "\"support\":{\"nodes\":0.5,\"edges\":1}," +
        "\"properties\":{\"nodes\":{\"score\":{" +
        "\"mean\":{\"missing\":\"" +
        missing +
        "\",\"nulls\":\"" +
        nulls +
        "\"}}}," +
        "\"edges\":{\"score\":\"exact_equal\"}}},\"as\":\"m\"}]",
      ),
      [
        (
          "a",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(first)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "b",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(second)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "c",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(third)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn mean_exact_owner(
  first : @lower.BoundPrepared,
  second : @lower.BoundPrepared,
  third : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"mean_graphs\":{" +
        "\"with\":[\"a\",\"b\",\"c\"]," +
        "\"weights\":[1,2,3]," +
        "\"support\":{\"nodes\":0.5,\"edges\":1}," +
        "\"properties\":{\"nodes\":{\"score\":\"exact_equal\"}," +
        "\"edges\":{\"score\":\"exact_equal\"}}},\"as\":\"m\"}]",
      ),
      [
        (
          "a",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(first)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "b",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(second)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "c",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(third)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn mean_numeric_value(text : String) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.NumberType, nullable=true),
    cursor(text),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn mean_numeric_graph(
  owner : @lower.BoundPrepared,
  property : @value.CheckedValue?,
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  if property is Some(value) {
    @graph.append_node(output, number(1.0), [value]).unwrap()
  }
  @graph.finish_output(output).unwrap()
}

///|
fn mean_numeric_views(
  owner : @lower.BoundPrepared,
  owners : Array[@lower.BoundPrepared],
  graphs : Array[@graph.Completed],
) -> Array[@lifecycle.ProducerView] {
  Array::makei(3, index => {
    @graph.producer_read_view(
      @graph.prepare_producer_read(owner, index, owners[index], graphs[index]).unwrap(),
    ).unwrap()
  })
}

///|
test "graph mean applies exact missing and null numeric policies" {
  let first_owner = mean_numeric_source_owner()
  let second_owner = mean_numeric_source_owner()
  let third_owner = mean_numeric_source_owner()
  let owner = mean_numeric_owner(first_owner, second_owner, third_owner)
  let first = mean_numeric_graph(first_owner, Some(mean_numeric_value("6")))
  let second = mean_numeric_graph(
    second_owner,
    Some(mean_numeric_value("null")),
  )
  let third = mean_numeric_graph(third_owner, None)
  let reads = [
    @graph.prepare_producer_read(owner, 0, first_owner, first).unwrap(),
    @graph.prepare_producer_read(owner, 1, second_owner, second).unwrap(),
    @graph.prepare_producer_read(owner, 2, third_owner, third).unwrap(),
  ]
  let execution = start_mean_views(
    @bounded.control(),
    sequence(owner),
    0,
    reads.map(read => @graph.producer_read_view(read).unwrap()),
    storage_limits(),
    4096L,
    4096,
    fn() { true },
  ).unwrap()
  let completed = finish_mean(execution)
  let storage = @graph.completed_storage(completed).unwrap()
  assert_eq(@storage.node_count(storage), 1)
  assert_eq(
    @value.canonical_scalar_text(
      @storage.node_property(storage, 0, 0).unwrap(),
      10,
    ),
    Some("1"),
  )
  assert_eq(cleanup_mean(execution), Ok(true))
}

///|
test "graph mean distinguishes null exclusion from null failure" {
  let first_owner = mean_numeric_source_owner()
  let second_owner = mean_numeric_source_owner()
  let third_owner = mean_numeric_source_owner()
  let owners = [first_owner, second_owner, third_owner]
  let graphs = [
    mean_numeric_graph(first_owner, Some(mean_numeric_value("6"))),
    mean_numeric_graph(second_owner, Some(mean_numeric_value("null"))),
    mean_numeric_graph(third_owner, None),
  ]
  let exclude_owner = mean_numeric_policy_owner(
    first_owner, second_owner, third_owner, "exclude", "exclude",
  )
  let exclude = start_mean_views(
    @bounded.control(),
    sequence(exclude_owner),
    0,
    mean_numeric_views(exclude_owner, owners, graphs),
    storage_limits(),
    4096L,
    4096,
    fn() { true },
  ).unwrap()
  let completed = finish_mean(exclude)
  let storage = @graph.completed_storage(completed).unwrap()
  assert_eq(
    @value.canonical_scalar_text(
      @storage.node_property(storage, 0, 0).unwrap(),
      10,
    ),
    Some("6"),
  )
  assert_eq(cleanup_mean(exclude), Ok(true))
  let fail_owner = mean_numeric_policy_owner(
    first_owner, second_owner, third_owner, "exclude", "fail",
  )
  let failing = start_mean_views(
    @bounded.control(),
    sequence(fail_owner),
    0,
    mean_numeric_views(fail_owner, owners, graphs),
    storage_limits(),
    4096L,
    4096,
    fn() { true },
  ).unwrap()
  while true {
    match advance_mean(failing, 1).unwrap() {
      MeanContinue(_) => ()
      MeanFailed(MeanPropertyValue, ..) => break
      _ => abort("null-fail mean did not report its property failure")
    }
  }
  assert_eq(cleanup_mean(failing), Ok(true))
}

///|
test "graph mean rejects conflicting exact properties" {
  let first_owner = mean_numeric_source_owner()
  let second_owner = mean_numeric_source_owner()
  let third_owner = mean_numeric_source_owner()
  let owner = mean_exact_owner(first_owner, second_owner, third_owner)
  let graphs = [
    mean_numeric_graph(first_owner, Some(mean_numeric_value("2"))),
    mean_numeric_graph(second_owner, Some(mean_numeric_value("4"))),
    mean_numeric_graph(third_owner, Some(mean_numeric_value("2"))),
  ]
  let execution = start_mean_views(
    @bounded.control(),
    sequence(owner),
    0,
    mean_numeric_views(owner, [first_owner, second_owner, third_owner], graphs),
    storage_limits(),
    4096L,
    4096,
    fn() { true },
  ).unwrap()
  while true {
    match advance_mean(execution, 1).unwrap() {
      MeanContinue(_) => ()
      MeanFailed(MeanPropertyConflict, ..) => break
      _ => abort("conflicting exact mean did not fail")
    }
  }
  assert_eq(cleanup_mean(execution), Ok(true))
}

///|
test "graph mean admits fixed workspace before building state" {
  let first_owner = mean_source_owner()
  let second_owner = mean_source_owner()
  let owner = mean_owner(first_owner, second_owner)
  let first = mean_graph(first_owner, [1.0], [])
  let second = mean_graph(second_owner, [2.0], [])
  let limits = { ..storage_limits(), max_workspace_slots: 2, }
  assert_true(
    start_mean_views(
      @bounded.control(),
      sequence(owner),
      0,
      mean_views(owner, first_owner, second_owner, first, second),
      limits,
      4096L,
      4096,
      fn() { true },
    )
    is Err(MeanWorkspaceLimit),
  )
}

///|
test "graph mean admits merge storage before sorting" {
  let first_owner = mean_source_owner()
  let second_owner = mean_source_owner()
  let owner = mean_owner(first_owner, second_owner)
  let first = mean_graph(first_owner, [2.0, 1.0], [])
  let second = mean_graph(second_owner, [], [])
  let views = mean_views(owner, first_owner, second_owner, first, second)
  let exact = start_mean_views(
    @bounded.control(),
    sequence(owner),
    0,
    views,
    { ..storage_limits(), max_workspace_slots: 11, },
    4096L,
    4096,
    fn() { true },
  ).unwrap()
  let output = finish_mean(exact)
  assert_eq(@storage.node_count(@graph.completed_storage(output).unwrap()), 2)
  assert_eq(cleanup_mean(exact), Ok(true))
  let short = start_mean_views(
    @bounded.control(),
    sequence(owner),
    0,
    views,
    { ..storage_limits(), max_workspace_slots: 10, },
    4096L,
    4096,
    fn() { true },
  ).unwrap()
  while true {
    match advance_mean(short, 1).unwrap() {
      MeanContinue(_) => ()
      MeanFailed(MeanWorkspaceLimit, ..) => break
      _ => abort("one-short mean workspace did not fail")
    }
  }
  assert_eq(cleanup_mean(short), Ok(true))
}

///|
test "graph mean canonical ordering scales below quadratic work" {
  let small = mean_scale_work(32)
  let large = mean_scale_work(64)
  assert_true(large > small * 2L)
  assert_true(large < small * 3L)
}

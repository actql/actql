///|
test "row window lowering retains checked fixed options and authored offset" {
  let owner = expression_pipeline(
    ",{\"row_window\":{\"kind\":\"fixed\",\"time\":\"id\",\"size\":10,\"step\":3,\"offset\":-2}}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.WindowStep(window)) else {
    fail("window step")
  }
  assert_true(physical_equal(@lowering_relation.window_owner(window), owner))
  assert_eq(@lowering_relation.window_step_index(window), 1)
  assert_eq(@lowering_relation.window_input(window), "values_0")
  assert_eq(@lowering_relation.window_kind(window), @window.Fixed)
  assert_eq(
    @schema.reference_name(@lowering_relation.window_time(window)),
    "id",
  )
  let (start, end) = @lowering_relation.window_boundaries(window)
  assert_eq(
    (@schema.reference_name(start), @schema.reference_name(end)),
    ("window_start", "window_end"),
  )
  assert_eq(@lowering_relation.window_size(window), 10L)
  assert_eq(@lowering_relation.window_authored_step(window), Some(3L))
  assert_eq(@lowering_relation.window_effective_step(window), 10L)
  assert_eq(@lowering_relation.window_offset(window), -2L)
  assert_false(@lowering_relation.window_requires_epoch_milliseconds(window))
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_window_node(window, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"window_1\",\"in\":[\"values_0\"],\"op\":\"REL.window.fixed\",\"params\":{\"offset_ms\":-2,\"size_ms\":10,\"time\":\"id\"}}",
  )
}

///|
test "sliding window resolves all parameter milliseconds through its owner" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"size\":{\"type\":\"number\"},\"step\":{\"type\":\"string\",\"format\":\"duration\"},\"offset\":{\"type\":\"number\"}}",
      ),
    ),
    { max_parameters: 3, max_nodes: 20, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"sliding\",\"time\":\"id\",\"size\":{\"$param\":\"size\"},\"step\":{\"$param\":\"step\"},\"offset\":{\"$param\":\"offset\"}}}]",
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  )
  let pipeline = match checked {
    Ok(value) => value
    Err(issue) => fail(@debug.to_string(issue.kind))
  }
  guard @parameter.bind(
      declarations,
      Some(cursor("{\"size\":10,\"step\":\"3ms\",\"offset\":-2}")),
      { max_nodes: 20, max_depth: 10, max_text_bytes: 1000, },
    ).unwrap()
    is Ready(values) else {
    fail("complete bindings")
  }
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(pipeline, limits()).unwrap(),
    Some(values),
    max_parameters=3,
    max_name_bytes=14,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.WindowStep(window)) else {
    fail("window step")
  }
  assert_eq(@lowering_relation.window_kind(window), @window.Sliding)
  assert_eq(@lowering_relation.window_size(window), 10L)
  assert_eq(@lowering_relation.window_authored_step(window), Some(3L))
  assert_eq(@lowering_relation.window_effective_step(window), 3L)
  assert_eq(@lowering_relation.window_offset(window), -2L)
}

///|
test "event window lowering preserves its Carrier and TEA operation" {
  let relation = @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("event_id"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("occurred_at"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=2,
      max_name_bytes=20,
    ).unwrap(),
  )
  let events = @carrier.events(
    match relation {
      @carrier.Relation(rows) => rows
      _ => abort("relation")
    },
    id=@schema.Unqualified("event_id"),
    time=@schema.Unqualified("occurred_at"),
  ).unwrap()
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"window_events\":{\"kind\":\"sliding\",\"size\":10,\"step\":3,\"offset\":-2}}]",
    ),
    [("events", events)],
    None,
    Some(cursor("\"events\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.WindowStep(window)) else {
    fail("window step")
  }
  assert_true(@lowering_relation.window_preserves_events(window))
  assert_eq(
    @lowering_relation.operation(
      @lowering_relation.node_at(@lowering_relation.bound_preparation(owner), 0).unwrap(),
    ),
    "TEA.window.sliding_assign",
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_window_node(window, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"window_0\",\"in\":[\"input_0\"],\"op\":\"TEA.window.sliding_assign\",\"params\":{\"offset_ms\":-2,\"size_ms\":10,\"step_ms\":3,\"time\":\"occurred_at\"}}",
  )
}

///|
test "window lowering enforces cumulative view budgets atomically" {
  let owner = expression_pipeline(
    ",{\"row_window\":{\"kind\":\"fixed\",\"time\":\"id\",\"size\":10,\"step\":3,\"offset\":-2}}",
  )
  let exact = {
    ..sequence_limits(),
    max_bindings: 3,
    max_name_bytes: 24,
    expressions: { ..expression_limits(), max_work: 6, },
  }
  assert_true(@lowering_relation.prepare_sequence(owner, exact) is Ok(_))
  for
    constrained in [
      { ..exact, max_bindings: 2, },
      { ..exact, max_name_bytes: 23, },
      { ..exact, expressions: { ..exact.expressions, max_work: 5, }, },
    ] {
    assert_true(
      @lowering_relation.prepare_sequence(owner, constrained)
      is Err(
        @lowering_relation.WindowFailure(
          1,
          @lowering_relation.WindowBudgetExceeded
        )
      ),
    )
  }
}

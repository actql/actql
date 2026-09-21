///|
fn graft_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"from\":\"left\",\"graft_graph\":{\"with\":\"right\"}}]"),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
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
fn union_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
  exact? : Bool = false,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"from\":\"left\",\"union_graphs\":{" +
        "\"with\":[\"right\",\"left\",\"right\"]" +
        (if exact {
          ",\"merge\":{\"node_properties\":{\"name\":\"exact_equal\"}}"
        } else {
          ""
        }) +
        "}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
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
fn empty_graph_contract() -> @carrier.Carrier {
  let number_contract = @contract.primitive(
    @contract.NumberType,
    nullable=false,
  )
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  @carrier.graph(
    number_contract,
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    label_contract=Some(
      @contract.primitive(@contract.StringType, nullable=true),
    ),
  ).unwrap()
}

///|
fn numeric_graph_contract() -> @carrier.Carrier {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let node = @carrier.rows(
    [(@schema.Unqualified("score"), Some(number))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let edge = @carrier.rows(
    [(@schema.Unqualified("score"), Some(number))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  @carrier.graph(
    number,
    node,
    edge,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
fn numeric_graph_owner() -> @lower.BoundPrepared {
  bind(
    @pipeline.check_carriers(
      cursor("[{\"from\":\"g\",\"normalize_graph\":true}]"),
      [("g", numeric_graph_contract())],
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
fn numeric_structural_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
  operation : String,
  strategy : String,
) -> @lower.BoundPrepared {
  let body = if operation == "union_graphs" {
    "{\"with\":[\"right\"],\"merge\":{\"node_properties\":" +
    "{\"score\":\"" +
    strategy +
    "\"}}}"
  } else {
    "{\"with\":\"right\",\"merge\":{\"node_properties\":" +
    "{\"score\":\"" +
    strategy +
    "\"}}}"
  }
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"from\":\"left\",\"" + operation + "\":" + body + "}]"),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
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
fn numeric_union_list_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
  third : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"from\":\"left\",\"union_graphs\":{" +
        "\"with\":[\"right\",\"third\"],\"merge\":{" +
        "\"node_properties\":{\"score\":\"number_mean\"}}}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "third",
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
fn one_numeric_node_graph(
  owner : @lower.BoundPrepared,
  identity : Double,
  score : Double,
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    2048L,
    fn() { true },
  ).unwrap()
  @graph.append_node(output, number(identity), [number(score)]).unwrap()
  @graph.finish_output(output).unwrap()
}

///|
fn numeric_both_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"from\":\"left\",\"union_graphs\":{" +
        "\"with\":[\"right\"],\"merge\":{" +
        "\"node_properties\":{\"score\":\"number_sum\"}," +
        "\"edge_properties\":{\"score\":\"number_sum\"}}}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
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
fn numeric_edge_graph(
  owner : @lower.BoundPrepared,
  node_score : Double,
  edge_score : Double,
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  @graph.append_node(output, number(1.0), [number(node_score)]).unwrap()
  @graph.append_node(output, number(2.0), [number(node_score)]).unwrap()
  @graph.append_edge(output, number(1.0), number(2.0), None, [
    number(edge_score),
  ]).unwrap()
  @graph.finish_output(output).unwrap()
}

///|
fn set_graph_contract(nullable? : Bool = false) -> @carrier.Carrier {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let item = @contract.primitive(@contract.StringType, nullable=true)
  let tags = @contract.array_contract(item, nullable~, max_items=Some(10L)).unwrap()
  let node = @carrier.rows(
    [(@schema.Unqualified("tags"), Some(tags))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  let edge = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  @carrier.graph(
    number,
    node,
    edge,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
fn set_graph_owner(nullable? : Bool = false) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_carriers(
      cursor("[{\"from\":\"g\",\"normalize_graph\":true}]"),
      [("g", set_graph_contract(nullable~))],
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
fn set_structural_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
  operation : String,
  strategy : String,
) -> @lower.BoundPrepared {
  let body = if operation == "union_graphs" {
    "{\"with\":[\"right\"],\"merge\":{\"node_properties\":" +
    "{\"tags\":\"" +
    strategy +
    "\"}}}"
  } else {
    "{\"with\":\"right\",\"merge\":{\"node_properties\":" +
    "{\"tags\":\"" +
    strategy +
    "\"}}}"
  }
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"from\":\"left\",\"" + operation + "\":" + body + "}]"),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
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
fn set_value(text : String, nullable? : Bool = false) -> @value.CheckedValue {
  let item = @contract.primitive(@contract.StringType, nullable=true)
  let contract = @contract.array_contract(item, nullable~, max_items=Some(10L)).unwrap()
  @value.admit(contract, cursor(text), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
fn one_set_node_graph(
  owner : @lower.BoundPrepared,
  tags : @value.CheckedValue,
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    2048L,
    fn() { true },
  ).unwrap()
  @graph.append_node(output, number(1.0), [tags]).unwrap()
  @graph.finish_output(output).unwrap()
}

///|
fn empty_graph_owner() -> @lower.BoundPrepared {
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
fn subtract_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
  exact? : Bool = false,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"from\":\"left\",\"subtract_graphs\":{\"with\":\"right\"" +
        (if exact {
          ",\"merge\":{\"node_properties\":{\"name\":\"exact_equal\"}," +
          "\"edge_properties\":{\"weight\":\"exact_equal\"}}"
        } else {
          ""
        }) +
        "}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
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
fn empty_graph(
  owner : @lower.BoundPrepared,
  nodes : Array[Double],
  edges : Array[(Double, Double, String)],
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    2048L,
    fn() { true },
  ).unwrap()
  for identity in nodes {
    @graph.append_node(output, number(identity), []).unwrap()
  }
  for (source, target, label) in edges {
    @graph.append_edge(
      output,
      number(source),
      number(target),
      Some(text(label, nullable=true)),
      [],
    ).unwrap()
  }
  @graph.finish_output(output).unwrap()
}

///|
fn reordered_graft_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"from\":\"left\",\"graft_graph\":{\"with\":\"right\"}}]"),
      [
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
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
fn one_node_graph(
  owner : @lower.BoundPrepared,
  identity : Double,
  name : String,
) -> @graph.Completed {
  one_node_graph_with_availability(owner, identity, name, Ref(true))
}

///|
fn one_node_graph_with_availability(
  owner : @lower.BoundPrepared,
  identity : Double,
  name : String,
  available : Ref[Bool],
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    2048L,
    fn() { available.val },
  ).unwrap()
  @graph.append_node(output, number(identity), [text(name)]).unwrap()
  @graph.finish_output(output).unwrap()
}

///|
test "graft observes exact raw input lifetime until output handoff" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = graft_owner(left_owner, right_owner)
  for invalidated in [0, 1] {
    let left_live = Ref(true)
    let right_live = Ref(true)
    let left = one_node_graph_with_availability(
      left_owner, 1.0, "left", left_live,
    )
    let right = one_node_graph_with_availability(
      right_owner, 2.0, "right", right_live,
    )
    let execution = start_graft(
      @bounded.control(),
      sequence(owner),
      0,
      graft_inputs(owner, left_owner, right_owner, left, right),
      storage_limits(),
      4096L,
      fn() { true },
    ).unwrap()
    assert_true(advance_graft(execution, 1).unwrap() is GraftContinue(_))
    if invalidated == 0 {
      left_live.val = false
    } else {
      right_live.val = false
    }
    assert_true(
      advance_graft(execution, 1).unwrap()
      is GraftFailed(GraftInputUnavailable, progress=1L, work=1L),
    )
    assert_eq(cleanup_graft(execution), Ok(true))
  }

  let left_live = Ref(true)
  let right_live = Ref(true)
  let left = one_node_graph_with_availability(
    left_owner, 1.0, "left", left_live,
  )
  let right = one_node_graph_with_availability(
    right_owner, 2.0, "right", right_live,
  )
  let finishing = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(finishing, 2).unwrap() is GraftContinue(progress=2L, work=2L),
  )
  right_live.val = false
  assert_true(
    advance_graft(finishing, 1).unwrap()
    is GraftFailed(GraftInputUnavailable, progress=2L, work=2L),
  )
  assert_eq(cleanup_graft(finishing), Ok(true))

  let left_live = Ref(true)
  let right_live = Ref(true)
  let left = one_node_graph_with_availability(
    left_owner, 1.0, "left", left_live,
  )
  let right = one_node_graph_with_availability(
    right_owner, 2.0, "right", right_live,
  )
  let completed = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  guard advance_graft(completed, 3).unwrap() is GraftComplete(output, ..) else {
    fail("live graft did not complete")
  }
  left_live.val = false
  right_live.val = false
  assert_eq(@storage.node_count(@graph.completed_storage(output).unwrap()), 2)
  assert_eq(cleanup_graft(completed), Ok(true))
}

///|
fn graft_inputs(
  owner : @lower.BoundPrepared,
  left_owner : @lower.BoundPrepared,
  right_owner : @lower.BoundPrepared,
  left : @graph.Completed,
  right : @graph.Completed,
) -> Array[@graph.ProducerRead] {
  [
    @graph.prepare_producer_read(owner, 0, left_owner, left).unwrap(),
    @graph.prepare_producer_read(owner, 1, right_owner, right).unwrap(),
  ]
}

///|
fn union_inputs(
  owner : @lower.BoundPrepared,
  left_owner : @lower.BoundPrepared,
  right_owner : @lower.BoundPrepared,
  left : @graph.Completed,
  right : @graph.Completed,
) -> Array[@graph.ProducerRead] {
  let left_read = @graph.prepare_producer_read(owner, 0, left_owner, left).unwrap()
  let right_read = @graph.prepare_producer_read(owner, 1, right_owner, right).unwrap()
  [left_read, right_read, left_read, right_read]
}

///|
test "graft preserves ordered inputs and collapses equal declarations" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = graft_owner(left_owner, right_owner)
  let left = one_node_graph(left_owner, 1.0, "a")
  let right = one_node_graph(right_owner, 1.0, "a")
  let control = @bounded.control()
  let execution = start_graft(
    control,
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_eq(graft_max_noninterruptible_value_nodes(execution), 401)
  assert_true(
    advance_graft(execution, 1).unwrap() is GraftContinue(progress=1L, work=1L),
  )
  assert_true(
    advance_graft(execution, 1).unwrap() is GraftContinue(progress=2L, work=2L),
  )
  guard advance_graft(execution, 1).unwrap()
    is GraftComplete(completed, progress=2L, work=2L) else {
    fail("completed graft")
  }
  let result = @graph.completed_storage(completed).unwrap()
  assert_eq(@storage.node_count(result), 1)
  assert_eq(@storage.input_row_count(result), 2)
  assert_true(graft_stopped(execution))
  assert_true(graft_cleanup_pending(execution))
  assert_eq(cleanup_graft(execution), Ok(true))

  let repeated_owner = source_owner()
  let repeated = one_node_graph(repeated_owner, 3.0, "shared")
  let repeated_consumer = graft_owner(repeated_owner, repeated_owner)
  let repeated_execution = start_graft(
    @bounded.control(),
    sequence(repeated_consumer),
    0,
    graft_inputs(
      repeated_consumer, repeated_owner, repeated_owner, repeated, repeated,
    ),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  guard advance_graft(repeated_execution, 3).unwrap()
    is GraftComplete(repeated_output, progress=2L, work=2L) else {
    fail("completed repeated-input graft")
  }
  let repeated_result = @graph.completed_storage(repeated_output).unwrap()
  assert_eq(@storage.node_count(repeated_result), 1)
  assert_eq(@storage.input_row_count(repeated_result), 2)
  assert_eq(cleanup_graft(repeated_execution), Ok(true))
}

///|
test "graft consumes exact common Graph views" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = graft_owner(left_owner, right_owner)
  let left = one_node_graph(left_owner, 1.0, "left")
  let right = one_node_graph(right_owner, 2.0, "right")
  let views = graft_inputs(owner, left_owner, right_owner, left, right).map(input => {
    @graph.producer_read_view(input).unwrap()
  })
  let execution = start_graft_views(
    @bounded.control(),
    sequence(owner),
    0,
    views,
    storage_limits(),
    2048L,
    fn() { true },
  ).unwrap()
  guard advance_graft(execution, 1).unwrap() is GraftContinue(_) else {
    fail("first view was not consumed")
  }
  guard advance_graft(execution, 1).unwrap() is GraftContinue(_) else {
    fail("second view was not consumed")
  }
  guard advance_graft(execution, 1).unwrap()
    is GraftComplete(output, progress=2L, work=2L) else {
    fail("view graft did not complete")
  }
  let storage = @graph.completed_storage(output).unwrap()
  assert_eq(@storage.node_count(storage), 2)
  assert_eq(
    @value.canonical_scalar_text(
      @storage.node_property(storage, 0, 0).unwrap(),
      10,
    ),
    Some("left"),
  )
  assert_eq(
    @value.canonical_scalar_text(
      @storage.node_property(storage, 1, 0).unwrap(),
      10,
    ),
    Some("right"),
  )
  assert_eq(cleanup_graft(execution), Ok(true))
}

///|
test "graft binds each operand to its exact positioned input" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = reordered_graft_owner(left_owner, right_owner)
  let left = one_node_graph(left_owner, 1.0, "left")
  let right = one_node_graph(right_owner, 2.0, "right")
  let exact = [
    @graph.prepare_producer_read(owner, 1, left_owner, left).unwrap(),
    @graph.prepare_producer_read(owner, 0, right_owner, right).unwrap(),
  ]
  let control = @bounded.control()
  let execution = start_graft(
    control,
    sequence(owner),
    0,
    exact,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_graft(execution, 1).unwrap() is GraftContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_graft(execution, 1).unwrap() is GraftStopped(_))
  assert_eq(cleanup_graft(execution), Ok(true))

  let wrong = [
    @graph.prepare_producer_read(owner, 0, right_owner, right).unwrap(),
    @graph.prepare_producer_read(owner, 1, left_owner, left).unwrap(),
  ]
  assert_true(
    start_graft(
      @bounded.control(),
      sequence(owner),
      0,
      wrong,
      storage_limits(),
      4096L,
      fn() { true },
    )
    is Err(GraftInputUnavailable),
  )
}

///|
test "graft rejects conflicting payloads without exposing partial output" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = graft_owner(left_owner, right_owner)
  let left = one_node_graph(left_owner, 1.0, "a")
  let right = one_node_graph(right_owner, 1.0, "conflict")
  let execution = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(execution, 2).unwrap()
    is GraftFailed(
      GraftOutput(@graph.Storage(@storage.DuplicateNodeConflict)),
      progress=1L,
      work=1L
    ),
  )
  assert_true(graft_stopped(execution))
  assert_eq(cleanup_graft(execution), Ok(true))
}

///|
test "graft observes cancellation between graph records" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = graft_owner(left_owner, right_owner)
  let left = one_node_graph(left_owner, 1.0, "a")
  let right = one_node_graph(right_owner, 2.0, "b")
  let control = @bounded.control()
  let execution = start_graft(
    control,
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_graft(execution, 1).unwrap() is GraftContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_graft(execution, 1).unwrap()
    is GraftStopped(@bounded.Cancelled, progress=1L, work=1L),
  )
  assert_true(graft_stopped(execution))
  assert_eq(cleanup_graft(execution), Ok(true))
}

///|
test "graft enforces output admission before a second retained node" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = graft_owner(left_owner, right_owner)
  let left = one_node_graph(left_owner, 1.0, "a")
  let right = one_node_graph(right_owner, 2.0, "b")
  let execution = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    { ..storage_limits(), max_nodes: 1, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(execution, 2).unwrap()
    is GraftFailed(
      GraftOutput(@graph.Storage(@storage.NodeLimit)),
      progress=1L,
      work=1L
    ),
  )
  assert_true(graft_stopped(execution))
  assert_eq(cleanup_graft(execution), Ok(true))
}

///|
test "finite-list union enforces output admission at the exact boundary" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = union_owner(left_owner, right_owner)
  let left = one_node_graph(left_owner, 1.0, "a")
  let right = one_node_graph(right_owner, 2.0, "b")
  let rejected = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    union_inputs(owner, left_owner, right_owner, left, right),
    { ..storage_limits(), max_nodes: 1, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(rejected, 4).unwrap()
    is GraftFailed(
      GraftOutput(@graph.Storage(@storage.NodeLimit)),
      progress=1L,
      work=1L
    ),
  )
  assert_eq(cleanup_graft(rejected), Ok(true))

  let admitted = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    union_inputs(owner, left_owner, right_owner, left, right),
    { ..storage_limits(), max_nodes: 2, },
    4096L,
    fn() { true },
  ).unwrap()
  guard advance_graft(admitted, 8).unwrap()
    is GraftComplete(output, progress=4L, work=4L) else {
    fail("finite-list union did not complete at the exact node limit")
  }
  let result = @graph.completed_storage(output).unwrap()
  assert_eq(@storage.node_count(result), 2)
  assert_eq(@storage.input_row_count(result), 4)
  assert_eq(cleanup_graft(admitted), Ok(true))
}

///|
test "finite-list union applies explicit exact equality at every fold" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = union_owner(left_owner, right_owner, exact=true)
  let left = one_node_graph(left_owner, 1.0, "same")
  let right = one_node_graph(right_owner, 1.0, "same")
  let execution = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    union_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  guard advance_graft(execution, 8).unwrap()
    is GraftComplete(output, progress=4L, work=4L) else {
    fail("explicit exact union did not complete")
  }
  let result = @graph.completed_storage(output).unwrap()
  assert_eq(@storage.node_count(result), 1)
  assert_eq(@storage.input_row_count(result), 4)
  assert_eq(cleanup_graft(execution), Ok(true))

  let conflict = one_node_graph(right_owner, 1.0, "different")
  let rejected = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    union_inputs(owner, left_owner, right_owner, left, conflict),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(rejected, 8).unwrap()
    is GraftFailed(GraftPropertyConflict, progress=0L, work=0L),
  )
  assert_eq(cleanup_graft(rejected), Ok(true))
}

///|
test "structural subtraction removes identities and closes endpoints" {
  let left_owner = empty_graph_owner()
  let right_owner = empty_graph_owner()
  let owner = subtract_owner(left_owner, right_owner)
  let left = empty_graph(left_owner, [1.0, 2.0, 3.0], [
    (1.0, 2.0, "a"),
    (2.0, 3.0, "b"),
    (1.0, 3.0, "c"),
  ])
  let right = empty_graph(right_owner, [2.0], [])
  let execution = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let output = match advance_graft(execution, 16).unwrap() {
    GraftComplete(output, progress~, work~) => {
      assert_eq(progress, 6L)
      assert_eq(work, 6L)
      output
    }
    GraftContinue(progress~, work~) =>
      abort(
        "subtraction continued " + progress.to_string() + "/" + work.to_string(),
      )
    GraftFailed(_, progress~, work~) =>
      abort(
        "subtraction failed " + progress.to_string() + "/" + work.to_string(),
      )
    GraftStopped(_, progress~, work~) =>
      abort(
        "subtraction stopped " + progress.to_string() + "/" + work.to_string(),
      )
  }
  let result = @graph.completed_storage(output).unwrap()
  assert_eq(@storage.node_count(result), 2)
  assert_eq(@storage.edge_count(result), 1)
  assert_true(@storage.node_index(result, number(1.0)).unwrap() is Some(_))
  assert_true(@storage.node_index(result, number(2.0)).unwrap() is None)
  assert_true(@storage.node_index(result, number(3.0)).unwrap() is Some(_))
  assert_eq(cleanup_graft(execution), Ok(true))
}

///|
test "structural subtraction retains explicit exact-equal properties" {
  let left_owner = source_owner()
  let right_owner = source_owner()
  let owner = subtract_owner(left_owner, right_owner, exact=true)
  let left = one_node_graph(left_owner, 1.0, "same")
  let right = one_node_graph(right_owner, 1.0, "same")
  let execution = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  guard advance_graft(execution, 4).unwrap()
    is GraftComplete(output, progress=2L, work=2L) else {
    fail("exact-equal subtraction did not complete")
  }
  let result = @graph.completed_storage(output).unwrap()
  assert_eq(@storage.node_count(result), 1)
  assert_eq(
    @value.canonical_scalar_text(
      @storage.node_property(result, 0, 0).unwrap(),
      10,
    ),
    Some("same"),
  )
  assert_eq(cleanup_graft(execution), Ok(true))

  let conflict = one_node_graph(right_owner, 1.0, "different")
  let rejected = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, conflict),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(rejected, 4).unwrap()
    is GraftFailed(GraftPropertyConflict, progress=0L, work=0L),
  )
  assert_eq(cleanup_graft(rejected), Ok(true))
}

///|
test "structural folds apply every finite numeric property strategy" {
  let left_owner = numeric_graph_owner()
  let right_owner = numeric_graph_owner()
  let left = one_numeric_node_graph(left_owner, 1.0, 2.0)
  let right = one_numeric_node_graph(right_owner, 1.0, 4.0)
  for
    (strategy, expected) in [
      ("number_sum", "6"),
      ("number_mean", "3"),
      ("number_min", "2"),
      ("number_max", "4"),
    ] {
    let owner = numeric_structural_owner(
      left_owner, right_owner, "union_graphs", strategy,
    )
    let execution = start_graft(
      @bounded.control(),
      sequence(owner),
      0,
      graft_inputs(owner, left_owner, right_owner, left, right),
      storage_limits(),
      4096L,
      fn() { true },
    ).unwrap()
    guard advance_graft(execution, 4).unwrap()
      is GraftComplete(output, progress=2L, work=2L) else {
      fail("numeric structural union did not complete")
    }
    let result = @graph.completed_storage(output).unwrap()
    assert_eq(@storage.node_count(result), 1)
    assert_eq(@storage.input_row_count(result), 2)
    assert_eq(
      @value.canonical_scalar_text(
        @storage.node_property(result, 0, 0).unwrap(),
        20,
      ),
      Some(expected),
    )
    assert_eq(cleanup_graft(execution), Ok(true))
  }

  let subtract = numeric_structural_owner(
    left_owner, right_owner, "subtract_graphs", "number_sum",
  )
  let execution = start_graft(
    @bounded.control(),
    sequence(subtract),
    0,
    graft_inputs(subtract, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  guard advance_graft(execution, 4).unwrap()
    is GraftComplete(output, progress=2L, work=2L) else {
    fail("numeric structural subtraction did not complete")
  }
  let result = @graph.completed_storage(output).unwrap()
  assert_eq(@storage.node_count(result), 1)
  assert_eq(
    @value.canonical_scalar_text(
      @storage.node_property(result, 0, 0).unwrap(),
      20,
    ),
    Some("6"),
  )
  assert_eq(cleanup_graft(execution), Ok(true))

  let both = numeric_both_owner(left_owner, right_owner)
  let left_graph = numeric_edge_graph(left_owner, 2.0, 5.0)
  let right_graph = numeric_edge_graph(right_owner, 4.0, 7.0)
  let execution = start_graft(
    @bounded.control(),
    sequence(both),
    0,
    graft_inputs(both, left_owner, right_owner, left_graph, right_graph),
    storage_limits(),
    8192L,
    fn() { true },
  ).unwrap()
  guard advance_graft(execution, 8).unwrap()
    is GraftComplete(output, progress=6L, work=6L) else {
    fail("numeric node and edge fold did not complete")
  }
  let result = @graph.completed_storage(output).unwrap()
  assert_eq(@storage.node_count(result), 2)
  assert_eq(@storage.edge_count(result), 1)
  assert_eq(
    @value.canonical_scalar_text(
      @storage.edge_property(result, 0, 0).unwrap(),
      20,
    ),
    Some("12"),
  )
  assert_eq(cleanup_graft(execution), Ok(true))
}

///|
test "finite structural mean folds in authored input order" {
  let left_owner = numeric_graph_owner()
  let right_owner = numeric_graph_owner()
  let third_owner = numeric_graph_owner()
  let owner = numeric_union_list_owner(left_owner, right_owner, third_owner)
  let left = one_numeric_node_graph(left_owner, 1.0, 2.0)
  let right = one_numeric_node_graph(right_owner, 1.0, 4.0)
  let third = one_numeric_node_graph(third_owner, 1.0, 8.0)
  let execution = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    [
      @graph.prepare_producer_read(owner, 0, left_owner, left).unwrap(),
      @graph.prepare_producer_read(owner, 1, right_owner, right).unwrap(),
      @graph.prepare_producer_read(owner, 2, third_owner, third).unwrap(),
    ],
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_eq(graft_max_noninterruptible_value_nodes(execution), 802)
  guard advance_graft(execution, 6).unwrap()
    is GraftComplete(output, progress=3L, work=3L) else {
    fail("finite numeric fold did not complete")
  }
  let result = @graph.completed_storage(output).unwrap()
  assert_eq(
    @value.canonical_scalar_text(
      @storage.node_property(result, 0, 0).unwrap(),
      20,
    ),
    Some("5.5"),
  )
  assert_eq(@storage.input_row_count(result), 3)
  assert_eq(cleanup_graft(execution), Ok(true))
}

///|
test "structural strategies consume exact common Graph views" {
  let left_owner = numeric_graph_owner()
  let right_owner = numeric_graph_owner()
  let left = one_numeric_node_graph(left_owner, 1.0, 2.0)
  let right = one_numeric_node_graph(right_owner, 1.0, 4.0)
  for operation in ["union_graphs", "subtract_graphs"] {
    let owner = numeric_structural_owner(
      left_owner, right_owner, operation, "number_sum",
    )
    let views = graft_inputs(owner, left_owner, right_owner, left, right).map(input => {
      @graph.producer_read_view(input).unwrap()
    })
    let execution = start_graft_views(
      @bounded.control(),
      sequence(owner),
      0,
      views,
      storage_limits(),
      4096L,
      fn() { true },
    ).unwrap()
    guard advance_graft(execution, 4).unwrap()
      is GraftComplete(output, progress=2L, work=2L) else {
      fail("structural view strategy did not complete")
    }
    let result = @graph.completed_storage(output).unwrap()
    assert_eq(@storage.node_count(result), 1)
    assert_eq(@storage.input_row_count(result), 2)
    assert_eq(
      @value.canonical_scalar_text(
        @storage.node_property(result, 0, 0).unwrap(),
        20,
      ),
      Some("6"),
    )
    assert_eq(cleanup_graft(execution), Ok(true))
  }
}

///|
test "structural folds canonicalize typed set strategies" {
  let left_owner = set_graph_owner()
  let right_owner = set_graph_owner()
  let left = one_set_node_graph(
    left_owner,
    set_value("[\"b\",\"a\",null,\"a\"]"),
  )
  let right = one_set_node_graph(right_owner, set_value("[\"c\",null,\"b\"]"))
  for
    (operation, strategy, expected) in [
      ("union_graphs", "set_union", ["null", "a", "b", "c"]),
      ("subtract_graphs", "set_difference", ["a"]),
    ] {
    let owner = set_structural_owner(
      left_owner, right_owner, operation, strategy,
    )
    let execution = start_graft(
      @bounded.control(),
      sequence(owner),
      0,
      graft_inputs(owner, left_owner, right_owner, left, right),
      storage_limits(),
      4096L,
      fn() { true },
    ).unwrap()
    assert_eq(graft_max_noninterruptible_value_nodes(execution), 808)
    guard advance_graft(execution, 4).unwrap()
      is GraftComplete(output, progress=2L, work=2L) else {
      fail("set structural fold did not complete")
    }
    let result = @graph.completed_storage(output).unwrap()
    guard @storage.node_property(result, 0, 0).unwrap().value
      is @value.Array(values) else {
      fail("set result was not an array")
    }
    let actual = @value.elements(values).map(value => {
      match value {
        @value.Null => "null"
        @value.Text(text) => text
        _ => "unexpected"
      }
    })
    assert_eq(actual, expected)
    assert_eq(cleanup_graft(execution), Ok(true))
  }

  let bounded_owner = set_structural_owner(
    left_owner, right_owner, "union_graphs", "set_union",
  )
  let exact = start_graft(
    @bounded.control(),
    sequence(bounded_owner),
    0,
    graft_inputs(bounded_owner, left_owner, right_owner, left, right),
    { ..storage_limits(), max_workspace_slots: 64, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_graft(exact, 4).unwrap() is GraftComplete(_))
  assert_eq(cleanup_graft(exact), Ok(true))

  let one_short = start_graft(
    @bounded.control(),
    sequence(bounded_owner),
    0,
    graft_inputs(bounded_owner, left_owner, right_owner, left, right),
    { ..storage_limits(), max_workspace_slots: 63, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(one_short, 4).unwrap()
    is GraftFailed(GraftWorkspaceLimit, progress=0L, work=0L),
  )
  assert_eq(cleanup_graft(one_short), Ok(true))

  assert_true(
    start_graft(
      @bounded.control(),
      sequence(bounded_owner),
      0,
      graft_inputs(bounded_owner, left_owner, right_owner, left, right),
      { ..storage_limits(), max_value_nodes: 268435456, },
      4096L,
      fn() { true },
    )
    is Err(InvalidGraftLimits),
  )

  let nullable_left_owner = set_graph_owner(nullable=true)
  let nullable_right_owner = set_graph_owner(nullable=true)
  let nullable_left = one_set_node_graph(
    nullable_left_owner,
    set_value("null", nullable=true),
  )
  let nullable_right = one_set_node_graph(
    nullable_right_owner,
    set_value("[\"a\"]", nullable=true),
  )
  let nullable_union = set_structural_owner(
    nullable_left_owner, nullable_right_owner, "union_graphs", "set_union",
  )
  let rejected = start_graft(
    @bounded.control(),
    sequence(nullable_union),
    0,
    graft_inputs(
      nullable_union, nullable_left_owner, nullable_right_owner, nullable_left, nullable_right,
    ),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(rejected, 4).unwrap()
    is GraftFailed(GraftPropertyValue, progress=0L, work=0L),
  )
  assert_eq(cleanup_graft(rejected), Ok(true))
}

///|
test "structural subtraction observes cancellation and exact capacity" {
  let left_owner = empty_graph_owner()
  let right_owner = empty_graph_owner()
  let owner = subtract_owner(left_owner, right_owner)
  let left = empty_graph(left_owner, [1.0, 2.0], [])
  let right = empty_graph(right_owner, [], [])
  let control = @bounded.control()
  let cancelled = start_graft(
    control,
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_graft(cancelled, 1).unwrap() is GraftContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_graft(cancelled, 1).unwrap() is GraftStopped(_))
  assert_eq(cleanup_graft(cancelled), Ok(true))

  let exact = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    { ..storage_limits(), max_nodes: 2, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_graft(exact, 4).unwrap() is GraftComplete(_))
  assert_eq(cleanup_graft(exact), Ok(true))

  let rejected = start_graft(
    @bounded.control(),
    sequence(owner),
    0,
    graft_inputs(owner, left_owner, right_owner, left, right),
    { ..storage_limits(), max_nodes: 1, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_graft(rejected, 4).unwrap()
    is GraftFailed(
      GraftOutput(@graph.Storage(@storage.NodeLimit)),
      progress=1L,
      work=1L
    ),
  )
  assert_eq(cleanup_graft(rejected), Ok(true))
}

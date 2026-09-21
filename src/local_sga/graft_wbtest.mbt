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
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    2048L,
    fn() { true },
  ).unwrap()
  @graph.append_node(output, number(identity), [text(name)]).unwrap()
  @graph.finish_output(output).unwrap()
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
    is GraftFailed(
      GraftOutput(@graph.Storage(@storage.DuplicateNodeConflict)),
      progress=1L,
      work=1L
    ),
  )
  assert_eq(cleanup_graft(rejected), Ok(true))
}

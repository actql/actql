///|
fn graph_contract() -> @carrier.Carrier {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let node = @carrier.rows(
    [
      (
        @schema.Unqualified("name"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  let edge = @carrier.rows(
    [(@schema.Unqualified("weight"), Some(number))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  @carrier.graph(
    number,
    node,
    edge,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    label_contract=Some(
      @contract.primitive(@contract.StringType, nullable=true),
    ),
  ).unwrap()
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="local-sga-normalize.aql",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn bind(checked : @pipeline.CheckedPipeline) -> @lower.BoundPrepared {
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn source_owner() -> @lower.BoundPrepared {
  bind(
    @pipeline.check_carriers(
      cursor("[{\"from\":\"g\",\"normalize_graph\":true}]"),
      [("g", graph_contract())],
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
fn consumer_owner(producer : @lower.BoundPrepared) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"normalize_graph\":true}]"),
      [
        (
          "prior",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(producer)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(cursor("\"prior\"")),
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
fn second_input_consumer_owner(
  first : @lower.BoundPrepared,
  second : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"normalize_graph\":true}]"),
      [
        (
          "first",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(first)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "second",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(second)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(cursor("\"second\"")),
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
fn sequence(owner : @lower.BoundPrepared) -> @lower.PreparedSequence {
  @lower.prepare_sequence(owner, {
    max_steps: 10,
    max_rows: 100,
    max_cells: 1000,
    max_bindings: 100,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  }).unwrap()
}

///|
fn storage_limits() -> @storage.Limits {
  {
    max_input_rows: 10,
    max_nodes: 10,
    max_edges: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn number(value : Double) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.NumberType, nullable=false),
    cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn text(value : String, nullable? : Bool = false) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.StringType, nullable~),
    cursor("\"" + value + "\""),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 100, },
  ).unwrap()
}

///|
fn source_graph(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  @graph.append_node(output, number(1.0), [text("a")]).unwrap()
  @graph.append_node(output, number(2.0), [text("b")]).unwrap()
  @graph.append_edge(
    output,
    number(1.0),
    number(2.0),
    Some(text("knows", nullable=true)),
    [number(3.0)],
  ).unwrap()
  @graph.finish_output(output).unwrap()
}

///|
test "normalize advances in bounded steps and feeds two consumers" {
  let producer = source_owner()
  let source_live = Ref(true)
  let source = source_graph(producer, source_live)
  let owner = consumer_owner(producer)
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  let output_live = Ref(true)
  let control = @bounded.control()
  let execution = start_normalize(
    control,
    sequence(owner),
    0,
    input,
    storage_limits(),
    4096L,
    fn() { output_live.val },
  ).unwrap()
  assert_eq(normalize_max_noninterruptible_value_nodes(execution), 401)
  assert_true(
    advance_normalize(execution, 0) is Err(Execution(@bounded.InvalidQuantum)),
  )
  assert_true(
    advance_normalize(execution, 1).unwrap() is Continue(progress=1L, work=1L),
  )
  assert_true(
    advance_normalize(execution, 1).unwrap() is Continue(progress=2L, work=2L),
  )
  assert_true(
    advance_normalize(execution, 1).unwrap() is Continue(progress=3L, work=3L),
  )
  guard advance_normalize(execution, 1).unwrap()
    is Complete(completed, progress=3L, work=3L) else {
    fail("completed normalized graph")
  }
  assert_true(normalize_stopped(execution))
  assert_true(normalize_cleanup_pending(execution))
  assert_eq(cleanup_normalize(execution), Ok(true))
  source_live.val = false
  assert_true(@graph.completed_available(completed))
  let material = @graph.completed_storage(completed).unwrap()
  assert_eq(@storage.node_count(material), 2)
  assert_eq(@storage.edge_count(material), 1)

  let downstream = consumer_owner(owner)
  let first = @graph.prepare_producer_read(downstream, 0, owner, completed).unwrap()
  let second = @graph.prepare_producer_read(downstream, 0, owner, completed).unwrap()
  assert_false(@graph.producer_read_same(first, second))
  assert_eq(
    @storage.node_count(@graph.producer_read_storage(first).unwrap()),
    2,
  )
  assert_eq(
    @storage.edge_count(@graph.producer_read_storage(second).unwrap()),
    1,
  )
}

///|
test "normalize admits only the exact external operation input" {
  let first_owner = source_owner()
  let second_owner = source_owner()
  let first = source_graph(first_owner, Ref(true))
  let second = source_graph(second_owner, Ref(true))
  let owner = second_input_consumer_owner(first_owner, second_owner)
  let wrong = @graph.prepare_producer_read(owner, 0, first_owner, first).unwrap()
  assert_true(
    start_normalize(
      @bounded.control(),
      sequence(owner),
      0,
      wrong,
      storage_limits(),
      4096L,
      fn() { true },
    )
    is Err(InvalidKernel),
  )
  let exact = @graph.prepare_producer_read(owner, 1, second_owner, second).unwrap()
  let control = @bounded.control()
  let execution = start_normalize(
    control,
    sequence(owner),
    0,
    exact,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_normalize(execution, 1).unwrap() is Continue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_normalize(execution, 1).unwrap() is Stopped(_))
  assert_eq(cleanup_normalize(execution), Ok(true))
}

///|
test "normalize confirms cancellation before reclaiming partial output" {
  let producer = source_owner()
  let source = source_graph(producer, Ref(true))
  let owner = consumer_owner(producer)
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let execution = start_normalize(
    control,
    sequence(owner),
    0,
    input,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_normalize(execution, 1).unwrap() is Continue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_normalize(execution, 1).unwrap()
    is Stopped(@bounded.Cancelled, progress=1L, work=1L),
  )
  assert_true(normalize_stopped(execution))
  assert_true(normalize_cleanup_pending(execution))
  assert_eq(cleanup_normalize(execution), Ok(true))
  assert_false(normalize_cleanup_pending(execution))
}

///|
test "normalize accepts the exact node capacity" {
  let producer = source_owner()
  let source = source_graph(producer, Ref(true))
  let owner = consumer_owner(producer)
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_normalize(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    { ..storage_limits(), max_nodes: 2, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_normalize(execution, 1).unwrap() is Continue(_))
  assert_true(advance_normalize(execution, 1).unwrap() is Continue(_))
  assert_true(advance_normalize(execution, 1).unwrap() is Continue(_))
  guard advance_normalize(execution, 1).unwrap()
    is Complete(completed, progress=3L, work=3L) else {
    fail("exact node capacity must complete")
  }
  assert_eq(
    @storage.node_count(@graph.completed_storage(completed).unwrap()),
    2,
  )
  assert_eq(
    @storage.edge_count(@graph.completed_storage(completed).unwrap()),
    1,
  )
  assert_eq(cleanup_normalize(execution), Ok(true))
}

///|
test "normalize rejects one node less than the required capacity" {
  let producer = source_owner()
  let source = source_graph(producer, Ref(true))
  let owner = consumer_owner(producer)
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_normalize(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    { ..storage_limits(), max_nodes: 1, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_normalize(execution, 1).unwrap() is Continue(_))
  assert_true(
    advance_normalize(execution, 1).unwrap()
    is Failed(Output(@graph.Storage(@storage.NodeLimit)), progress=1L, work=1L),
  )
  assert_true(normalize_stopped(execution))
  assert_true(normalize_cleanup_pending(execution))
  assert_eq(cleanup_normalize(execution), Ok(true))
  assert_false(normalize_cleanup_pending(execution))
}

///|
test "normalize rejects foreign kernels and bounded output overflow" {
  let producer = source_owner()
  let source = source_graph(producer, Ref(true))
  let owner = consumer_owner(producer)
  let input = @graph.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_normalize(
      @bounded.control(),
      sequence(owner),
      1,
      input,
      storage_limits(),
      4096L,
      fn() { true },
    )
    is Err(InvalidKernel),
  )
  let constrained = start_normalize(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    { ..storage_limits(), max_nodes: 1, },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_normalize(constrained, 3).unwrap()
    is Failed(Output(@graph.Storage(@storage.NodeLimit)), progress=1L, work=1L),
  )
  assert_true(normalize_stopped(constrained))
  assert_eq(cleanup_normalize(constrained), Ok(true))
}

///|
fn closure_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 4096,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  ).unwrap()
}

///|
fn empty_capacity(
  p : @pipeline.CheckedPipeline,
) -> @capacity_graph_preflight.ApplicationCoverage {
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let source = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let selected = policy(false)
  let graph = @capacity_graph_preflight.check(p, source, selected, caps()).unwrap()
  let program = @program.check_applications(claims, [], max_work=0).unwrap()
  let sequence = @sequence.check_applications(
    p,
    source,
    selected,
    [],
    max_work=10000,
  ).unwrap()
  @capacity_graph_preflight.check_application_coverage(
    graph,
    program,
    sequence,
    max_work=10000,
  ).unwrap()
}

///|
fn forwarding_pipeline(
  inputs : Array[(String, @pipeline.InputContract)],
) -> @pipeline.CheckedPipeline {
  @pipeline.check_with_evidence(
    closure_cursor("[]"),
    inputs,
    None,
    Some(closure_cursor("\"a\"")),
    {
      max_steps: 0,
      max_work: 100,
      max_text_bytes: 100,
      max_nodes: 100,
      max_tokens: 100,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "capacity closure covers unused and repeated producers with exact owners and cumulative work" {
  let base = fixture_pipeline(false)
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(base, Input(0)).unwrap(),
  )
  let root = forwarding_pipeline([("a", input), ("b", input)])
  let orders = @pipeline.resolve_contextual_closure(
    root,
    max_steps=0,
    max_work=100,
    max_text_bytes=100,
  ).unwrap()
  assert_eq(@pipeline.contextual_closure_count(orders), 3)
  let a = empty_capacity(root)
  let b = empty_capacity(base)
  let entries = [a, b, b]
  let cost = 3 +
    @capacity_graph_preflight.application_coverage_work(a) +
    2 * @capacity_graph_preflight.application_coverage_work(b)
  let checked = @capacity_graph_preflight.check_application_closure(
    orders,
    entries,
    max_work=cost,
  ).unwrap()
  assert_eq(@capacity_graph_preflight.application_closure_work(checked), cost)
  assert_true(
    physical_equal(
      @capacity_graph_preflight.application_closure_orders(checked),
      orders,
    ),
  )
  entries[2] = a
  assert_true(
    physical_equal(
      @capacity_graph_preflight.application_closure_at(checked, 2).unwrap(),
      b,
    ),
  )
  assert_true(
    @capacity_graph_preflight.application_closure_at(checked, -1) is None,
  )
  assert_true(
    @capacity_graph_preflight.application_closure_at(checked, 3) is None,
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [a, b],
      max_work=cost,
    )
    is Err(CoverageCount(expected=3, actual=2)),
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [a, b, b, b],
      max_work=cost,
    )
    is Err(CoverageCount(expected=3, actual=4)),
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [a, b, b],
      max_work=cost - 1,
    )
    is Err(WorkLimit(2)),
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [a, b, b],
      max_work=-1,
    )
    is Err(InvalidLimits),
  )
  let foreign = empty_capacity(fixture_pipeline(false))
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [a, b, foreign],
      max_work=cost,
    )
    is Err(ForeignPipeline(2)),
  )
}

///|
test "capacity closure handles long forwarding ancestry without recursion" {
  let mut p = fixture_pipeline(false)
  let entries = [empty_capacity(p)]
  for _ in 0..<1000 {
    p = forwarding_pipeline([
      (
        "a",
        @pipeline.ProducedInput(@pipeline.produced_input(p, Input(0)).unwrap()),
      ),
    ])
    entries.push(empty_capacity(p))
  }
  let orders = @pipeline.resolve_contextual_closure(
    p,
    max_steps=0,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  let ordered : Array[@capacity_graph_preflight.ApplicationCoverage] = []
  let mut cost = entries.length()
  for i in 0..<entries.length() {
    let entry = entries[entries.length() - 1 - i]
    ordered.push(entry)
    cost += @capacity_graph_preflight.application_coverage_work(entry)
  }
  assert_eq(@pipeline.contextual_closure_count(orders), 1001)
  let result = @capacity_graph_preflight.check_application_closure(
    orders,
    ordered,
    max_work=cost,
  ).unwrap()
  assert_eq(@capacity_graph_preflight.application_closure_work(result), cost)
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      ordered,
      max_work=cost - 1,
    )
    is Err(WorkLimit(1000)),
  )
}

///|
test "source preparation checks SourceView requests before producer membership" {
  let remote = []
  let (stages, wiring, _, _, locals, evidence) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    profile=capacity_profile(false),
  )
  let snapshots = evidence.unwrap()
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=10000000,
    max_text_bytes=10000000,
  ).unwrap()
  let inputs = attach_reconciled_inputs(
    wired,
    snapshots,
    locals,
    sourceviews=Some(remote[0]),
    max_work=10000000,
    max_text_bytes=10000000,
    max_local_input_nodes=100000,
  ).unwrap()
  let selected = bind_capacity_policy(
    inputs,
    @environment.read_capacity(@local_inputs.program_environment(snapshots), {
      max_bytes: 10000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    max_work=10000000,
    max_text_bytes=10000000,
    max_policy_nodes=100,
  ).unwrap()
  let caps : @sourceviews.RequestLimits = {
    max_work: 10000000,
    max_pairs: 1000,
    values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
  }
  // These SourceViews have no keyed lookup joins; stage membership is still
  // checked rather than using a source-only empty outer collection.
  let prepared = prepare_program_sources(
    selected,
    [[], []],
    [[], []],
    caps,
    max_bindings=100,
    max_slots=1000,
  ).unwrap()
  let work = source_producer_work(prepared)
  let requests = source_rows_requests(
    source_policy_rows(
      source_capacity_context(source_producer_capacity(prepared)),
    ),
  )
  assert_true(physical_equal(source_request_inputs(requests), inputs))
  assert_true(
    physical_equal(
      @request_slots.source(source_request_slots(requests)),
      @stages.operations_source(
        @stages.bound_operations(stage_operations(stages)),
      ),
    ),
  )
  assert_true(source_request_stage(requests, 0) is Some(_))
  assert_true(source_request_stage(requests, 1) is Some(_))
  let (_, pairs, nodes, text) = source_request_usage(requests)
  let exact : @sourceviews.RequestLimits = {
    max_work: work,
    max_pairs: pairs,
    values: { ..caps.values, max_nodes: nodes, max_text_bytes: text, },
  }
  assert_true(
    prepare_program_sources(
      selected,
      [[], []],
      [[], []],
      exact,
      max_bindings=100,
      max_slots=1000,
    )
    is Ok(_),
  )
  assert_true(
    prepare_program_sources(
      selected,
      [[], []],
      [[], []],
      { ..exact, max_work: work - 1, },
      max_bindings=100,
      max_slots=1000,
    )
    is Err(_),
  )
  assert_true(
    prepare_program_sources(
      selected,
      [],
      [[], []],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Rows(StageCountMismatch)),
  )
  assert_true(
    prepare_program_sources(
      selected,
      [[], []],
      [[], [(0, 0)]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Producers(JoinCountMismatch(1))),
  )
}

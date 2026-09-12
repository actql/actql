///|
fn prepared_coverage(
  p : @pipeline.CheckedPipeline,
  source : @host.HostSources,
  requests : Array[@capacity_graph_preflight.ConsumerRequest],
) -> @capacity_graph_preflight.ApplicationCoverage raise {
  let caps : @capacity_graph_preflight.PreparationLimits = {
    max_work: 10000,
    max_name_bytes: 1000,
    max_input_work: 1000,
    max_operand_work: 1000,
  }
  let result = @capacity_graph_preflight.prepare_application_coverage(
    p,
    source,
    policy(false),
    requests,
    caps,
  ).unwrap()
  let graph = @capacity_graph_preflight.source_coverage_graph(
    @capacity_graph_preflight.application_coverage_sources(result),
  )
  assert_true(
    physical_equal(@capacity_graph_preflight.checked_pipeline(graph), p),
  )
  assert_true(
    physical_equal(@capacity_graph_preflight.checked_sources(graph), source),
  )
  let exact : @capacity_graph_preflight.PreparationLimits = {
    ..caps,
    max_work: @capacity_graph_preflight.application_coverage_work(result),
    max_name_bytes: @capacity_graph_preflight.usage(graph).1,
  }
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      source,
      policy(false),
      requests,
      exact,
    )
    is Ok(_),
  )
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      source,
      policy(false),
      requests,
      { ..exact, max_work: exact.max_work - 1, },
    )
    is Err(_),
  )
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      source,
      policy(false),
      requests,
      { ..exact, max_work: -1, },
    )
    is Err(InvalidLimits),
  )
  if exact.max_name_bytes > 0 {
    assert_true(
      @capacity_graph_preflight.prepare_application_coverage(
        p,
        source,
        policy(false),
        requests,
        { ..exact, max_name_bytes: exact.max_name_bytes - 1, },
      )
      is Err(Graph(BudgetExceeded)),
    )
  }
  result
}

///|
test "preparation joins graph sequence and join coverage from one source owner" {
  let p = consumer_pipeline(true, joins=true)
  let source = combined_sources(false, joins=true)
  let sequence : @capacity_graph_preflight.ConsumerRequest = Sequence(
    step=0,
    matches=2,
    output=3,
  )
  let joined : @capacity_graph_preflight.ConsumerRequest = Join(
    step=1,
    output=4,
  )
  let result = prepared_coverage(p, source, [sequence, joined])
  let consumer = @capacity_graph_preflight.application_coverage_consumers(
    result,
  )
  let seq = @capacity_graph_preflight.consumer_coverage_sequence(consumer)
  let joins = @capacity_graph_preflight.consumer_coverage_joins(consumer).unwrap()
  assert_true(physical_equal(@sequence.application_sources(seq), source))
  assert_true(physical_equal(@program.join_application_sources(joins), source))
  let caps : @capacity_graph_preflight.PreparationLimits = {
    max_work: 10000,
    max_name_bytes: 1000,
    max_input_work: 1000,
    max_operand_work: 1000,
  }
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      source,
      policy(false),
      [sequence],
      caps,
    )
    is Err(JoinCollection(MissingApplication(1))),
  )
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      source,
      policy(false),
      [joined],
      caps,
    )
    is Err(SequenceCollection(MissingApplication(0))),
  )
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      source,
      policy(false),
      [sequence, sequence, joined],
      caps,
    )
    is Err(SequenceCollection(DuplicateApplication(1))),
  )
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      source,
      policy(false),
      [sequence, Join(step=0, output=4)],
      caps,
    )
    is Err(Join(1, WrongOperation)),
  )
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      source,
      policy(true),
      [sequence, joined],
      caps,
    )
    is Err(_),
  )
  let extra = combined_sources(true, joins=true)
  assert_true(
    @capacity_graph_preflight.prepare_application_coverage(
      p,
      extra,
      policy(false),
      [sequence, Join(step=1, output=5)],
      caps,
    )
    is Err(Coverage(Consumer(UnconsumedLimit(4)))),
  )
}

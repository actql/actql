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
test "preparation retains owned sequence guards and charges their selection" {
  for
    guard_text in [
      ",\"max_matches_per_key\":1", ",\"max_output_rows\":2", ",\"max_matches_per_key\":1,\"max_output_rows\":2",
    ] {
    let p = consumer_pipeline(true, sequence_guards=guard_text)
    let occurrences = @pipeline.collect_author_guards(
      p,
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap()
    let guards = @pipeline.bind_author_guards(
      occurrences,
      None,
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap()
    let sources = combined_sources(false)
    let requests : Array[@capacity_graph_preflight.ConsumerRequest] = [
      Sequence(step=0, matches=2, output=3),
    ]
    let limits : @capacity_graph_preflight.PreparationLimits = {
      max_work: 10000,
      max_name_bytes: 1000,
      max_input_work: 1000,
      max_operand_work: 1000,
    }
    let coverage = @capacity_graph_preflight.prepare_application_coverage(
      p,
      sources,
      policy(false),
      requests,
      limits,
      guards=Some(guards),
    ).unwrap()
    let applications = @capacity_graph_preflight.consumer_coverage_sequence(
      @capacity_graph_preflight.application_coverage_consumers(coverage),
    )
    let selected = @sequence.application_at(applications, 0).unwrap()
    assert_true(
      physical_equal(@sequence.bound_guards(selected).unwrap(), guards),
    )
    for i in 0..<@pipeline.author_guard_count(occurrences) {
      let occurrence = @pipeline.author_guard_at(occurrences, i).unwrap()
      let scope = match @pipeline.author_guard_scope(occurrence) {
        SequenceMatchesPerKey => @sequence.MatchesPerKey
        SequenceOutputRows => @sequence.OutputRows
        _ => fail("unexpected fixture guard")
      }
      assert_eq(@sequence.guard_index(selected, scope), Some(i))
      assert_eq(
        @sequence.guard_value(selected, scope),
        @pipeline.bound_guard_value_at(guards, i),
      )
      assert_eq(@sequence.effective_maximum(selected, scope), 1L)
    }
    let work = @capacity_graph_preflight.application_coverage_work(coverage)
    assert_true(
      @capacity_graph_preflight.prepare_application_coverage(
        p,
        sources,
        policy(false),
        requests,
        { ..limits, max_work: work, },
        guards=Some(guards),
      )
      is Ok(_),
    )
    assert_true(
      @capacity_graph_preflight.prepare_application_coverage(
        p,
        sources,
        policy(false),
        requests,
        { ..limits, max_work: work - 1, },
        guards=Some(guards),
      )
      is Err(_),
    )
    assert_true(
      @capacity_graph_preflight.prepare_application_coverage(
        p,
        sources,
        policy(false),
        requests,
        limits,
      )
      is Err(Sequence(0, UnresolvedAuthorSource(_))),
    )
    // Equal syntax cannot replace the pipeline that owns the occurrences.
    let foreign = consumer_pipeline(true, sequence_guards=guard_text)
    assert_true(
      @capacity_graph_preflight.prepare_application_coverage(
        foreign,
        sources,
        policy(false),
        requests,
        limits,
        guards=Some(guards),
      )
      is Err(ForeignGuardOwner),
    )
  }
}

///|
test "preparation rejects equal but separately bound sequence Parameters" {
  let declarations = @parameter.read_declarations(
    Some(closure_cursor("{\"n\":{\"type\":\"number\",\"default\":2}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let p = consumer_pipeline(
    true,
    parameters=Some(declarations),
    sequence_guards=",\"max_output_rows\":{\"$param\":\"n\"}",
  )
  let caps : @value.Limits = {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  guard @parameter.bind(declarations, None, caps).unwrap() is Ready(values) else {
    fail("expected ready values")
  }
  guard @parameter.bind(declarations, None, caps).unwrap() is Ready(copy) else {
    fail("expected ready values")
  }
  let guards = @pipeline.bind_author_guards(
    @pipeline.collect_author_guards(p, max_work=1000, max_text_bytes=1000).unwrap(),
    Some(values),
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  let sources = combined_sources(false)
  for (bound, accepted) in [(values, true), (copy, false)] {
    let counts = @program.bind_parameters(
      p,
      bound,
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap()
    let result = @capacity_graph_preflight.prepare_application_coverage(
      p,
      sources,
      policy(false),
      [Sequence(step=0, matches=2, output=3)],
      {
        max_work: 10000,
        max_name_bytes: 1000,
        max_input_work: 1000,
        max_operand_work: 1000,
      },
      bindings=Some(counts),
      guards=Some(guards),
    )
    if accepted {
      assert_true(result is Ok(_))
    } else {
      assert_true(result is Err(ForeignGuardBindings))
    }
  }
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

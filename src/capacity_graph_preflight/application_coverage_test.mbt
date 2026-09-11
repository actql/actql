///|
test "combined application coverage shares source and consumer budgets and proof owners" {
  for extra in [false, true] {
    let p = consumer_pipeline(true, joins=true)
    let source = combined_sources(extra, joins=true)
    let selected = policy(false)
    let graph = @capacity_graph_preflight.check(p, source, selected, caps()).unwrap()
    let sequence = sequence_consumers(p, source)
    let claims = @host.source_claims(source)
    let program = @program.check_applications(claims, [], max_work=100).unwrap()
    let limit = @program.check_join_limit(
      p,
      1,
      source,
      program,
      selected,
      if extra {
        5
      } else {
        4
      },
      max_work=100,
    ).unwrap()
    let joined = @program.check_join_applications(
      p,
      source,
      program,
      selected,
      [limit],
      max_work=100,
    ).unwrap()
    let n = @wire.claim_count(@wire.program_claim_arithmetic(claims))
    let work = n + (if extra { 10 } else { 9 })
    let result = @capacity_graph_preflight.check_application_coverage(
      graph,
      program,
      sequence,
      joins=Some(joined),
      max_work=work,
    )
    if extra {
      assert_true(result is Err(Consumer(UnconsumedLimit(4))))
    } else {
      let checked = result.unwrap()
      assert_eq(
        @capacity_graph_preflight.application_coverage_work(checked),
        work,
      )
      let covered_sources = @capacity_graph_preflight.application_coverage_sources(
        checked,
      )
      let covered_consumers = @capacity_graph_preflight.application_coverage_consumers(
        checked,
      )
      assert_true(
        physical_equal(
          @capacity_graph_preflight.source_coverage_program(covered_sources),
          program,
        ),
      )
      assert_true(
        physical_equal(
          @capacity_graph_preflight.consumer_coverage_graph(covered_consumers),
          graph,
        ),
      )
      assert_true(
        physical_equal(
          @capacity_graph_preflight.consumer_coverage_joins(covered_consumers).unwrap(),
          joined,
        ),
      )
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          program,
          sequence,
          joins=Some(joined),
          max_work=work - 1,
        )
        is Err(Consumer(WorkLimit)),
      )
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          program,
          sequence,
          joins=Some(joined),
          max_work=n - 1,
        )
        is Err(Source(WorkLimit)),
      )
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          program,
          sequence,
          joins=Some(joined),
          max_work=-1,
        )
        is Err(InvalidLimits),
      )
      let other_program = @program.check_applications(claims, [], max_work=100).unwrap()
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          other_program,
          sequence,
          joins=Some(joined),
          max_work=work,
        )
        is Err(ForeignProgram),
      )
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          program,
          sequence,
          max_work=work,
        )
        is Err(Consumer(UnconsumedLimit(4))),
      )
    }
  }
}

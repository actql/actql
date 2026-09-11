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
    // With no components ledger, operation coverage also scans both steps.
    let work = n + (if extra { 10 } else { 9 }) + @pipeline.step_count(p)
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
        is Err(MissingJoinApplications(1)),
      )
    }
  }
}

///|
test "empty limit collections cannot hide omitted join applications" {
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
  let program = @program.check_applications(claims, [], max_work=0).unwrap()
  let selected = policy(false)
  let row = @schema.from_object(
    @contract.object_contract(
      [("id", @contract.primitive(NumberType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  ).unwrap()
  for
    body in [
      "[]", "[{\"select\":[\"id\"]}]", "[{\"join\":{\"with\":\"rows\",\"kind\":\"inner\",\"on\":\"id\"}}]",
      "[{\"cross_join\":{\"with\":\"rows\"}}]", "[{\"interval_join\":{\"with\":\"rows\",\"kind\":\"inner\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"id\"}}}]",
    ] {
    let root = @decode.admit(
      @source.parse_json(body, {
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
    let p = @pipeline.check_carriers(
      root,
      [("rows", @carrier.relation(@carrier.typed_rows(row)))],
      None,
      None,
      {
        max_steps: 1,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap()
    let graph = @capacity_graph_preflight.check(p, source, selected, caps()).unwrap()
    let sequence = @sequence.check_applications(
      p,
      source,
      selected,
      [],
      max_work=2,
    ).unwrap()
    let steps = @pipeline.step_count(p)
    let result = @capacity_graph_preflight.check_application_coverage(
      graph,
      program,
      sequence,
      max_work=2 + steps,
    )
    if body == "[]" || body == "[{\"select\":[\"id\"]}]" {
      assert_eq(
        @capacity_graph_preflight.application_coverage_work(result.unwrap()),
        2 + steps,
      )
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          program,
          sequence,
          max_work=1 + steps,
        )
        is Err(Consumer(WorkLimit)),
      )
    } else {
      // The lower-level ledger scan intentionally checks artifacts only.
      assert_true(
        @capacity_graph_preflight.check_consumer_coverage(
          graph,
          sequence,
          max_work=2,
        )
        is Ok(_),
      )
      assert_true(result is Err(MissingJoinApplications(0)))
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          program,
          sequence,
          max_work=0,
        )
        is Err(WorkLimit),
      )
    }
  }
}

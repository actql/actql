///|
fn producer_select(
  p : @pipeline_typing.CheckedPipeline,
  t : @pipeline_typing.Target,
  fields : String,
) -> @relation.CheckedOperation {
  @relation.check(
    Select,
    cursor(fields),
    @pipeline_typing.schema_at(p, t).unwrap(),
    None,
    {
      max_work: 100000,
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_tokens: 1000,
      max_depth: 1000,
    },
  ).unwrap()
}

///|
fn consume_projection(
  input : @pipeline_typing.ProducedInput,
  steps : String,
) -> @pipeline_typing.CheckedPipeline {
  @pipeline_typing.check_with_evidence(
    cursor(steps),
    [("rows", @pipeline_typing.ProducedInput(input))],
    None,
    None,
    limits(),
  ).unwrap()
}

///|
test "projected producers retain origin counts and hidden-field order without extra authored steps" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[" +
      count_values(3, "seed") +
      ",{\"derive\":{\"extra\":{\"literal\":42}}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let projection = producer_select(p, Step(1), "[\"extra\"]")
  let result = @pipeline_typing.project_produced_input(
    p,
    Step(1),
    projection,
    limits(),
  ).unwrap()
  let input = @pipeline_typing.projected_input(result)
  assert_true(physical_equal(@pipeline_typing.producer_pipeline(input), p))
  assert_eq(@pipeline_typing.producer_target(input), Step(1))
  assert_true(
    physical_equal(
      @pipeline_typing.producer_projection(input).unwrap(),
      projection,
    ),
  )
  assert_true(
    @pipeline_typing.producer_projection(
      @pipeline_typing.produced_input(p, Step(1)).unwrap(),
    )
    is None,
  )
  let downstream = consume_projection(input, "[{\"take\":1}]")
  assert_eq(
    @schema.field_count(
      @pipeline_typing.schema_at(downstream, Input(0)).unwrap(),
    ),
    1,
  )
  assert_eq(
    @schema.field_at(
      @pipeline_typing.schema_at(downstream, Input(0)).unwrap(),
      0,
    ).unwrap().name,
    Unqualified("extra"),
  )
  let count = @pipeline_typing.row_count(downstream, Input(0)).unwrap()
  assert_eq(count.upper, 3L)
  assert_true(count.exact)
  assert_true(@pipeline_typing.take_order(downstream, 0) is Some(_))
  let used = @pipeline_typing.projected_input_usage(result)
  let exact = {
    ..limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_tokens: 0,
  }
  assert_true(
    @pipeline_typing.project_produced_input(p, Step(1), projection, exact)
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.project_produced_input(p, Step(1), projection, {
      ..exact,
      max_work: used.work - 1,
    })
    is Err(_),
  )
  let foreign = @pipeline_typing.check_carriers(
    cursor(
      "[" +
      count_values(3, "seed") +
      ",{\"derive\":{\"extra\":{\"literal\":42}}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.project_produced_input(
      foreign,
      Step(1),
      projection,
      limits(),
    )
    is Err({ kind: KeyEvidence(InputContractMismatch), .. }),
  )
  assert_true(
    @pipeline_typing.project_produced_input(p, Step(99), projection, limits())
    is Err(_),
  )
  assert_true(
    @pipeline_typing.project_produced_input(p, Step(1), projection, {
      ..limits(),
      max_work: -1,
    })
    is Err({ kind: InvalidLimits, .. }),
  )
  let other = @relation.check(
    Derive,
    cursor("{}"),
    @pipeline_typing.schema_at(p, Step(1)).unwrap(),
    None,
    {
      max_work: 10000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_tokens: 1000,
    },
  ).unwrap()
  assert_true(
    @pipeline_typing.project_produced_input(p, Step(1), other, limits())
    is Err({ kind: InvalidBody, .. }),
  )
}

///|
test "projected producer window aliases use the existing select transfer law" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}}]",
    ),
    [("rows", window_input())],
    None,
    None,
    limits(),
  ).unwrap()
  let projection = producer_select(
    p,
    Step(0),
    "[{\"a\":\"window_start\"},{\"b\":\"window_start\"},{\"c\":\"window_end\"}]",
  )
  let input = @pipeline_typing.projected_input(
    @pipeline_typing.project_produced_input(p, Step(0), projection, limits()).unwrap(),
  )
  let downstream = consume_projection(
    input, "[{\"drop\":[\"a\"]},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
  )
  assert_eq(
    @pipeline_typing.window_fields(
      @pipeline_typing.window_evidence_at(downstream, Step(1)).unwrap(),
    ),
    (Unqualified("b"), Unqualified("c")),
  )
}

///|
test "projected producer Delta contracts follow retained fields" {
  let p = delta_producer()
  let projection = producer_select(p, Step(1), "[{\"kept\":\"second\"}]")
  let input = @pipeline_typing.projected_input(
    @pipeline_typing.project_produced_input(p, Step(1), projection, limits()).unwrap(),
  )
  let downstream = consume_projection(input, "[]")
  let before = @pipeline_typing.expected_delta_contract(
    p,
    Step(1),
    Unqualified("second"),
  ).unwrap()
  let after = @pipeline_typing.expected_delta_contract(
    downstream,
    Input(0),
    Unqualified("kept"),
  ).unwrap()
  assert_true(physical_equal(before, after))
  assert_true(
    @pipeline_typing.expected_delta_contract(
      downstream,
      Input(0),
      Unqualified("first"),
    )
    is None,
  )
}

///|
test "projected producers transfer candidate keys and score declarations independently" {
  let rows = combined_rows()
  let bound = @pipeline_typing.combine_relation_evidence(
    cursor("null"),
    combined_keys(rows),
    combined_ranking(rows),
  ).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [("rows", @pipeline_typing.RelationEvidenceInput(bound))],
    None,
    None,
    limits(),
  ).unwrap()
  for
    (fields, keyed) in [
      ("[{\"saved_id\":\"id\"},{\"saved_score\":\"score\"}]", true),
      ("[{\"saved_score\":\"score\"}]", false),
    ] {
    let projection = producer_select(p, Input(0), fields)
    let result = @pipeline_typing.project_produced_input(
      p,
      Input(0),
      projection,
      limits(),
    ).unwrap()
    let downstream = consume_projection(
      @pipeline_typing.projected_input(result),
      "[]",
    )
    let keys = @pipeline_typing.candidate_keys(downstream, Input(0)).unwrap()
    assert_eq(@evidence.key_witness_count(keys), if keyed { 1 } else { 0 })
    let ranking = @pipeline_typing.ranking_evidence(downstream, Input(0)).unwrap()
    assert_true(
      @vector.ranking_score_at(ranking, Unqualified("saved_score")) is Some(_),
    )
    assert_true(@vector.ranking_score_at(ranking, Unqualified("score")) is None)
    let u = @pipeline_typing.projected_input_usage(result)
    assert_true(u.text_bytes > 0)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
      max_tokens: 0,
    }
    assert_true(
      @pipeline_typing.project_produced_input(p, Input(0), projection, exact)
      is Ok(_),
    )
    for cap in [{ ..exact, max_text_bytes: u.text_bytes - 1, }] {
      assert_true(
        @pipeline_typing.project_produced_input(p, Input(0), projection, cap)
        is Err(_),
      )
    }
  }
}

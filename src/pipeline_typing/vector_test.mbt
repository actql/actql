///|
test "nearest preserves current corpus and repeated query edges before Relation projection" {
  let source = cursor(
    "[{\"normalize_vectors\":true,\"as\":\"prepared\"},{\"nearest\":{\"queries\":\"prepared\",\"k\":3,\"metric\":\"cosine\"},\"as\":\"ranking\"},{\"select\":[\"query_id\",\"candidate_id\",\"rank\"]}]",
  )
  let inputs = [("v", vector_input())]
  let p = @pipeline_typing.check_carriers(source, inputs, None, None, limits()).unwrap()
  let step = @pipeline_typing.step_at(p, 1).unwrap()
  assert_true(step.operation is Nearest(queries=Step(0), ..))
  let edges = @pipeline_typing.input_occurrences(step)
  assert_eq(edges.length(), 2)
  assert_eq(edges[0].target, Step(0))
  assert_eq(edges[1].target, Step(0))
  assert_eq(edges[0].role, Left)
  assert_eq(edges[1].role, Right)
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 3)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, cap) is Err(_),
    )
  }
  let issue = @pipeline_typing.check_carriers(
    cursor(
      "[{\"nearest\":{\"queries\":\"later\",\"k\":1,\"metric\":\"dot\"}},{\"normalize_vectors\":true,\"as\":\"later\"}]",
    ),
    inputs,
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, UnknownName("later"))
  assert_eq(issue.path, [
    @source.Index(0),
    @source.Key("nearest"),
    @source.Key("queries"),
  ])
}

///|
fn vector_input() -> @carrier.Carrier {
  @carrier.vectors(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("embedding"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
    ids=[Unqualified("id")],
    components=Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
}

///|
test "relation bridge composes with vector normalization scoring and projection" {
  guard vector_input() is @carrier.VectorValue(v) else { abort("vectors") }
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"normalize_vectors\":true},{\"score_vectors\":{\"query\":[1,2],\"metric\":\"cosine\"}},{\"vectors\":true},{\"select\":[\"id\",\"score\"]}]",
    ),
    [("rows", @carrier.relation(@carrier.vector_records(v)))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 2)
  assert_true(
    @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("id"),
    ).unwrap().shape
    is Number,
  )
}

///|
test "vector checking connects branches and explicit relation projection" {
  let body = cursor(
    "[{\"normalize_vectors\":true,\"as\":\"unit\"},{\"score_vectors\":{\"query\":[1,2],\"metric\":\"dot\"}},{\"vectors\":true},{\"select\":[\"id\",\"score\"]},{\"score_vectors\":{\"query\":[2,1],\"metric\":\"l2\"},\"from\":\"unit\",\"as\":\"other\"},{\"vectors\":true}]",
  )
  let p = @pipeline_typing.check_carriers(
    body,
    [("input", vector_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.step_at(p, 0).unwrap().operation is Vector(_))
  assert_eq(
    @pipeline_typing.input_occurrences(@pipeline_typing.step_at(p, 4).unwrap())[0].target,
    Step(0),
  )
  assert_eq(@pipeline_typing.lookup(p, "other"), Some(Step(4)))
  let score = @schema.lookup(
    @pipeline_typing.output_schema(p).unwrap(),
    Unqualified("score"),
  ).unwrap()
  assert_true(score.shape is Number && !score.nullable)
  let used = @pipeline_typing.usage(p)
  let cap = limits()
  let exact : @pipeline_typing.Limits = {
    ..cap,
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(
      body,
      [("input", vector_input())],
      None,
      None,
      exact,
    )
    is Ok(_),
  )
  for
    caps in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        body,
        [("input", vector_input())],
        None,
        None,
        caps,
      )
      is Err(_),
    )
  }
}

///|
test "vector pipeline preserves query diagnostics and rejects wrong carriers" {
  let issue = @pipeline_typing.check_carriers(
    cursor("[{\"score_vectors\":{\"query\":[1],\"metric\":\"dot\"}}]"),
    [("input", vector_input())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.path, [
    @source.Index(0),
    @source.Key("score_vectors"),
    @source.Key("query"),
  ])
  assert_true(issue.kind is Vector(DimensionMismatch(2.0, 1.0)))
  let wrong = @pipeline_typing.check_carriers(
    cursor("[{\"normalize_vectors\":true}]"),
    [("input", event_input())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_true(wrong.kind is Vector(WrongCarrier(EventsKind)))
}

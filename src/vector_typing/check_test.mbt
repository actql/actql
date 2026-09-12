///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 1000,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 1000,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn limits() -> @vector_typing.Limits {
  {
    max_work: 10000,
    max_nodes: 10000,
    max_depth: 1000,
    max_text_bytes: 100000,
  }
}

///|
test "parameter queries retain binding obligations and use only declaration dimensions" {
  for
    declaration in [
      "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"length\":2}", "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1]}",
    ] {
    let ds = @parameter.read_declarations(
      Some(cursor("{\"q\":" + declaration + "}")),
      {
        max_parameters: 10,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      },
    ).unwrap()
    let checked = @vector_typing.check(
      ScoreVectors,
      cursor("{\"query\":{\"$param\":\"q\"},\"metric\":\"dot\"}"),
      vectors(),
      Some(ds),
      limits(),
    ).unwrap()
    let query = @vector_typing.query(checked).unwrap()
    assert_eq(@vector_typing.query_parameter(query), Some("q"))
    assert_true(@vector_typing.query_values(query) is None)
    assert_true(
      indexed_obligation_copy(
        @vector_typing.pending_validations(checked),
        @vector_typing.pending_validation_count(checked),
        i => @vector_typing.pending_validation_at(checked, i),
        (a, b) => a == b,
      ).contains(BindQuery("q")),
    )
    assert_true(
      indexed_obligation_copy(
        @vector_typing.pending_validations(checked),
        @vector_typing.pending_validation_count(checked),
        i => @vector_typing.pending_validation_at(checked, i),
        (a, b) => a == b,
      ).contains(MatchDimensions),
    )
  }
  for
    declaration in [
      "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"length\":3}", "{\"type\":\"array\",\"items\":{\"type\":\"number\",\"nullable\":true}}",
      "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"nullable\":true}", "{\"type\":\"array\",\"items\":{\"type\":\"string\"}}",
      "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"max_items\":0}",
    ] {
    let ds = @parameter.read_declarations(
      Some(cursor("{\"q\":" + declaration + "}")),
      {
        max_parameters: 10,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      },
    ).unwrap()
    let issue = @vector_typing.check(
      ScoreVectors,
      cursor("{\"query\":{\"$param\":\"q\"},\"metric\":\"dot\"}"),
      vectors(),
      Some(ds),
      limits(),
    ).unwrap_err()
    assert_eq(issue.path, [@source.Key("query")])
    assert_true(
      issue.kind is (IncompatibleParameter("q") | DimensionMismatch(2.0, 3.0)),
    )
  }
  assert_eq(
    @vector_typing.check(
      ScoreVectors,
      cursor("{\"query\":{\"$param\":\"missing\"},\"metric\":\"dot\"}"),
      vectors(),
      None,
      limits(),
    ).unwrap_err().kind,
    @vector_typing.IssueKind::UnknownParameter("missing"),
  )
}

///|
fn vectors(
  extra_score? : Bool = false,
  open? : Bool = false,
) -> @carrier.Carrier {
  let fields : Array[(@row.FieldName, @contract.Contract?)] = [
    (Unqualified("id"), Some(@contract.primitive(NumberType, nullable=false))),
    (
      Unqualified("embedding"),
      Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
    ),
    (Unqualified("payload"), None),
  ]
  if extra_score {
    fields.push(
      (
        Unqualified("score"),
        Some(@contract.primitive(StringType, nullable=false)),
      ),
    )
  }
  let rows = @carrier.rows(
    fields,
    field_set=if open { Open } else { Closed },
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
  @carrier.vectors(
    rows,
    ids=[Unqualified("id")],
    components=Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
}

///|
test "normalization preserves carrier knowledge without claiming evaluated values" {
  for input in [vectors(), @carrier.unknown_carrier(VectorsKind)] {
    let checked = @vector_typing.check(
      NormalizeVectors,
      cursor("true"),
      input,
      None,
      limits(),
    ).unwrap()
    assert_eq(
      @carrier.kind(@vector_typing.output(checked)),
      @carrier.VectorsKind,
    )
    assert_true(
      indexed_obligation_copy(
        @vector_typing.pending_validations(checked),
        @vector_typing.pending_validation_count(checked),
        i => @vector_typing.pending_validation_at(checked, i),
        (a, b) => a == b,
      ).contains(NormalizeArithmetic),
    )
    assert_true(@vector_typing.query(checked) is None)
    assert_true(@vector_typing.metric(checked) is None)
  }
  assert_true(
    @vector_typing.check(
      NormalizeVectors,
      cursor("false"),
      vectors(),
      None,
      limits(),
    )
    is Err({ kind: InvalidBody, .. }),
  )
  assert_true(
    @vector_typing.check(
      NormalizeVectors,
      cursor("true"),
      @carrier.unknown_carrier(GraphKind),
      None,
      limits(),
    )
    is Err({ kind: WrongCarrier(GraphKind), .. }),
  )
}

///|
test "scoring preserves typed roles and partial payload knowledge and owns query arrays" {
  for metric in ["cosine", "dot", "l2"] {
    let checked = @vector_typing.check(
      ScoreVectors,
      cursor("{\"query\":[1,2],\"metric\":\"" + metric + "\"}"),
      vectors(),
      None,
      limits(),
    ).unwrap()
    guard @vector_typing.output(checked) is @carrier.VectorValue(v) else {
      abort("expected vectors")
    }
    assert_eq(@carrier.vector_dimensions(v), 2.0)
    assert_eq(@carrier.vector_components(v).name, @row.Unqualified("embedding"))
    assert_eq(@carrier.vector_identities(v)[0].name, @row.Unqualified("id"))
    let rows = @carrier.vector_records(v)
    assert_true(
      @carrier.lookup(rows, Unqualified("payload"))
      is Present({ contract: None, .. }),
    )
    assert_true(
      @carrier.lookup(rows, Unqualified("score"))
      is Present({ contract: Some({ shape: Number, nullable: false, }), .. }),
    )
    let query = @vector_typing.query(checked).unwrap()
    assert_eq(@vector_typing.query_dimensions(query), Some(2.0))
    let values = @vector_typing.query_values(query).unwrap()
    values[0] = 99.0
    assert_eq(@vector_typing.query_values(query).unwrap()[0], 1.0)
    let pending = indexed_obligation_copy(
      @vector_typing.pending_validations(checked),
      @vector_typing.pending_validation_count(checked),
      i => @vector_typing.pending_validation_at(checked, i),
      (a, b) => a == b,
    )
    assert_true(pending.contains(ScoreOrder))
    pending.clear()
    assert_true(
      indexed_obligation_copy(
        @vector_typing.pending_validations(checked),
        @vector_typing.pending_validation_count(checked),
        i => @vector_typing.pending_validation_at(checked, i),
        (a, b) => a == b,
      ).contains(ScoreArithmetic),
    )
  }
}

///|
test "query errors retain paths and unknown output knowledge cannot prove a fresh score" {
  let source = cursor("{\"query\":[1],\"metric\":\"dot\"}")
  let issue = @vector_typing.check(
    ScoreVectors,
    source,
    vectors(),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, @vector_typing.IssueKind::DimensionMismatch(2.0, 1.0))
  assert_eq(issue.path, [@source.Key("query")])
  for
    body in [
      "{\"query\":[],\"metric\":\"dot\"}", "{\"query\":[1,null],\"metric\":\"dot\"}",
      "{\"query\":[1,2],\"metric\":\"unknown\"}", "{\"query\":[1,2],\"metric\":\"dot\",\"extra\":true}",
    ] {
    assert_true(
      @vector_typing.check(
        ScoreVectors,
        cursor(body),
        vectors(),
        None,
        limits(),
      )
      is Err(_),
    )
  }
  let source = cursor("{\"query\":[1,2],\"metric\":\"dot\"}")
  assert_eq(
    @vector_typing.check(
      ScoreVectors,
      source,
      vectors(extra_score=true),
      None,
      limits(),
    ).unwrap_err().kind,
    @vector_typing.IssueKind::OutputCollision("score"),
  )
  for input in [vectors(open=true), @carrier.unknown_carrier(VectorsKind)] {
    assert_eq(
      @vector_typing.check(ScoreVectors, source, input, None, limits()).unwrap_err().kind,
      @vector_typing.IssueKind::UnknownOutputFields,
    )
  }
}

///|
test "reported budgets are exact and each exhausted budget rejects" {
  let source = cursor("{\"query\":[1,2],\"metric\":\"dot\"}")
  let usage = @vector_typing.usage(
    @vector_typing.check(ScoreVectors, source, vectors(), None, limits()).unwrap(),
  )
  let exact : @vector_typing.Limits = {
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
    max_depth: 2,
  }
  assert_true(
    @vector_typing.check(ScoreVectors, source, vectors(), None, exact) is Ok(_),
  )
  let caps : Array[@vector_typing.Limits] = [
    { ..exact, max_work: exact.max_work - 1, },
    { ..exact, max_nodes: exact.max_nodes - 1, },
    { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    { ..exact, max_depth: 1, },
  ]
  for cap in caps {
    assert_eq(
      @vector_typing.check(ScoreVectors, source, vectors(), None, cap).unwrap_err().kind,
      @vector_typing.IssueKind::BudgetExceeded,
    )
  }
}

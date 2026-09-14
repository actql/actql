///|
test "multiple score assertions retain distinct ownership through ordered copies and aliases" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("a"), Some(number)), (Unqualified("b"), Some(number))],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=2,
    ).unwrap(),
  )
  let source = cursor(
    "{\"a\":{\"domain\":\"A\",\"normalization\":\"N\",\"range\":[0,1]},\"b\":{\"domain\":\"B\",\"normalization\":\"N\",\"range\":[1,2]}}",
  )
  let checked = @vector_typing.declare_ranking_scores(source, rows, limits()).unwrap()
  // The map has 13 nodes; independently admitted declarations have 6 each.
  assert_eq(checked.usage.nodes, 25)
  assert_eq(checked.usage.work, 31)
  let exact = {
    ..limits(),
    max_work: checked.usage.work,
    max_nodes: checked.usage.nodes,
    max_text_bytes: checked.usage.text_bytes,
  }
  assert_true(
    @vector_typing.declare_ranking_scores(source, rows, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      { ..exact, max_depth: 2, },
    ] {
    assert_true(
      @vector_typing.declare_ranking_scores(source, rows, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  let a = @vector_typing.ranking_score_at(checked.input, Unqualified("a")).unwrap()
  let b = @vector_typing.ranking_score_at(checked.input, Unqualified("b")).unwrap()
  assert_false(physical_equal(a, b))
  assert_true(
    physical_equal(
      @vector_typing.declared_score_records(a),
      @vector_typing.declared_score_records(b),
    ),
  )
  assert_true(@vector_typing.ranking_score_declaration(checked.input) is None)
  let mut input = checked.input
  for
    (operation, body) in [
      (@relation.Derive, "[{\"saved\":\"a\"},{\"a\":\"b\"},{\"b\":\"saved\"}]"),
      (@relation.Select, "[{\"x\":\"a\"},{\"y\":\"a\"},\"b\"]"),
      (@relation.Drop, "[\"x\"]"),
    ] {
    let op = @relation.check(
      operation,
      cursor(body),
      @carrier.complete_schema(
        @carrier.relation_rows(@vector_typing.ranking_input_carrier(input)).unwrap(),
      ).unwrap(),
      None,
      {
        max_work: 1000,
        max_nodes: 1000,
        max_text_bytes: 1000,
        max_tokens: 1000,
        max_depth: 10,
      },
    ).unwrap()
    input = @vector_typing.transfer_ranking_unary(input, op, limits()).unwrap().input
  }
  assert_true(
    physical_equal(
      @vector_typing.ranking_score_at(input, Unqualified("y")).unwrap(),
      b,
    ),
  )
  assert_true(
    physical_equal(
      @vector_typing.ranking_score_at(input, Unqualified("b")).unwrap(),
      a,
    ),
  )
  assert_true(@vector_typing.ranking_score_at(input, Unqualified("x")) is None)
  let op = @relation.check(
    @relation.Drop,
    cursor("[\"b\"]"),
    @carrier.complete_schema(
      @carrier.relation_rows(@vector_typing.ranking_input_carrier(input)).unwrap(),
    ).unwrap(),
    None,
    {
      max_work: 1000,
      max_nodes: 1000,
      max_text_bytes: 1000,
      max_tokens: 1000,
      max_depth: 10,
    },
  ).unwrap()
  let transferred = @vector_typing.transfer_ranking_unary(input, op, limits()).unwrap()
  assert_true(
    physical_equal(
      @vector_typing.ranking_score_declaration(transferred.input).unwrap(),
      b,
    ),
  )
  assert_true(
    physical_equal(
      @vector_typing.ranking_score_at(checked.input, Unqualified("a")).unwrap(),
      a,
    ),
  )
}

///|
test "score map admission does not return a successful prefix" {
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("a"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=1,
    ).unwrap(),
  )
  let invalid = cursor(
    "{\"a\":{\"domain\":\"A\",\"normalization\":\"N\",\"range\":[0,1]},\"missing\":{\"domain\":\"B\",\"normalization\":\"N\",\"range\":[1,2]}}",
  )
  assert_true(
    @vector_typing.declare_ranking_scores(invalid, rows, limits())
    is Err({ kind: InvalidRankingField(Unqualified("missing")), .. }),
  )
  let empty = @vector_typing.declare_ranking_scores(
    cursor("{}"),
    rows,
    limits(),
  ).unwrap()
  assert_true(@vector_typing.ranking_score_declaration(empty.input) is None)
  assert_eq(empty.usage.nodes, 1)
}

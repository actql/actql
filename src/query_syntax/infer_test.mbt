///|
test "INFER preserves explicit input, key, KEEP and result roles" {
  let query = parse_query(
    "FROM tickets AS t |> INFER `model-task:risk.v1` ITEM KEY (t.id, tenant) INPUT (text = t.body, weight = 1 + @p) KEEP (t.id AS ticket, t.*, *) AS assessment",
    query_limits(),
  ).unwrap()
  match operation_at(query, 0) {
    Some(Infer(clause)) => {
      assert_eq(clause.contract.value, "model-task:risk.v1")
      assert_true(clause.contract.quoted)
      assert_eq(clause.keys.length(), 2)
      assert_eq(clause.keys[0].map(part => part.value), ["t", "id"])
      assert_eq(clause.inputs.length(), 2)
      assert_eq(clause.inputs[0].0.value, "text")
      assert_eq(clause.keep.length(), 3)
      assert_eq(clause.keep[0].name.unwrap().value, "ticket")
      assert_true(clause.keep[1].wildcard)
      assert_eq(clause.keep[1].path[0].value, "t")
      assert_true(clause.keep[2].path.is_empty())
      assert_eq(clause.name.value, "assessment")
    }
    _ => fail("INFER is a distinct operation")
  }
  let empty = parse_query(
    "FROM tickets |> INFER constant ITEM KEY (id) INPUT () AS assessment",
    query_limits(),
  ).unwrap()
  match operation_at(empty, 0) {
    Some(Infer(clause)) => {
      assert_true(clause.inputs.is_empty())
      assert_true(clause.keep.is_empty())
    }
    _ => fail("empty closed input is checked against the ModelTask")
  }
}

///|
test "INFER clauses are mandatory and KEEP is reference-only" {
  for
    text in [
      "FROM t |> INFER score INPUT (text = body) AS assessment", "FROM t |> INFER score ITEM KEY () INPUT () AS assessment",
      "FROM t |> INFER score ITEM KEY (id) AS assessment", "FROM t |> INFER score ITEM KEY (id) INPUT ()",
      "FROM t |> INFER score ITEM KEY (id) INPUT () KEEP () AS assessment", "FROM t |> INFER score ITEM KEY (id) INPUT () KEEP (id + 1 AS n) AS assessment",
      "FROM t |> INFER score ITEM KEY (id) INPUT () KEEP (* AS all) AS assessment",
      "WITH c AS (SELECT id FROM t |> INFER score ITEM KEY (id) INPUT () AS a) SELECT id FROM c",
    ] {
    match parse_query(text, query_limits(), source_path="infer.pipe") {
      Err({ span: Some(span), .. }) => assert_eq(span.source_path, "infer.pipe")
      _ => fail(text)
    }
  }
  assert_true(
    parse_query(
      "FROM t |> INFER score ITEM KEY (id) INPUT (text = body) KEEP (id, body) AS assessment",
      { ..query_limits(), max_syntax_nodes: 2, },
    )
    is Err(_),
  )
}

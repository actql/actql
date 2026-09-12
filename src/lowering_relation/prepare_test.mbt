///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 100000, max_nodes: 10000, max_depth: 4000, },
      source_path="lowering-test.aql",
    ).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 4000,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn checked(tail : String) -> @pipeline.CheckedPipeline {
  @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"}" +
      tail +
      "]",
    ),
    [],
    None,
    None,
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 4000,
    },
  ).unwrap()
}

///|
fn limits() -> @lowering_relation.Limits {
  {
    max_nodes: 100,
    max_references: 100,
    max_work: 1000,
    max_identifier_bytes: 1000,
  }
}

///|
test "fixed preparation vector retains no-op and branch target" {
  let p = checked(
    ",{\"derive\":{},\"as\":\"identity\"},{\"from\":\"seed\",\"select\":[\"id\"]}",
  )
  let prepared = @lowering_relation.prepare(p, limits()).unwrap()
  assert_eq(@lowering_relation.node_count(prepared), 3)
  let expected = [
    ("values_0", "REL.values", []),
    ("derive_1", "REL.derive", ["values_0"]),
    ("select_2", "REL.select", ["values_0"]),
  ]
  for i = 0; i < expected.length(); i = i + 1 {
    let node = @lowering_relation.node_at(prepared, i).unwrap()
    let (id, op, refs) = expected[i]
    assert_eq(@lowering_relation.node_id(node), id)
    assert_eq(@lowering_relation.operation(node), op)
    assert_eq(@lowering_relation.input_ids(node), refs)
    assert_eq(
      @decode.cursor_span(@lowering_relation.source(node)),
      @decode.cursor_span(@pipeline.step_at(p, i).unwrap().source),
    )
  }
  assert_eq(@lowering_relation.usage(prepared), {
    nodes: 3,
    references: 2,
    work: 5,
    identifier_bytes: 24,
  })
}

///|
test "returned references cannot mutate prepared wiring" {
  let p = @lowering_relation.prepare(
    checked(",{\"select\":[\"id\"]}"),
    limits(),
  ).unwrap()
  let n = @lowering_relation.node_at(p, 1).unwrap()
  let refs = @lowering_relation.input_ids(n)
  refs[0] = "foreign"
  refs.push("extra")
  assert_eq(@lowering_relation.input_ids(n), ["values_0"])
}

///|
test "external input alias never collides with generated node ids" {
  let schema = @pipeline.schema_at(checked(""), Step(0)).unwrap()
  let p = @pipeline.check(
    cursor("[{\"select\":[\"id\"]}]"),
    [("select_0", schema)],
    None,
    Some(cursor("\"select_0\"")),
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let prepared = @lowering_relation.prepare(p, limits()).unwrap()
  let node = @lowering_relation.node_at(prepared, 0).unwrap()
  assert_eq(@lowering_relation.input_id(prepared, 0), Some("input_0"))
  assert_eq(@lowering_relation.node_id(node), "select_0")
  assert_eq(@lowering_relation.input_ids(node), ["input_0"])
  assert_eq(
    @pipeline.lookup(@lowering_relation.pipeline(prepared), "select_0"),
    Some(Input(0)),
  )
}

///|
test "preparation budgets enforce exact boundaries" {
  let p = checked(",{\"select\":[\"id\"]}")
  let exact : @lowering_relation.Limits = {
    max_nodes: 2,
    max_references: 1,
    max_work: 3,
    max_identifier_bytes: 16,
  }
  assert_true(@lowering_relation.prepare(p, exact) is Ok(_))
  for
    constrained in [
      { ..exact, max_nodes: 1, },
      { ..exact, max_references: 0, },
      { ..exact, max_work: 2, },
      { ..exact, max_identifier_bytes: 15, },
    ] {
    guard @lowering_relation.prepare(p, constrained) is Err(issue) else {
      fail("expected budget failure")
    }
    assert_eq(issue.kind, @lowering_relation.BudgetExceeded)
  }
  guard @lowering_relation.prepare(p, { ..exact, max_work: -1, }) is Err(issue) else {
    fail("expected invalid limits")
  }
  assert_eq(issue.kind, @lowering_relation.InvalidLimits)
}

///|
/// Implementation coverage test, not a language rejection requirement.
test "unimplemented later operation never returns a partial preparation" {
  let p = checked(",{\"select\":[\"id\"]},{\"distinct\":true}")
  guard @lowering_relation.prepare(p, limits()) is Err(issue) else {
    fail("distinct has no lowering handler yet")
  }
  assert_eq(issue.kind, @lowering_relation.OperationNotImplemented)
  assert_eq(
    @decode.cursor_span(issue.source),
    @decode.cursor_span(@pipeline.step_at(p, 2).unwrap().source),
  )
}

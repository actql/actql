///|
fn source() -> @decode.Cursor {
  @decode.admit(
    @source.parse_json("null", {
      max_input_bytes: 4,
      max_nodes: 1,
      max_depth: 0,
    }).unwrap(),
    {
      max_nodes: 1,
      max_depth: 0,
      max_string_bytes: 0,
      max_total_string_bytes: 0,
    },
  ).unwrap()
}

///|
fn schema() -> @schema.Schema {
  @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
}

///|
test "policy planning preserves supplied lineage without certifying its ownership" {
  let s = source()
  let schema = schema()
  let inherited = decide(
    s,
    schema,
    schema,
    ["id"],
    None,
    None,
    Some(7),
    max_work=1,
    max_text_bytes=0,
  ).unwrap()
  assert_eq(inherited.strategy, Inherited)
  assert_eq(inherited.inherited, Some(7))
  assert_eq(inherited.terms.length(), 0)
  let term : AuthoredTerm = {
    field: "id",
    direction: Desc,
    nulls: Last,
    source: s,
  }
  let authored = decide(
    s,
    schema,
    schema,
    ["id"],
    Some([term]),
    None,
    Some(7),
    max_work=100,
    max_text_bytes=100,
  ).unwrap()
  assert_eq(authored.strategy, Authored)
  assert_eq(authored.inherited, Some(7))
  assert_eq(authored.terms[0].direction, Desc)
  let absent : Int? = None
  assert_true(
    decide(
      s,
      schema,
      schema,
      ["id"],
      Some([term]),
      None,
      absent,
      max_work=100,
      max_text_bytes=100,
    )
    is Err({ kind: UnresolvedOrder, .. }),
  )
}

///|
test "policy fallback preserves exact budget boundaries and rejects missing fields" {
  let s = source()
  let schema = schema()
  let absent : Int? = None
  let p = decide(
    s,
    schema,
    schema,
    ["id"],
    None,
    None,
    absent,
    max_work=100,
    max_text_bytes=100,
  ).unwrap()
  assert_eq(p.strategy, ProjectedFields)
  assert_eq(p.terms[0].field, @schema.Unqualified("id"))
  assert_true(
    decide(
      s,
      schema,
      schema,
      ["id"],
      None,
      None,
      absent,
      max_work=p.work,
      max_text_bytes=p.text_bytes,
    )
    is Ok(_),
  )
  assert_true(
    decide(
      s,
      schema,
      schema,
      ["id"],
      None,
      None,
      absent,
      max_work=p.work - 1,
      max_text_bytes=p.text_bytes,
    )
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    decide(
      s,
      schema,
      schema,
      ["id"],
      None,
      None,
      absent,
      max_work=p.work,
      max_text_bytes=p.text_bytes - 1,
    )
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    decide(
      s,
      schema,
      schema,
      ["missing"],
      None,
      None,
      absent,
      max_work=100,
      max_text_bytes=100,
    )
    is Err({ kind: InvalidInput, .. }),
  )
  let term : AuthoredTerm = {
    field: "missing",
    direction: Asc,
    nulls: Last,
    source: s,
  }
  assert_true(
    decide(
      s,
      schema,
      schema,
      ["id"],
      Some([term]),
      None,
      Some(7),
      max_work=100,
      max_text_bytes=100,
    )
    is Err({ kind: InvalidInput, .. }),
  )
}

///|
test "partial policy retains authored order debt and exact bounded usage" {
  let source = source()
  let schema = schema()
  let absent : Int? = None
  let term : AuthoredTerm = { field: "id", direction: Desc, nulls: Last, source, }
  let pending = resolve(source, schema, schema, ["id"], Some([term]), None, absent, max_work=100, max_text_bytes=100).unwrap()
  assert_true(pending.decision is None)
  assert_true(pending.pending is Some(cursor) && physical_equal(cursor, source))
  assert_true(pending.work > 0)
  assert_true(pending.text_bytes > 0)
  assert_true(resolve(source, schema, schema, ["id"], Some([term]), None, absent, max_work=pending.work, max_text_bytes=pending.text_bytes) is Ok(_))
  assert_true(resolve(source, schema, schema, ["id"], Some([term]), None, absent, max_work=pending.work - 1, max_text_bytes=pending.text_bytes) is Err({ kind: BudgetExceeded, .. }))
  assert_true(resolve(source, schema, schema, ["id"], Some([term]), None, absent, max_work=pending.work, max_text_bytes=pending.text_bytes - 1) is Err({ kind: BudgetExceeded, .. }))
  guard decide(source, schema, schema, ["id"], Some([term]), None, absent, max_work=100, max_text_bytes=100) is Err(issue) else { fail("strict policy must reject an unresolved authored order") }
  assert_eq(issue.kind, UnresolvedOrder)
  assert_true(physical_equal(issue.source, pending.pending.unwrap()))
}

///|
test "partial policy preserves inherited and scalar-field decisions" {
  let source = source()
  let schema = schema()
  for prior in [None, Some(7)] {
    let resolved = resolve(source, schema, schema, ["id"], None, None, prior, max_work=100, max_text_bytes=100).unwrap()
    let strict = decide(source, schema, schema, ["id"], None, None, prior, max_work=100, max_text_bytes=100).unwrap()
    let decision = resolved.decision.unwrap()
    assert_true(resolved.pending is None)
    assert_eq(decision.strategy, strict.strategy)
    assert_eq(decision.inherited, prior)
    assert_eq(resolved.work, strict.work)
    assert_eq(resolved.text_bytes, strict.text_bytes)
    if prior is None { assert_eq(decision.strategy, ProjectedFields); assert_eq(decision.terms[0].field, @schema.Unqualified("id")) }
    else { assert_eq(decision.strategy, Inherited); assert_eq(decision.terms.length(), 0) }
  }
}

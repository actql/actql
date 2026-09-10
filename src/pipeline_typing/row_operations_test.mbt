///|
test "row operations consume raw join schemas on every join kind" {
  for kind in ["inner", "left", "full", "semi", "anti"] {
    let start = "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"" +
      kind +
      "\",\"on\":\"id\"}},"
    let p = join_pipeline(
      start +
      "{\"sort\":[{\"left.amount\":\"desc\"}]},{\"take\":{\"count\":2,\"offset\":1}},{\"distinct\":true},{\"dedupe_rows\":{\"by\":[\"left.id\",\"left.id\"],\"order_by\":[{\"left.amount\":\"asc\"}]}},{\"distinct\":[\"left.id\"],\"as\":\"ids\"}]",
    ).unwrap()
    assert_eq(@pipeline_typing.step_count(p), 6)
    assert_eq(
      @schema.field_count(@pipeline_typing.output_schema(p).unwrap()),
      1,
    )
    assert_eq(
      @schema.lookup(
        @pipeline_typing.output_schema(p).unwrap(),
        Qualified(Left, "id"),
      ).unwrap().nullable,
      kind == "full",
    )
    assert_eq(@pipeline_typing.lookup(p, "ids"), Some(Step(5)))
    let sort = unary(@pipeline_typing.step_at(p, 1).unwrap().operation)
    assert_true(
      @relation.row_operation(sort) is Some(Sort(terms)) &&
      terms[0].field == @schema.Qualified(Left, "amount"),
    )
    assert_eq(@relation.pending_validations(sort)[0].kind, SortOrderCompletion)
    let take = unary(@pipeline_typing.step_at(p, 2).unwrap().operation)
    assert_eq(@relation.pending_validations(take)[0].kind, StableInputOrder)
    let dedupe = unary(@pipeline_typing.step_at(p, 4).unwrap().operation)
    assert_eq(@relation.pending_validations(dedupe)[0].kind, FailOnTopTie)
    for
      op in [
        "{\"sort\":[{\"right.amount\":\"desc\"}]}", "{\"distinct\":[\"right.id\"]}",
        "{\"dedupe_rows\":{\"by\":[\"right.id\"],\"order_by\":[{\"left.id\":\"asc\"}]}}",
      ] {
      assert_eq(
        join_pipeline(start + op + "]") is Ok(_),
        kind != "semi" && kind != "anti",
      )
    }
    assert_true(
      join_pipeline(start + "{\"sort\":[{\"amount\":\"asc\"}]}]")
      is Err({ kind: Operation(UnknownField("amount")), .. }),
    )
  }
}

///|
test "empty sort cannot discharge take ordering and branch changes retain obligations" {
  let p = join_pipeline(
    "[{\"sort\":[],\"from\":\"l\"},{\"take\":1,\"as\":\"first\"},{\"select\":[\"id\"],\"from\":\"r\"}]",
  ).unwrap()
  let sort = unary(@pipeline_typing.step_at(p, 0).unwrap().operation)
  assert_true(@relation.pending_validations(sort).is_empty())
  let take = unary(@pipeline_typing.step_at(p, 1).unwrap().operation)
  assert_eq(@relation.pending_validations(take)[0].kind, StableInputOrder)
  assert_eq(@pipeline_typing.step_at(p, 2).unwrap().input.unwrap(), Input(1))
}

///|
test "pipeline take keeps nullable count and offset parameters unbound" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"n\":{\"type\":\"number\",\"nullable\":true,\"default\":0},\"skip\":{\"type\":\"number\",\"default\":1}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let p = @pipeline_typing.check(
    cursor(
      "[{\"sort\":[]},{\"take\":{\"count\":{\"$param\":\"n\"},\"offset\":{\"$param\":\"skip\"}}}]",
    ),
    [("rows", schema())],
    Some(params),
    None,
    limits(),
  ).unwrap()
  let take = unary(@pipeline_typing.step_at(p, 1).unwrap().operation)
  assert_true(
    @relation.row_operation(take)
    is Some(Take(count=Parameter("n"), offset=Parameter("skip"))),
  )
  assert_eq(@relation.pending_validations(take).map(v => v.kind), [
    BoundInteger(name="n", minimum=1L),
    BoundInteger(name="skip", minimum=0L),
    StableInputOrder,
  ])
}

///|
test "row operation source locations and cumulative pipeline budgets remain exact" {
  let text = "[{\"sort\":[],\"from\":\"l\"},{\"take\":2},{\"distinct\":[\"id\"]},{\"dedupe_rows\":{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}}]"
  let p = join_pipeline(text).unwrap()
  let used = @pipeline_typing.usage(p)
  let exact : @pipeline_typing.Limits = {
    ..limits(),
    max_steps: 4,
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_tokens: used.tokens,
  }
  let inputs = [("l", schema()), ("r", schema())]
  assert_true(
    @pipeline_typing.check(cursor(text), inputs, None, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_steps: 3, },
    ] {
    assert_true(
      @pipeline_typing.check(cursor(text), inputs, None, None, cap) is Err(_),
    )
  }
  let issue = join_pipeline(
    "[{\"sort\":[{\"field\":\"missing\",\"dir\":\"asc\",\"nulls\":\"last\"}],\"from\":\"l\"}]",
  ).unwrap_err()
  assert_eq(issue.path, [@source.Index(0), Key("sort"), Index(0), Key("field")])
  assert_eq(issue.span.source_path, "pipeline.aql")
}

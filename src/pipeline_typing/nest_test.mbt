///|
test "nest connects qualified parents and children with cumulative budgets" {
  let text = "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"},\"as\":\"raw\"},{\"nest\":{\"with\":\"raw\",\"on\":[{\"left\":\"left.id\",\"right\":\"left.id\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"right.amount\"}]},\"as\":\"nested\"},{\"unnest\":{\"column\":\"items\",\"as\":\"item\"}},{\"derive\":{\"value\":\"item.amount + left.amount\"}}]"
  let p = join_pipeline(text).unwrap()
  let step = @pipeline_typing.step_at(p, 1).unwrap()
  assert_eq(step.input.unwrap(), Step(0))
  match step.operation {
    Nest(right~, checked~) => {
      assert_eq(right, Step(0))
      assert_eq(
        @nest.projection(checked)[0].input,
        @schema.Qualified(Right, "amount"),
      )
      assert_eq(@nest.pending_validations(checked).length(), 5)
      assert_true(@nest.order(checked) is None)
    }
    _ => fail("expected nest")
  }
  assert_true(
    @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("value"),
    ).unwrap().nullable,
  )
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
    max_tokens: u.tokens,
  }
  assert_true(
    @pipeline_typing.check(
      cursor(text),
      [("l", schema()), ("r", schema())],
      None,
      None,
      exact,
    )
    is Ok(_),
  )
  for
    l in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(text),
        [("l", schema()), ("r", schema())],
        None,
        None,
        l,
      )
      is Err(_),
    )
  }
}

///|
test "nest enforces ordinary current and prior-name scope" {
  for
    text in [
      "[{\"nest\":{\"with\":\"r\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"]}}]",
      "[{\"nest\":{\"with\":\"later\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"]},\"from\":\"l\",\"as\":\"later\"}]",
    ] {
    assert_true(join_pipeline(text) is Err(_))
  }
  let issue = join_pipeline(
    "[{\"nest\":{\"with\":\"r\",\"on\":[{\"left\":\"id\",\"right\":\"missing\"}],\"into\":\"items\",\"fields\":[\"id\"]},\"from\":\"l\"}]",
  ).unwrap_err()
  assert_eq(issue.kind, Nest(UnknownField(Right, "missing")))
  assert_eq(issue.path, [
    @source.Index(0),
    Key("nest"),
    Key("on"),
    Index(0),
    Key("right"),
  ])
}

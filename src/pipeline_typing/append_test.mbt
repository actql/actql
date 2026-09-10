///|
test "append resolves two retained operands and permits appending the same input" {
  for
    text in [
      "[{\"append\":{\"with\":\"r\"},\"from\":\"l\",\"as\":\"combined\"}]", "[{\"append\":{\"with\":\"l\"},\"from\":\"l\",\"as\":\"combined\"}]",
    ] {
    let p = join_pipeline(text).unwrap()
    let step = @pipeline_typing.step_at(p, 0).unwrap()
    assert_eq(step.input.unwrap(), Input(0))
    match step.operation {
      Append(right~, checked~) => {
        assert_true(right == Input(0) || right == Input(1))
        assert_eq(@append.alignment(checked).length(), 3)
        assert_true(!@append.pending_validations(checked).is_empty())
      }
      _ => fail("expected append")
    }
    assert_eq(@pipeline_typing.current(p).unwrap(), Step(0))
    assert_eq(@pipeline_typing.lookup(p, "combined"), Some(Step(0)))
  }
  for
    text in [
      "[{\"append\":{\"with\":\"r\"}}]", "[{\"append\":{\"with\":\"later\"},\"from\":\"l\",\"as\":\"later\"}]",
      "[{\"append\":{\"with\":\"missing\"},\"from\":\"l\"}]", "[{\"append\":{\"with\":\"r\",\"left\":\"l\"},\"from\":\"l\"}]",
    ] {
    assert_true(join_pipeline(text) is Err(_))
  }
  let p = @pipeline_typing.check(
    cursor("[{\"append\":{\"with\":\"only\"}}]"),
    [("only", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.step_at(p, 0).unwrap().operation
    is Append(right=Input(0), ..),
  )
}

///|
test "append retains raw join provenance then feeds existing expression and projection checks" {
  let text = "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"},\"as\":\"raw\"},{\"append\":{\"with\":\"raw\"},\"as\":\"twice\"},{\"derive\":{\"v\":\"left.amount + right.amount\"}},{\"select\":[\"v\"]}]"
  let p = join_pipeline(text).unwrap()
  let step = @pipeline_typing.step_at(p, 1).unwrap()
  assert_eq(step.input.unwrap(), Step(0))
  assert_true(step.operation is Append(right=Step(0), ..))
  assert_true(
    @schema.as_object(@pipeline_typing.step_schema(step).unwrap()) is None,
  )
  assert_true(
    @schema.lookup(
      @pipeline_typing.step_schema(step).unwrap(),
      Qualified(Right, "amount"),
    ).unwrap().nullable,
  )
  assert_true(
    @schema.lookup(@pipeline_typing.output_schema(p).unwrap(), Unqualified("v")).unwrap().nullable,
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
    bound in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(text),
        [("l", schema()), ("r", schema())],
        None,
        None,
        bound,
      )
      is Err(_),
    )
  }
  let issue = join_pipeline(
    "[{\"select\":[\"id\"],\"from\":\"l\"},{\"append\":{\"with\":\"r\"}}]",
  ).unwrap_err()
  assert_true(
    issue.kind is Append(MissingField(Left, @schema.Unqualified("amount"))),
  )
  assert_eq(issue.path, [@source.Index(1), Key("append"), Key("with")])
  assert_eq(issue.range, None)
}

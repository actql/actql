///|
fn reshaping_pipeline(
  text : String,
  bounds : @pipeline_typing.Limits,
) -> Result[@pipeline_typing.CheckedPipeline, @pipeline_typing.Issue] {
  let row = @contract.read_author(
    cursor(
      "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}}}}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 10000, },
  ).unwrap()
  @pipeline_typing.check(
    cursor(text),
    [
      ("l", @schema.from_object(row).unwrap()),
      ("r", @schema.from_object(row).unwrap()),
    ],
    None,
    None,
    bounds,
  )
}

///|
test "raw join pick and unnest retain scopes through downstream expression and projection" {
  let text = "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"}},{\"json_pick\":{\"column\":\"right.payload\",\"path\":[\"items\"],\"output\":\"items\"}},{\"unnest\":{\"column\":\"items\",\"as\":\"v\",\"outer\":true,\"with_index\":true},\"as\":\"expanded\"},{\"derive\":{\"n\":\"v + left.id\"}},{\"select\":[\"n\",\"v_index\"]}]"
  let p = reshaping_pipeline(text, limits()).unwrap()
  let pick = @pipeline_typing.step_at(p, 1).unwrap()
  assert_true(
    @schema.lookup(
      @pipeline_typing.step_schema(pick).unwrap(),
      Unqualified("items"),
    ).unwrap().nullable,
  )
  assert_true(
    @schema.lookup(
      @pipeline_typing.step_schema(pick).unwrap(),
      Qualified(Right, "payload"),
    ).unwrap().nullable,
  )
  let expanded = @pipeline_typing.step_at(p, 2).unwrap()
  assert_true(
    @schema.lookup(
      @pipeline_typing.step_schema(expanded).unwrap(),
      Unqualified("v"),
    ).unwrap().nullable,
  )
  assert_eq(@pipeline_typing.lookup(p, "expanded"), Some(Step(2)))
  assert_true(
    @schema.lookup(@pipeline_typing.output_schema(p).unwrap(), Unqualified("n")).unwrap().nullable,
  )
  let usage = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: usage.work,
    max_text_bytes: usage.text_bytes,
    max_nodes: usage.nodes,
    max_tokens: usage.tokens,
  }
  assert_true(reshaping_pipeline(text, exact) is Ok(_))
  for
    l in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
    ] {
    assert_true(reshaping_pipeline(text, l) is Err(_))
  }
  let issue = reshaping_pipeline(
    "[{\"json_pick\":{\"column\":\"payload\",\"path\":[\"items\",\"x\"],\"output\":\"v\"},\"from\":\"l\"}]",
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, Operation(ExpectedObject))
  assert_eq(issue.path, [
    @source.Index(0),
    Key("json_pick"),
    Key("path"),
    Index(1),
  ])
}

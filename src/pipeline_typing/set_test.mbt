///|
test "set operators resolve both occurrences and feed existing operations" {
  for op in ["except", "intersect"] {
    let p = @pipeline_typing.check(
      cursor(
        "[{\"" +
        op +
        "\":{\"with\":\"rows\",\"duplicates\":\"all\"},\"as\":\"subset\"},{\"select\":[\"id\"]}]",
      ),
      [("rows", schema())],
      None,
      None,
      limits(),
    ).unwrap()
    let step = @pipeline_typing.step_at(p, 0).unwrap()
    let edges = @pipeline_typing.input_occurrences(step)
    assert_eq(edges.map(e => e.target), [Input(0), Input(0)])
    assert_eq(edges.map(e => e.role), [Left, Right])
    match step.operation {
      Set(checked~, right~) => {
        assert_eq(right, Input(0))
        assert_eq(@set.duplicates(checked), All)
      }
      _ => fail("expected checked set operation")
    }
    assert_eq(@pipeline_typing.lookup(p, "subset"), Some(Step(0)))
    assert_eq(
      @schema.field_count(@pipeline_typing.output_schema(p).unwrap()),
      1,
    )
    let used = @pipeline_typing.usage(p)
    assert_true(
      @pipeline_typing.check(
        @pipeline_typing.source(p),
        [("rows", schema())],
        None,
        None,
        { ..limits(), max_work: used.work - 1, },
      )
      is Err(_),
    )
  }
}

///|
test "set errors retain original option paths and reject future operands" {
  let bad = @pipeline_typing.check(
    cursor("[{\"except\":{\"with\":\"rows\",\"duplicates\":null}}]"),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(bad.kind, Set(InvalidDuplicates))
  assert_eq(bad.path, [Index(0), Key("except"), Key("duplicates")])
  assert_true(
    @pipeline_typing.check(
      cursor(
        "[{\"intersect\":{\"with\":\"later\",\"duplicates\":\"all\"},\"as\":\"later\"}]",
      ),
      [("rows", schema())],
      None,
      None,
      limits(),
    )
    is Err({ kind: UnknownName("later"), .. }),
  )
}

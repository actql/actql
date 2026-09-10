///|
fn values_step(extra : String) -> String {
  "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]}" +
  extra +
  "}"
}

///|
test "values establish current without consuming any input" {
  for inputs in [[], [("ignored", schema())]] {
    let p = @pipeline_typing.check(
      cursor("[" + values_step(",\"as\":\"seed\"") + ",{\"select\":[\"id\"]}]"),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let step = @pipeline_typing.step_at(p, 0).unwrap()
    assert_eq(step.input, None)
    assert_true(@pipeline_typing.input_occurrences(step).is_empty())
    assert_eq(@pipeline_typing.current(p), Some(Step(1)))
    assert_eq(@pipeline_typing.lookup(p, "seed"), Some(Step(0)))
    match step.operation {
      Values(v) => assert_eq(@values.row_count(v), 1)
      _ => fail("values")
    }
    assert_eq(@pipeline_typing.step_at(p, 1).unwrap().input, Some(Step(0)))
  }
}

///|
test "generator alias from and duplicates rules are explicit" {
  assert_true(
    @pipeline_typing.check(
      cursor("[" + values_step("") + "]"),
      [],
      None,
      None,
      limits(),
    )
    is Err({ kind: GeneratorRequiresAlias, .. }),
  )
  assert_true(
    @pipeline_typing.check(
      cursor("[" + values_step(",\"as\":\"seed\",\"from\":\"rows\"") + "]"),
      [("rows", schema())],
      None,
      None,
      limits(),
    )
    is Err({ kind: GeneratorFrom, .. }),
  )
  assert_true(
    @pipeline_typing.check(
      cursor("[" + values_step(",\"as\":\"rows\"") + "]"),
      [("rows", schema())],
      None,
      None,
      limits(),
    )
    is Err({ kind: DuplicateName("rows"), .. }),
  )
}

///|
test "generated Relations compose with set and cross operators" {
  let p = @pipeline_typing.check(
    cursor(
      "[" +
      values_step(",\"as\":\"seed\"") +
      ",{\"intersect\":{\"with\":\"seed\",\"duplicates\":\"all\"}},{\"cross_join\":{\"with\":\"seed\",\"select\":{\"id\":\"left.id\"}}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.current(p), Some(Step(2)))
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 1)
}

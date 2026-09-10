///|
test "cross connections preserve repeated operands and feed qualified expressions" {
  let p = @pipeline_typing.check(
    cursor(
      "[{\"cross_join\":{\"with\":\"rows\",\"right_rows\":\"one\"},\"as\":\"product\"},{\"derive\":{\"sum\":\"left.amount + right.amount\"}},{\"select\":[\"sum\"]}]",
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_eq(@pipeline_typing.input_occurrences(step).map(e => e.target), [
    Input(0),
    Input(0),
  ])
  match step.operation {
    CrossJoin(right~, checked~) => {
      assert_eq(right, Input(0))
      assert_true(@join.cross_requires_one_right_row(checked))
    }
    _ => fail("expected cross join")
  }
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 1)
  assert_eq(@pipeline_typing.lookup(p, "product"), Some(Step(0)))
}

///|
test "cross uses step from and diagnoses right input Carrier mismatches" {
  let inputs = [
    ("a", @carrier.relation(@carrier.typed_rows(schema()))),
    ("b", @carrier.unknown_carrier(GraphKind)),
  ]
  let e = @pipeline_typing.check_carriers(
    cursor("[{\"cross_join\":{\"with\":\"b\"},\"from\":\"a\"}]"),
    inputs,
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(e.kind, WrongCarrier(GraphKind))
  assert_eq(e.path, [Index(0), Key("cross_join"), Key("with")])
  let p = @pipeline_typing.check(
    cursor(
      "[{\"cross_join\":{\"with\":\"a\",\"select\":{\"x\":\"left.id\"}},\"from\":\"b\"}]",
    ),
    [("a", schema()), ("b", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @pipeline_typing.input_occurrences(@pipeline_typing.step_at(p, 0).unwrap()).map(e => {
        e.target
      },
    ),
    [Input(1), Input(0)],
  )
  assert_true(
    @pipeline_typing.check(
      cursor("[{\"cross_join\":{\"with\":\"later\"},\"as\":\"later\"}]"),
      [("a", schema())],
      None,
      None,
      limits(),
    )
    is Err({ kind: UnknownName("later"), .. }),
  )
}

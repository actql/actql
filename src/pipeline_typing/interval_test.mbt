///|
test "interval join left temporal fields are not dataflow selectors" {
  let body = cursor(
    "[{\"interval_join\":{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"amount\"},\"right\":{\"start\":\"amount\",\"end\":\"amount\"},\"select\":{\"value\":\"right.amount\"}},\"from\":\"l\",\"as\":\"matched\"},{\"derive\":{\"copy\":\"value\"}}]",
  )
  let p = @pipeline_typing.check(
    body,
    [("l", schema()), ("r", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_eq(@pipeline_typing.input_occurrences(step).map(e => e.target), [
    Input(0),
    Input(1),
  ])
  assert_eq(@pipeline_typing.lookup(p, "matched"), Some(Step(0)))
  match step.operation {
    IntervalJoin(right~, checked~) => {
      assert_eq(right, Input(1))
      assert_eq(
        @join.interval_operand(checked, Left),
        Point(Unqualified("amount")),
      )
      assert_true(
        @join.interval_pending_validations(checked).contains(
          ValidateIntervalEndpoints,
        ),
      )
    }
    _ => fail("expected interval join")
  }
  let output = @pipeline_typing.output_schema(p).unwrap()
  assert_true(@schema.lookup(output, Unqualified("value")).unwrap().nullable)
  assert_true(@schema.lookup(output, Unqualified("copy")).unwrap().nullable)
}

///|
test "interval join keeps temporal diagnostics and requires a prior right Relation" {
  let bad = @pipeline_typing.check(
    cursor(
      "[{\"interval_join\":{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"amount\"},\"right\":{\"start\":\"amount\",\"end\":\"missing\"}},\"from\":\"l\"}]",
    ),
    [("l", schema()), ("r", schema())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(bad.kind, Join(UnknownField(Right, "missing")))
  assert_eq(bad.path, [Index(0), Key("interval_join"), Key("right"), Key("end")])
  let unknown = @pipeline_typing.check(
    cursor(
      "[{\"interval_join\":{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"amount\"},\"right\":{\"start\":\"amount\",\"end\":\"amount\"}},\"as\":\"r\"}]",
    ),
    [("l", schema())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(unknown.kind, UnknownName("r"))
  let carrier = @pipeline_typing.check_carriers(
    cursor(
      "[{\"interval_join\":{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"amount\"},\"right\":{\"start\":\"amount\",\"end\":\"amount\"}},\"from\":\"l\"}]",
    ),
    [
      ("l", @carrier.relation(@carrier.typed_rows(schema()))),
      ("r", @carrier.unknown_carrier(EventsKind)),
    ],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(carrier.kind, WrongCarrier(EventsKind))
}

///|
test "as-of pipeline consumes retained Events identity and emits a typed Relation" {
  let p = @pipeline_typing.check(
    cursor(
      "[{\"to_events\":{\"id\":\"id\",\"time\":\"amount\"},\"from\":\"l\"},{\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"amount\",\"right_time\":\"amount\",\"direction\":\"nearest\",\"tolerance\":100,\"select\":{\"id\":\"left.id\",\"value\":\"right.amount\"}},\"as\":\"matched\"},{\"derive\":{\"copy\":\"value\"}}]",
    ),
    [("l", schema()), ("r", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 1).unwrap()
  assert_eq(@pipeline_typing.input_occurrences(step).map(e => e.target), [
    Step(0),
    Input(1),
  ])
  assert_eq(@pipeline_typing.lookup(p, "matched"), Some(Step(1)))
  match step.operation {
    AsOfJoin(right~, checked~) => {
      assert_eq(right, Input(1))
      assert_eq(@join.asof_identity(checked), [Unqualified("id")])
      assert_eq(@join.asof_direction(checked), Nearest)
    }
    _ => fail("expected as-of join")
  }
  let output = @pipeline_typing.output_schema(p).unwrap()
  assert_true(@schema.lookup(output, Unqualified("value")).unwrap().nullable)
  assert_true(@schema.lookup(output, Unqualified("copy")).unwrap().nullable)
}

///|
test "as-of pipeline supplies whole retained keys on both input edges" {
  let relation = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), relation, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let inputs = [
    ("l", @pipeline_typing.KeyedInput(key)),
    ("r", @pipeline_typing.KeyedInput(key)),
  ]
  let source = cursor(
    "[{\"from\":\"l\",\"derive\":{\"saved\":\"id\"}},{\"drop\":[\"id\"]},{\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"amount\",\"right_time\":\"amount\",\"direction\":\"nearest\",\"tolerance\":100,\"select\":{\"id\":\"left.saved\",\"value\":\"right.amount\"}}}]",
  )
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 2).unwrap()
  guard step.operation is AsOfJoin(checked~, ..) else { abort("as-of") }
  assert_eq(@join.asof_identity(checked), [Unqualified("saved")])
  assert_eq(@join.asof_completed_tie_break(checked), [Unqualified("id")])
  assert_eq(
    @evidence.declared_key_field_at(
      @join.asof_key_completion(checked, Left).unwrap(),
      0,
    ).unwrap().name,
    Unqualified("id"),
  )
  assert_eq(@pipeline_typing.input_occurrences(step).map(e => e.target), [
    Step(1),
    Input(1),
  ])
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, cap)
      is Err(_),
    )
  }
}

///|
test "as-of pipeline Relation input requires identity and preserves right diagnostics" {
  let body = cursor(
    "[{\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"amount\",\"right_time\":\"amount\",\"direction\":\"nearest\",\"tolerance\":100,\"select\":{\"id\":\"left.id\",\"value\":\"right.amount\"},\"left_id\":\"id\"},\"from\":\"l\"}]",
  )
  let p = @pipeline_typing.check(
    body,
    [("l", schema()), ("r", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @pipeline_typing.input_occurrences(@pipeline_typing.step_at(p, 0).unwrap()).map(e => {
        e.target
      },
    ),
    [Input(0), Input(1)],
  )
  let missing = @pipeline_typing.check(
    cursor(
      "[{\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"amount\",\"right_time\":\"amount\",\"direction\":\"nearest\",\"tolerance\":100,\"select\":{\"id\":\"left.id\",\"value\":\"right.amount\"}},\"from\":\"l\"}]",
    ),
    [("l", schema()), ("r", schema())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(missing.kind, Join(MissingLeftIdentity))
  let wrong = @pipeline_typing.check_carriers(
    body,
    [
      ("l", @carrier.relation(@carrier.typed_rows(schema()))),
      ("r", @carrier.unknown_carrier(GraphKind)),
    ],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(wrong.kind, Join(WrongCarrier(Right, GraphKind)))
  assert_eq(wrong.path, [Index(0), Key("asof_join"), Key("with")])
}

///|
test "event bridges preserve retained membership keys without inventing intrinsic uniqueness" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for kind in ["fixed", "sliding"] {
    for keyed in [false, true] {
      let inputs = [
        (
          "rows",
          if keyed {
            @pipeline_typing.KeyedInput(key)
          } else {
            @pipeline_typing.CarrierInput(rows)
          },
        ),
      ]
      let source = cursor(
        "[{\"to_events\":{\"id\":\"id\",\"time\":\"amount\"}},{\"window_events\":{\"kind\":\"" +
        kind +
        "\",\"size\":10,\"step\":3}},{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"drop\"}},{\"events\":true},{\"sort\":[{\"id\":\"desc\"}]},{\"drop\":[\"window_start_ms\"]}]",
      )
      let p = @pipeline_typing.check_with_evidence(
        source,
        inputs,
        None,
        None,
        limits(),
      ).unwrap()
      for i in 0..<3 {
        assert_eq(
          @carrier.kind(@pipeline_typing.carrier_at(p, Step(i)).unwrap()),
          EventsKind,
        )
        assert_true(@pipeline_typing.candidate_keys(p, Step(i)) is None)
      }
      assert_eq(@pipeline_typing.candidate_key(p, Step(3)) is Some(_), keyed)
      assert_eq(@pipeline_typing.logical_order(p, Step(4)) is Some(_), keyed)
      assert_eq(
        @pipeline_typing.candidate_key(p, Step(5)) is Some(_),
        keyed && kind == "fixed",
      )
      if keyed {
        let result = @pipeline_typing.candidate_key(p, Step(3)).unwrap()
        assert_eq(
          @evidence.key_field_count(result),
          if kind == "fixed" {
            1
          } else {
            2
          },
        )
        if kind == "sliding" {
          assert_eq(
            @evidence.key_field_at(result, 1).unwrap().name,
            Unqualified("window_start_ms"),
          )
          assert_eq(
            @evidence.key_pending(@evidence.key_window_input(result).unwrap()),
            @evidence.key_pending(key),
          )
        }
      }
      let u = @pipeline_typing.usage(p)
      let exact = {
        ..limits(),
        max_work: u.work,
        max_text_bytes: u.text_bytes,
        max_nodes: u.nodes,
        max_tokens: u.tokens,
      }
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
        is Ok(_),
      )
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, {
          ..exact,
          max_work: u.work - 1,
        })
        is Err(_),
      )
    }
  }
}

///|
test "as-of retains Events role identity instead of reinterpreting carried relation keys" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"amount\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 6,
  }).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor(
      "[{\"to_events\":{\"id\":\"id\",\"time\":\"amount\"},\"from\":\"l\"},{\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"amount\",\"right_time\":\"amount\",\"direction\":\"nearest\",\"tolerance\":100,\"select\":{\"id\":\"left.id\",\"value\":\"right.amount\"}}}]",
    ),
    [
      ("l", @pipeline_typing.KeyedInput(key)),
      ("r", @pipeline_typing.CarrierInput(rows)),
    ],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 1).unwrap().operation
    is @pipeline_typing.AsOfJoin(checked~, ..) else {
    abort("expected asof")
  }
  assert_eq(@join.asof_identity(checked), [Unqualified("id")])
}

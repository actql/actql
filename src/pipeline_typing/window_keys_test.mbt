///|
test "window group keys include checked boundaries and survive exact aliases" {
  let source = cursor(
    "[{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":3}},{\"window_group\":{\"by\":[\"value\",\"value\"],\"aggregates\":{}}},{\"select\":[{\"begin\":\"window_start\"},{\"end\":\"window_end\"},\"value\"]}]",
  )
  let inputs = [("rows", window_input())]
  let p = @pipeline_typing.check_carriers(source, inputs, None, None, limits()).unwrap()
  // No input key or row identity is inferred from window boundary names alone.
  assert_true(@pipeline_typing.candidate_keys(p, Step(0)) is None)
  let key = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
  assert_eq(@evidence.key_origin(key), GroupResult)
  assert_eq(@evidence.key_field_count(key), 3)
  assert_eq(
    Array::makei(3, i => @evidence.key_field_at(key, i).unwrap().name),
    [
      Unqualified("window_start"),
      Unqualified("window_end"),
      Unqualified("value"),
    ],
  )
  let producer = @evidence.key_producer(key).unwrap()
  assert_eq(
    @relation.group_keys(@relation.group(producer).unwrap()).length(),
    4,
  )
  assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
  let transferred = @pipeline_typing.candidate_key(p, Step(2)).unwrap()
  assert_eq(
    Array::makei(3, i => @evidence.key_field_at(transferred, i).unwrap().name),
    [Unqualified("begin"), Unqualified("end"), Unqualified("value")],
  )
  assert_eq(
    @evidence.declared_key_field_at(transferred, 0).unwrap().name,
    Unqualified("window_start"),
  )
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, cap) is Err(_),
    )
  }
}

///|
test "window group boundary tuple completes as-of identity without a declared input key" {
  for keep_end in [true, false] {
    let projection = if keep_end {
      "[{\"begin\":\"window_start\"},{\"end\":\"window_end\"}]"
    } else {
      "[{\"begin\":\"window_start\"}]"
    }
    let source = cursor(
      "[{\"from\":\"l\",\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}},{\"window_group\":{\"by\":[],\"aggregates\":{}}},{\"select\":" +
      projection +
      "},{\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"begin\",\"right_time\":\"at\",\"direction\":\"nearest\",\"tolerance\":100,\"select\":{\"begin\":\"left.begin\"}}}]",
    )
    let result = @pipeline_typing.check_carriers(
      source,
      [("l", window_input()), ("r", window_input())],
      None,
      None,
      limits(),
    )
    if !keep_end {
      assert_eq(result.unwrap_err().kind, Join(MissingLeftIdentity))
      continue
    }
    let p = result.unwrap()
    guard @pipeline_typing.step_at(p, 3).unwrap().operation
      is AsOfJoin(checked~, ..) else {
      abort("as-of")
    }
    assert_eq(@join.asof_identity(checked), [
      Unqualified("begin"),
      Unqualified("end"),
    ])
    let key = @join.asof_key_completion(checked, Left).unwrap()
    assert_eq(@evidence.key_origin(key), GroupResult)
    assert_true(@evidence.key_producer(key) is Some(_))
    assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
  }
}

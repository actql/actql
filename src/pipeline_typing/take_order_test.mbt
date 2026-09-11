///|
test "take completes a whole input key only when no prior order exists" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("z"), Some(number)), (Unqualified("a"), Some(number))],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=2,
    ).unwrap(),
  )
  let key = @evidence.declare_primary_key(cursor("[\"z\",\"a\"]"), rows, {
    max_fields: 2,
    max_name_bytes: 2,
  }).unwrap()
  let source = cursor(
    "[{\"sort\":[]},{\"take\":{\"count\":2,\"offset\":1}},{\"take\":1}]",
  )
  let inputs = [("rows", @pipeline_typing.KeyedInput(key))]
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.logical_order(p, Step(0)) is None)
  let order = @pipeline_typing.take_order(p, 1).unwrap()
  assert_eq(@pipeline_typing.order_origin(order), Step(1))
  let selected = @pipeline_typing.order_key_completion(order).unwrap()
  assert_eq(@evidence.key_field_count(selected), 2)
  assert_eq(@evidence.key_field_at(selected, 0).unwrap().name, Unqualified("a"))
  assert_eq(@evidence.key_field_at(selected, 1).unwrap().name, Unqualified("z"))
  assert_eq(
    @evidence.declared_key_field_at(selected, 0).unwrap().name,
    Unqualified("z"),
  )
  assert_eq(@evidence.key_pending(selected), @evidence.key_pending(key))
  assert_eq(
    @pipeline_typing.order_origin(@pipeline_typing.take_order(p, 2).unwrap()),
    Step(1),
  )
  assert_true(@pipeline_typing.take_order(p, 0) is None)
  assert_true(@pipeline_typing.take_order(p, -1) is None)
  let raw = @pipeline_typing.check_carriers(
    source,
    [("rows", rows)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.take_order(raw, 1) is None)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
  }
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, cap)
      is Err(_),
    )
  }
}

///|
test "take preserves completed descending sort instead of replacing it with ascending identity" {
  let source = cursor(
    "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"sort\":[{\"time\":\"desc\"}]},{\"take\":1}]",
  )
  let p = @pipeline_typing.check_carriers(source, [], None, None, limits()).unwrap()
  let order = @pipeline_typing.take_order(p, 2).unwrap()
  assert_eq(@pipeline_typing.order_origin(order), Step(1))
  assert_true(@pipeline_typing.order_key_completion(order) is None)
  assert_true(@pipeline_typing.order_sort_completion(order) is Some(_))
  guard @pipeline_typing.order_producer(order).unwrap().operation is Unary(op) else {
    abort("sort")
  }
  assert_eq(@relation.sort_term_at(op, 0).unwrap().direction, Desc)
}

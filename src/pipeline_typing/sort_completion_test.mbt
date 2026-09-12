///|
test "sort completion preserves authored terms and recognizes equivalent key aliases" {
  let source = cursor(
    "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"select\":[{\"a\":\"time\"},{\"b\":\"time\"},\"x\"],\"as\":\"aliases\"},{\"sort\":[{\"x\":\"desc\"}]},{\"sort\":[{\"b\":\"desc\"}],\"from\":\"aliases\"},{\"drop\":[\"a\",\"b\"]},{\"take\":2}]",
  )
  let p = @pipeline_typing.check_carriers(source, [], None, None, limits()).unwrap()
  let order = @pipeline_typing.logical_order(p, Step(3)).unwrap()
  assert_true(
    @pipeline_typing.sort_order_strategy(
      @pipeline_typing.sort_order(p, 3).unwrap(),
    )
    is CandidateKey(_),
  )
  assert_true(@pipeline_typing.order_tie_break(order) is None)
  assert_eq(@pipeline_typing.order_origin(order), Step(3))
  let completion = @pipeline_typing.order_sort_completion(order).unwrap()
  assert_eq(@pipeline_typing.sort_completion_count(completion), 1)
  assert_eq(
    @pipeline_typing.sort_completion_field(completion, 0),
    Some(Unqualified("a")),
  )
  assert_true(@pipeline_typing.sort_completion_field(completion, 1) is None)
  assert_eq(
    @evidence.key_origin(@pipeline_typing.sort_completion_key(completion)),
    TimeSeriesResult,
  )
  guard @pipeline_typing.order_producer(order).unwrap().operation is Unary(op) else {
    abort("sort")
  }
  assert_eq(@relation.sort_term_count(op), 1)
  let authored = @relation.sort_term_at(op, 0).unwrap()
  assert_eq(authored.field, Unqualified("x"))
  assert_eq(authored.direction, Desc)
  let covered = @pipeline_typing.order_sort_completion(
    @pipeline_typing.logical_order(p, Step(4)).unwrap(),
  ).unwrap()
  // b carries the same original component as a, so a is not appended again.
  assert_eq(@pipeline_typing.sort_completion_count(covered), 0)
  assert_eq(
    @pipeline_typing.order_origin(
      @pipeline_typing.logical_order(p, Step(6)).unwrap(),
    ),
    Step(4),
  )
  assert_true(@pipeline_typing.candidate_key(p, Step(5)) is None)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, [], None, None, exact) is Ok(_),
  )
  for
    caps in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(source, [], None, None, caps) is Err(_),
    )
  }
}

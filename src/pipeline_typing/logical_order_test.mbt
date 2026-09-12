///|
test "generator order survives projection and empty sort without inventing field keys" {
  let source = cursor(
    "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"drop\":[\"time\"]},{\"sort\":[]},{\"take\":1},{\"sort\":[{\"x\":\"desc\"}]},{\"select\":[\"time\"],\"from\":\"grid\"}]",
  )
  let p = @pipeline_typing.check_carriers(source, [], None, None, limits()).unwrap()
  for i = 0; i <= 4; i = i + 1 {
    let order = @pipeline_typing.logical_order(p, Step(i)).unwrap()
    assert_eq(@pipeline_typing.order_origin(order), Step(0))
    assert_true(
      @pipeline_typing.order_producer(order).unwrap().operation is TimeSeries(_),
    )
    assert_eq(
      @pipeline_typing.order_predecessor(order),
      if i == 0 {
        None
      } else {
        Some(Step(i - 1))
      },
    )
  }
  // A stable occurrence sequence does not make constant output x a unique key.
  assert_true(@pipeline_typing.candidate_key(p, Step(2)) is None)
  let sorted = @pipeline_typing.logical_order(p, Step(5)).unwrap()
  assert_eq(@pipeline_typing.order_origin(sorted), Step(5))
  assert_eq(
    @pipeline_typing.order_origin(
      @pipeline_typing.order_tie_break(sorted).unwrap(),
    ),
    Step(0),
  )
  let branched = @pipeline_typing.logical_order(p, Step(6)).unwrap()
  assert_eq(@pipeline_typing.order_predecessor(branched), Some(Step(0)))
  assert_eq(@pipeline_typing.order_origin(branched), Step(0))
  assert_true(@pipeline_typing.logical_order(p, Step(999)) is None)
  assert_true(@pipeline_typing.logical_order(p, Input(0)) is None)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, [], None, None, exact) is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(source, [], None, None, {
      ..exact,
      max_work: u.work - 1,
    })
    is Err(_),
  )
}

///|
test "calendar series order retains its admitted profile but unknown input order stays unknown" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-02T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"},{\"rename\":{\"start\":\"begin\"}}]",
    ),
    [],
    None,
    None,
    limits(),
    calendar_profile=Some(calendar_profile()),
  ).unwrap()
  let order = @pipeline_typing.logical_order(p, Step(1)).unwrap()
  assert_eq(@pipeline_typing.order_origin(order), Step(0))
  assert_true(
    @pipeline_typing.order_producer(order).unwrap().operation is Calendar(_),
  )
  let unknown = @pipeline_typing.check_carriers(
    cursor("[{\"sort\":[]}]"),
    [("input", @pipeline_typing.output_carrier(p).unwrap())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.logical_order(unknown, Step(0)) is None)
}

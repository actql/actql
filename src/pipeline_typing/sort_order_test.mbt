///|
test "sort establishes a new order with hidden prior fields as tie dependency" {
  let source = cursor(
    "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"drop\":[\"time\"]},{\"sort\":[{\"x\":\"desc\"}]},{\"take\":1},{\"sort\":[]}]",
  )
  let p = match
    @pipeline_typing.check_carriers(source, [], None, None, limits()) {
    Ok(p) => p
    Err(e) => fail(@debug.to_string(e.kind))
  }
  let resolution = @pipeline_typing.sort_order(p, 3).unwrap()
  assert_true(
    physical_equal(@pipeline_typing.sort_order_pipeline(resolution), p),
  )
  assert_eq(@pipeline_typing.sort_order_step(resolution), 3)
  assert_eq(@pipeline_typing.sort_order_input(resolution), Step(2))
  guard @pipeline_typing.sort_order_consumer(resolution).operation is Unary(op) else {
    abort("sort operation")
  }
  assert_eq(@relation.sort_term_at(op, 0).unwrap().direction, Desc)
  guard @pipeline_typing.sort_order_strategy(resolution) is ExistingTotal(prior) else {
    abort("prior witness expected")
  }
  assert_true(
    physical_equal(prior, @pipeline_typing.logical_order(p, Step(2)).unwrap()),
  )
  assert_eq(@pipeline_typing.order_origin(prior), Step(0))
  let order = @pipeline_typing.sort_order_evidence(resolution)
  assert_eq(@pipeline_typing.order_origin(order), Step(3))
  assert_true(@pipeline_typing.order_predecessor(order) is None)
  assert_eq(@pipeline_typing.order_dependency_count(order), 1)
  assert_eq(@pipeline_typing.order_dependency_at(order, 0), Some(Step(2)))
  assert_true(
    physical_equal(@pipeline_typing.order_tie_break(order).unwrap(), prior),
  )
  for i in [4, 5] {
    let kept = @pipeline_typing.logical_order(p, Step(i)).unwrap()
    assert_eq(@pipeline_typing.order_origin(kept), Step(3))
    assert_true(
      physical_equal(@pipeline_typing.order_tie_break(kept).unwrap(), prior),
    )
  }
  for i in [-1, 0, 4, 5, 6] {
    assert_true(@pipeline_typing.sort_order(p, i) is None)
  }
  let resolved = @pipeline_typing.resolve_contextual_orders(
    p,
    max_steps=6,
    max_work=6,
    max_text_bytes=0,
  ).unwrap()
  assert_true(
    @pipeline_typing.contextual_orders_at(resolved, 3).unwrap()[0]
    is SortSequence(_),
  )
  assert_eq(@pipeline_typing.contextual_orders_usage(resolved), (6, 0))
  for (steps, work) in [(5, 6), (6, 5), (6, -1)] {
    assert_true(
      @pipeline_typing.resolve_contextual_orders(
        p,
        max_steps=steps,
        max_work=work,
        max_text_bytes=0,
      )
      is Err(_),
    )
  }
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
  assert_true(
    @pipeline_typing.check_carriers(source, [], None, None, {
      ..exact,
      max_work: u.work - 1,
    })
    is Err(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(source, [], None, None, {
      ..exact,
      max_text_bytes: u.text_bytes - 1,
    })
    is Err(_),
  )
}

///|
test "sort ties use the actual imported producer and never another input's evidence" {
  let a = @pipeline_typing.check_carriers(
    cursor("[" + count_values(2, "seed") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let b = @pipeline_typing.check_carriers(
    cursor("[" + count_values(2, "seed") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let pa = @pipeline_typing.produced_input(a, Step(0)).unwrap()
  let pb = @pipeline_typing.produced_input(b, Step(0)).unwrap()
  let inputs = [
    ("a", @pipeline_typing.ProducedInput(pa)),
    ("b", @pipeline_typing.ProducedInput(pb)),
  ]
  for (name, owner) in [("a", pa), ("b", pb)] {
    let p = @pipeline_typing.check_with_evidence(
      cursor("[{\"from\":\"" + name + "\",\"sort\":[{\"id\":\"desc\"}]}]"),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    guard @pipeline_typing.sort_order_strategy(
        @pipeline_typing.sort_order(p, 0).unwrap(),
      )
      is ExistingTotal(prior) else {
      abort("imported order")
    }
    assert_true(
      physical_equal(
        @pipeline_typing.order_input_producer(prior).unwrap(),
        owner,
      ),
    )
  }
  let raw = @pipeline_typing.CarrierInput(
    @pipeline_typing.output_carrier(a).unwrap(),
  )
  let p = @pipeline_typing.check_with_evidence(
    cursor("[{\"from\":\"raw\",\"sort\":[{\"id\":\"desc\"}]},{\"take\":1}]"),
    [("unrelated", @pipeline_typing.ProducedInput(pa)), ("raw", raw)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.sort_order(p, 0) is None)
  assert_true(@pipeline_typing.take_order(p, 1) is None)
  assert_eq(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=2,
      max_work=2,
      max_text_bytes=0,
    ).unwrap_err().kind,
    UnresolvedOrder,
  )
}

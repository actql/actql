///|
test "imported order coordinates retain upstream ownership and repeated dependencies" {
  let producer = @pipeline_typing.check_carriers(
    cursor("[" + count_values(2, "seed") + ",{\"append\":{\"with\":\"seed\"}}]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let imported = @pipeline_typing.produced_input(producer, Step(1)).unwrap()
  let source = cursor("[{\"sort\":[]},{\"append\":{\"with\":\"prior\"}}]")
  let inputs = [
    (
      "unused",
      @pipeline_typing.CarrierInput(
        @carrier.relation(@carrier.typed_rows(schema())),
      ),
    ),
    ("prior", @pipeline_typing.ProducedInput(imported)),
  ]
  let from = Some(cursor("\"prior\""))
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    from,
    limits(),
  ).unwrap()
  let order = @pipeline_typing.logical_order(p, Input(1)).unwrap()
  assert_eq(@pipeline_typing.order_origin(order), Input(1))
  assert_true(@pipeline_typing.order_producer(order) is None)
  assert_eq(@pipeline_typing.order_dependency_count(order), 0)
  assert_true(
    physical_equal(
      @pipeline_typing.order_input_producer(order).unwrap(),
      imported,
    ),
  )
  assert_true(
    physical_equal(@pipeline_typing.producer_pipeline(imported), producer),
  )
  let upstream = @pipeline_typing.producer_order(imported).unwrap()
  assert_eq(@pipeline_typing.order_origin(upstream), Step(1))
  assert_true(
    @pipeline_typing.order_producer(upstream).unwrap().operation is Append(..),
  )
  assert_eq(@pipeline_typing.order_dependency_count(upstream), 2)
  assert_eq(@pipeline_typing.order_dependency_at(upstream, 0), Some(Step(0)))
  assert_eq(@pipeline_typing.order_dependency_at(upstream, 1), Some(Step(0)))
  let kept = @pipeline_typing.logical_order(p, Step(0)).unwrap()
  assert_eq(@pipeline_typing.order_origin(kept), Input(1))
  assert_eq(@pipeline_typing.order_predecessor(kept), Some(Input(1)))
  assert_true(
    physical_equal(
      @pipeline_typing.order_input_producer(kept).unwrap(),
      imported,
    ),
  )
  let derived = @pipeline_typing.logical_order(p, Step(1)).unwrap()
  assert_eq(@pipeline_typing.order_origin(derived), Step(1))
  assert_true(@pipeline_typing.order_input_producer(derived) is None)
  assert_true(
    @pipeline_typing.order_producer(derived).unwrap().operation is Append(..),
  )
  assert_eq(@pipeline_typing.order_dependency_at(derived, 0), Some(Step(0)))
  assert_eq(@pipeline_typing.order_dependency_at(derived, 1), Some(Input(1)))
  assert_true(@pipeline_typing.logical_order(p, Input(0)) is None)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
    max_tokens: u.tokens,
  }
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, from, exact)
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, from, {
      ..exact,
      max_work: u.work - 1,
    })
    is Err(_),
  )
}

///|
test "imported order resolves input consumers but equal schemas do not invent order" {
  let producer = @pipeline_typing.check_carriers(
    cursor("[" + count_values(2, "rows") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let source = cursor(
    "[{\"watermark_rows\":{\"time\":\"id\",\"max_skew\":1,\"late_policy\":\"mark\"}},{\"take\":1}]",
  )
  for retained in [false, true] {
    let input = if retained {
      @pipeline_typing.ProducedInput(
        @pipeline_typing.produced_input(producer, Step(0)).unwrap(),
      )
    } else {
      @pipeline_typing.CarrierInput(
        @pipeline_typing.carrier_at(producer, Step(0)).unwrap(),
      )
    }
    let p = @pipeline_typing.check_with_evidence(
      source,
      [("rows", input)],
      None,
      None,
      limits(),
    ).unwrap()
    let resolved = @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=2,
      max_work=1000,
      max_text_bytes=1000,
    )
    assert_eq(resolved is Ok(_), retained)
    assert_eq(@pipeline_typing.take_order(p, 1) is Some(_), retained)
    if retained {
      assert_eq(
        @pipeline_typing.order_origin(
          @pipeline_typing.take_order(p, 1).unwrap(),
        ),
        Input(0),
      )
    }
  }
}

///|
test "forwarded input order keeps each owner without recursive resolution" {
  let original = @pipeline_typing.check_carriers(
    cursor("[" + count_values(1, "rows") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let mut p = original
  let mut target = @pipeline_typing.Step(0)
  let source = cursor("[]")
  for _ in 0..<2000 {
    let input = @pipeline_typing.produced_input(p, target).unwrap()
    p = @pipeline_typing.check_with_evidence(
      source,
      [("rows", @pipeline_typing.ProducedInput(input))],
      None,
      None,
      limits(),
    ).unwrap()
    target = Input(0)
  }
  let mut order = @pipeline_typing.logical_order(p, Input(0)).unwrap()
  let mut owners = 0
  while @pipeline_typing.order_input_producer(order) is Some(input) {
    owners += 1
    if owners == 2000 {
      assert_true(
        physical_equal(@pipeline_typing.producer_pipeline(input), original),
      )
    }
    order = @pipeline_typing.producer_order(input).unwrap()
  }
  assert_eq(owners, 2000)
  assert_eq(@pipeline_typing.order_origin(order), Step(0))
  assert_true(
    @pipeline_typing.order_producer(order).unwrap().operation is Values(_),
  )
}

///|
test "join order checks imported operands independently" {
  let producer = @pipeline_typing.check_carriers(
    cursor("[" + count_values(2, "rows") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let imported = @pipeline_typing.produced_input(producer, Step(0)).unwrap()
  let raw = @pipeline_typing.carrier_at(producer, Step(0)).unwrap()
  for kind in ["inner", "left", "full", "semi", "anti"] {
    for right_ordered in [false, true] {
      let right = if right_ordered {
        @pipeline_typing.ProducedInput(imported)
      } else {
        @pipeline_typing.CarrierInput(raw)
      }
      let p = @pipeline_typing.check_with_evidence(
        cursor(
          "[{\"from\":\"left\",\"join\":{\"with\":\"right\",\"kind\":\"" +
          kind +
          "\",\"on\":\"id\"}}]",
        ),
        [("left", @pipeline_typing.ProducedInput(imported)), ("right", right)],
        None,
        None,
        limits(),
      ).unwrap()
      let left_only = kind == "semi" || kind == "anti"
      let order = @pipeline_typing.logical_order(p, Step(0))
      assert_eq(order is Some(_), left_only || right_ordered)
      if order is Some(order) {
        assert_eq(
          @pipeline_typing.order_dependency_count(order),
          if left_only {
            1
          } else {
            2
          },
        )
        assert_eq(
          @pipeline_typing.order_dependency_at(order, 0),
          Some(Input(0)),
        )
        if !left_only {
          assert_eq(
            @pipeline_typing.order_dependency_at(order, 1),
            Some(Input(1)),
          )
        }
      }
    }
  }
  let unknown = @pipeline_typing.check_carriers(
    cursor("[]"),
    [("rows", raw)],
    None,
    None,
    limits(),
  ).unwrap()
  let supplied = @pipeline_typing.produced_input(unknown, Input(0)).unwrap()
  assert_true(@pipeline_typing.producer_order(supplied) is None)
  let p = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [("rows", @pipeline_typing.ProducedInput(supplied))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.logical_order(p, Input(0)) is None)
}

///|
fn port_limits() -> @relation_results.PortLimits {
  {
    max_results: 100,
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
  }
}

///|
fn port_order_owner() -> @relation_results.CheckedOrders {
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"x\":{\"literal\":1}},\"as\":\"extended\"}]",
    ),
    [],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let r = @relation_results.check(
    p,
    cursor(
      "{\"ascending\":{\"from\":\"extended\",\"fields\":[\"x\"],\"order_by\":[{\"time\":\"asc\"}]},\"descending\":{\"from\":\"extended\",\"fields\":[\"x\"],\"order_by\":[{\"time\":\"desc\"}]},\"inherited\":{\"from\":\"extended\",\"fields\":[\"x\"]}}",
    ),
    limits(),
  ).unwrap()
  @relation_results.resolve_all_orders(r, {
    max_steps: 100,
    max_results: 100,
    max_work: 100000,
    max_text_bytes: 100000,
  }).unwrap()
}

///|
test "named Result ports keep publication order distinct from their shared source and projection" {
  let orders = port_order_owner()
  let ports = @relation_results.prepare_ports(orders, port_limits()).unwrap()
  assert_eq(@relation_results.port_count(ports), 3)
  assert_true(physical_equal(@relation_results.ports_orders(ports), orders))
  for i in 0..<3 {
    let port = @relation_results.port_at(ports, i).unwrap()
    assert_true(physical_equal(@relation_results.port_orders(port), orders))
    let order = @relation_results.port_order(port)
    assert_true(
      physical_equal(
        order,
        @relation_results.publication_order_at(
          @relation_results.checked_publication_orders(orders),
          i,
        ).unwrap(),
      ),
    )
    let result = @relation_results.port_result(port)
    assert_eq(@relation_results.target(result), Step(1))
    let schema = @relation_results.port_schema(port)
    assert_eq(@schema.field_count(schema), 1)
    assert_eq(@schema.field_at(schema, 0).unwrap().name, Unqualified("x"))
    assert_eq(@relation_results.pending_validations(result), [
      TotalDeterministicOrder,
    ])
    match @relation_results.name(result) {
      "ascending" => {
        assert_eq(@relation_results.publication_strategy(order), Authored)
        assert_eq(
          @relation_results.publication_term_at(order, 0).unwrap().direction,
          Asc,
        )
      }
      "descending" => {
        assert_eq(@relation_results.publication_strategy(order), Authored)
        assert_eq(
          @relation_results.publication_term_at(order, 0).unwrap().direction,
          Desc,
        )
      }
      "inherited" => {
        assert_eq(@relation_results.publication_strategy(order), Inherited)
        assert_true(
          @relation_results.publication_inherited_order(order) is Some(_),
        )
      }
      _ => fail("unexpected Result name")
    }
  }
  assert_true(@relation_results.port_at(ports, -1) is None)
  assert_true(@relation_results.port_at(ports, 3) is None)
}

///|
test "Result port preparation budgets include prior order checking and every projection" {
  let orders = port_order_owner()
  let ports = @relation_results.prepare_ports(orders, port_limits()).unwrap()
  let u = @relation_results.ports_usage(ports)
  let prior = @relation_results.checked_orders_usage(orders)
  assert_true(u.work > prior.0)
  assert_true(u.text_bytes > prior.1)
  assert_true(u.nodes > 0)
  let exact = {
    ..port_limits(),
    max_results: 3,
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@relation_results.prepare_ports(orders, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_results: 2, },
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(@relation_results.prepare_ports(orders, cap) is Err(_))
  }
  assert_true(
    @relation_results.prepare_ports(orders, { ..exact, max_work: prior.0 - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @relation_results.prepare_ports(orders, {
      ..exact,
      max_text_bytes: prior.1 - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    @relation_results.prepare_ports(orders, { ..exact, max_results: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "named Result inputs expose their own publication order to downstream consumers" {
  let orders = port_order_owner()
  let ports = @relation_results.prepare_ports(orders, port_limits()).unwrap()
  for i in 0..<@relation_results.port_count(ports) {
    let port = @relation_results.port_at(ports, i).unwrap()
    let input = @relation_results.port_input(port)
    let publication = @relation_results.port_publication(port)
    assert_true(
      physical_equal(
        @pipeline.order_publication(@pipeline.producer_order(input).unwrap()).unwrap(),
        publication,
      ),
    )
    let expected = @relation_results.port_order(port)
    assert_eq(
      @pipeline.publication_term_count(publication),
      @relation_results.publication_term_count(expected),
    )
    for j in 0..<@pipeline.publication_term_count(publication) {
      let actual = @pipeline.publication_term_at(publication, j).unwrap()
      let term = @relation_results.publication_term_at(expected, j).unwrap()
      assert_eq(actual.field, term.field)
      assert_eq(actual.direction, term.direction)
      assert_eq(actual.nulls, term.nulls)
    }
    let consumer = @pipeline.check_with_evidence(
      cursor("[{\"take\":1}]"),
      [("r", @pipeline.ProducedInput(input))],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.take_order(consumer, 0) is Some(_))
    assert_true(
      physical_equal(@pipeline.input_producer(consumer, 0).unwrap(), input),
    )
    assert_true(
      @schema.lookup_reference(
        @pipeline.schema_at(consumer, Input(0)).unwrap(),
        "time",
      )
      is None,
    )
    assert_eq(
      @schema.field_count(@pipeline.schema_at(consumer, Input(0)).unwrap()),
      1,
    )
  }
}

///|
test "Result ports preserve qualified join columns without flattening" {
  let r = @relation_results.check(
    joined_pipeline("full"),
    cursor(
      "{\"r\":{\"from\":\"joined\",\"fields\":[\"right.id\",\"left.id\"]}}",
    ),
    limits(),
  ).unwrap()
  let orders = @relation_results.resolve_all_orders(r, {
    max_steps: 10,
    max_results: 10,
    max_work: 100000,
    max_text_bytes: 100000,
  }).unwrap()
  let ports = @relation_results.prepare_ports(orders, port_limits()).unwrap()
  let port = @relation_results.port_at(ports, 0).unwrap()
  let schema = @relation_results.port_schema(port)
  assert_true(@schema.as_object(schema) is None)
  assert_true(@schema.lookup(schema, Qualified(Left, "id")).unwrap().nullable)
  assert_true(@schema.lookup(schema, Qualified(Right, "id")).unwrap().nullable)
  let order = @relation_results.port_order(port)
  assert_eq(@relation_results.publication_strategy(order), ProjectedFields)
  assert_eq(
    @relation_results.publication_term_at(order, 0).unwrap().field,
    Qualified(Right, "id"),
  )
  assert_eq(
    @relation_results.publication_term_at(order, 1).unwrap().field,
    Qualified(Left, "id"),
  )
}

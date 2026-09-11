///|
test "prepared Result ports and contexts retain the same resolved order owner" {
  let producer = base(true)
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(producer, Input(0)).unwrap(),
  )
  let root = pipeline([("a", input), ("unused", input)])
  let result = results(root)
  let orders = @results.resolve_all_orders(result, {
    max_steps: 0,
    max_results: 1,
    max_work: 10000,
    max_text_bytes: 10000,
  }).unwrap()
  let ports = @results.prepare_ports(orders, {
    max_results: 1,
    max_work: 20000,
    max_nodes: 1000,
    max_text_bytes: 20000,
    max_depth: 100,
  }).unwrap()
  let applications = [capacity(root), capacity(producer), capacity(producer)]
  let context = check_resolved_orders(
    orders,
    [None, None, None],
    applications,
    policy(),
    max_work=20000,
    max_text_bytes=20000,
  ).unwrap()
  assert_true(physical_equal(checked_results(context), result))
  assert_true(
    physical_equal(checked_orders(context), @results.ports_orders(ports)),
  )
  assert_true(
    physical_equal(
      checked_orders(context),
      @results.port_orders(@results.port_at(ports, 0).unwrap()),
    ),
  )
  assert_true(
    physical_equal(
      @pipeline.bound_guard_closure_source(bound_guards(context)),
      @results.checked_producer_orders(orders),
    ),
  )
  assert_true(
    physical_equal(
      @capacity.application_closure_orders(checked_capacity(context)),
      @results.checked_producer_orders(orders),
    ),
  )
  let (work, text) = usage(context)
  let ordinary = check(
    result,
    [None, None, None],
    applications,
    policy(),
    limits(),
  ).unwrap()
  assert_eq(usage(ordinary), (work, text))
  assert_true(
    check_resolved_orders(
      orders,
      [None, None, None],
      applications,
      policy(),
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    check_resolved_orders(
      orders,
      [None, None, None],
      applications,
      policy(),
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  let (prior_work, prior_text) = @results.checked_orders_usage(orders)
  assert_true(
    check_resolved_orders(
      orders,
      [None, None, None],
      applications,
      policy(),
      max_work=prior_work - 1,
      max_text_bytes=text,
    )
    is Err(PriorOrderLimit),
  )
  if prior_text > 0 {
    assert_true(
      check_resolved_orders(
        orders,
        [None, None, None],
        applications,
        policy(),
        max_work=work,
        max_text_bytes=prior_text - 1,
      )
      is Err(PriorOrderLimit),
    )
  }
  assert_true(
    check_resolved_orders(
      orders,
      [None, None, None],
      applications,
      policy(),
      max_work=-1,
      max_text_bytes=text,
    )
    is Err(InvalidIntegrationLimits),
  )
  let foreign = base(true)
  let wrong = [capacity(root), capacity(producer), capacity(foreign)]
  assert_true(
    check_resolved_orders(
      orders,
      [None, None, None],
      wrong,
      policy(),
      max_work=20000,
      max_text_bytes=20000,
    )
    is Err(Capacity(_)),
  )
  assert_true(physical_equal(@results.ports_orders(ports), orders))
}

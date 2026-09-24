///|
fn installed_offer_fixture(
  run : @strategy.CapturedDAG,
  task : Int,
  registration : @connector.CapabilityRegistration,
) -> @strategy.TaskOffer {
  @strategy.prepare_task_offer(
    run,
    task,
    registration,
    0,
    [],
    { transfer_bytes: 0L, retained_bytes: 0L, execution_bytes: 0L, },
    0,
  ).unwrap()
}

///|
test "installed offer collection uses exact finite entries and preserves unknown quantities" {
  let (run, _) = captured_graph_fixture()
  let driver = @host_driver.open_dispatch_driver(run)
  let registry = @connector.prepare_capability_registry(
    ["first", "second", "independent"].map(name => {
      name,
      acquisition: false,
      fixed_compute: true,
      effect: false,
    }),
    3,
    100,
  ).unwrap()
  let quantities : @host_driver.TaskEstimateQuantities = {
    rows: Some(3L),
    wire_bytes: None,
    pairs: Some(0L),
  }
  let mut calls = 0
  let entries = [0, 1, 2].map(index => {
    let registration = @connector.capability_registration_at(registry, index).unwrap()
    (
      registration,
      fn(
        _context : Unit,
        task,
        received : @host_driver.TaskEstimateQuantities,
      ) -> Result[Array[@strategy.TaskOffer], String] {
        calls += 1
        if received.rows != Some(3L) ||
          received.wire_bytes is Some(_) ||
          received.pairs != Some(0L) {
          return Err("estimate quantities changed")
        }
        Ok([installed_offer_fixture(run, task, registration)])
      },
    )
  })
  let installed = @connector.install_capability_implementations(
    registry, entries, 3,
  ).unwrap()
  entries.clear()
  let snapshot = @connector.capability_implementation_registrations(
    installed, 3,
  ).unwrap()
  snapshot.clear()
  assert_true(
    @connector.capability_implementation_registrations(installed, 2) is None,
  )
  assert_true(
    @host_driver.collect_installed_task_offers(
      driver,
      installed,
      (),
      1,
      quantities,
      2,
      3,
    )
    is Err(InvalidLimits),
  )
  assert_eq(calls, 0)
  assert_true(
    @host_driver.collect_installed_task_offers(
      driver,
      installed,
      (),
      1,
      { ..quantities, rows: Some(-1L), },
      3,
      3,
    )
    is Err(InvalidLimits),
  )
  assert_eq(calls, 0)
  let offers = @host_driver.collect_installed_task_offers(
    driver,
    installed,
    (),
    1,
    quantities,
    3,
    3,
  ).unwrap()
  assert_eq(calls, 3)
  assert_eq(offers.length(), 3)
  for index, offer in offers {
    assert_true(
      @strategy.task_offer_matches(
        run,
        1,
        @connector.capability_registration_at(registry, index).unwrap(),
        offer,
      ),
    )
  }
  assert_true(
    @host_driver.collect_installed_task_offers(
      driver,
      installed,
      (),
      1,
      quantities,
      3,
      2,
    )
    is Err(OfferLimit),
  )
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
}

///|
test "installed offers cannot substitute a foreign run task or implementation" {
  let (run, _) = captured_graph_fixture()
  let (foreign, _) = captured_graph_fixture()
  let driver = @host_driver.open_dispatch_driver(run)
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let other = @connector.capability_registration_at(registry, 1).unwrap()
  for
    offer in [
      installed_offer_fixture(foreign, 1, registration),
      installed_offer_fixture(run, 2, registration),
      installed_offer_fixture(run, 1, other),
    ] {
    let installed = @connector.install_capability_implementations(
      registry,
      [
        (
          registration,
          fn(
            _context : Unit,
            _task : Int,
            _q : @host_driver.TaskEstimateQuantities,
          ) -> Result[Array[@strategy.TaskOffer], String] {
            Ok([offer])
          },
        ),
      ],
      1,
    ).unwrap()
    assert_true(
      @host_driver.collect_installed_task_offers(
        driver,
        installed,
        (),
        1,
        { rows: None, wire_bytes: None, pairs: None, },
        1,
        1,
      )
      is Err(ForeignOffer),
    )
  }
  let offer = installed_offer_fixture(run, 1, registration)
  let installed = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(
          _context : Unit,
          _task : Int,
          _q : @host_driver.TaskEstimateQuantities,
        ) -> Result[Array[@strategy.TaskOffer], String] {
          @connector.close_capability_registry(registry)
          Ok([offer])
        },
      ),
    ],
    1,
  ).unwrap()
  assert_true(
    @host_driver.collect_installed_task_offers(
      driver,
      installed,
      (),
      1,
      { rows: None, wire_bytes: None, pairs: None, },
      1,
      1,
    )
    is Err(Unavailable),
  )
  assert_eq(@strategy.strategy_history_count(run), 0)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
}

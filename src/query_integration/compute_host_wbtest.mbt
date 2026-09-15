///|
test "Compute Host owns its installation even when no implementations are selected" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let driver = @host_driver.open_dispatch_driver(run)
  let entries : @connector.CapabilityImplementations[
    @host_driver.ComputeContribution[Unit, String],
  ] = @connector.install_capability_implementations(registry, [], 0).unwrap()
  let limits = dispatch_test_limits()
  assert_true(
    @host_driver.open_compute_host(
      driver,
      search_registry(),
      entries,
      limits.capacity,
      100,
      10000,
      0,
    )
    is Err(ForeignInstallation),
  )
  let host = @host_driver.open_compute_host(
    driver,
    registry,
    entries,
    limits.capacity,
    100,
    10000,
    0,
  ).unwrap()
  assert_false(@host_driver.compute_host_has_estimates(host))
  assert_true(
    @host_driver.prepare_next_compute_task(host, ())
    is Err(Dispatch(NoStrategy)),
  )
  @connector.close_capability_registry(registry)
  assert_true(
    @host_driver.open_compute_host(
      driver,
      registry,
      entries,
      limits.capacity,
      100,
      10000,
      0,
    )
    is Err(Installation(RegistryClosed)),
  )
  assert_eq(@strategy.strategy_history_count(run), 0)
}

///|
test "Compute Host refresh failure cannot reach preparation or replace the fixed policy" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let driver = @host_driver.open_dispatch_driver(run)
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let fail = Ref(false)
  let preparations = Ref(0)
  let proposals = Ref(0)
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        @host_driver.ComputeContribution::{
          exclusions: _ => Some([]),
          prepare: fn(
            _context : Unit,
            _task,
            _revision,
            _request,
          ) -> Result[@host_driver.DispatchWork, String] {
            preparations.val += 1
            Err("preparation-not-expected")
          },
          propose: fn(_context, task, _quantities) {
            proposals.val += 1
            if fail.val {
              return Err("estimate-failed")
            }
            @strategy.prepare_task_offer(
              run,
              task,
              registration,
              1,
              [{ work_slots: [0], milliseconds: Some(1L), }],
              {
                transfer_bytes: 0L,
                retained_bytes: 100L,
                execution_bytes: 2000L,
              },
              100,
            )
            .map(offer => [offer])
            .map_err(_ => "offer-failed")
          },
        },
      ),
    ],
    1,
  ).unwrap()
  let limits = dispatch_test_limits()
  let host = @host_driver.open_compute_host(
    driver,
    registry,
    entries,
    limits.capacity,
    100,
    10000,
    1,
  ).unwrap()
  let search : @strategy.SearchLimits = {
    max_offers: 3,
    max_strategies: 1,
    max_work: 1000,
    max_revisions: 2,
  }
  @host_driver.configure_compute_host_estimates(
    host,
    [Some(1000), Some(1000), Some(1000)],
    search,
    0,
  ).unwrap()
  assert_true(@host_driver.compute_host_has_estimates(host))
  assert_true(
    @host_driver.configure_compute_host_estimates(
      host,
      [Some(0), Some(0), Some(0)],
      search,
      0,
    )
    is Err(InvalidConfiguration),
  )
  @host_driver.refresh_compute_host(host).unwrap()
  assert_eq(proposals.val, 3)
  @host_driver.refresh_compute_host(host).unwrap()
  assert_eq(proposals.val, 3)
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 1L, 1L, 1L).unwrap()
  fail.val = true
  assert_true(
    @host_driver.prepare_next_compute_task(host, ())
    is Err(Estimate(Implementation("estimate-failed"))),
  )
  assert_eq(preparations.val, 0)
  assert_eq(proposals.val, 4)
  let usage = @resources.ledger_usage(ledger)
  assert_true(
    @host_driver.refresh_compute_host(host)
    is Err(Implementation("estimate-failed")),
  )
  assert_true(@host_driver.prepare_next_compute_task(host, ()) is Err(_))
  assert_eq(preparations.val, 0)
  assert_eq(proposals.val, 4)
  assert_eq(@resources.ledger_usage(ledger), usage)
  assert_eq(@strategy.strategy_history_count(run), 1)
  @resources.settle_reservation(ledger, reservation).unwrap()
}

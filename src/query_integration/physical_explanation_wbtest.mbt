///|
test "explanation distinguishes deferred unknown search from an incomplete bounded search" {
  for limited in [false, true] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    @strategy.configure_strategy_search(run, {
      max_offers: 6,
      max_strategies: if limited {
        7
      } else {
        8
      },
      max_work: 1000,
      max_revisions: 1,
    }).unwrap()
    let decision = @strategy.revise_strategy(
      run,
      search_offers(run, registry, [1, 2, 3], None),
      registry,
      None,
    )
    if limited {
      assert_true(decision is Err(StrategyLimit))
    } else {
      assert_true(decision is Ok(Deferred))
    }
    guard @json.parse(
        @strategy.explain_captured_strategy(run, 20000, 2000).unwrap(),
      )
      is Object(report) else {
      fail("report")
    }
    assert_true(report.get("selection") is Some(Null))
    if limited {
      assert_true(report.get("assessment_complete") is Some(False))
      assert_true(report.get("selection_state") is Some(String("not_selected")))
    } else {
      assert_true(report.get("assessment_complete") is Some(True))
      assert_true(report.get("selection_state") is Some(String("deferred")))
    }
  }
}

///|
test "strategy explanation snapshots disjoint work lines and preserves unknown and consumed quantities" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 1,
    max_work: 1000,
    max_revisions: 2,
  }).unwrap()
  let slots = [0, 1, 2, 3, 4]
  let lines : Array[@cost.SerialEstimateLine] = [
    { work_slots: slots, milliseconds: None, },
  ]
  let offers = []
  for task in [1, 2, 3] {
    offers.push(
      @strategy.prepare_task_offer(
        run,
        task,
        @connector.capability_registration_at(registry, 0).unwrap(),
        5,
        lines,
        {
          transfer_bytes: 0L,
          retained_bytes: 8000000L,
          execution_bytes: 64000000L,
        },
        100,
      ).unwrap(),
    )
  }
  slots[0] = 99
  lines[0] = { work_slots: [99], milliseconds: Some(0L), }
  assert_true(
    @strategy.revise_strategy(run, offers, registry, Some([0]))
    is Ok(Selected(_)),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  let statistics = @strategy.captured_root_statistics(run).unwrap()
  assert_eq(statistics.rows, 2)
  assert_eq(statistics.canonical_wire_bytes, 19)
  let reservation = @resources.reserve_attempt(ledger, 30L, 0L, 0L).unwrap()
  @resources.charge_transfer(ledger, reservation, 17L).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  guard @json.parse(
      @strategy.explain_captured_strategy(run, 20000, 2000).unwrap(),
    )
    is Object(report) else {
    fail("report")
  }
  assert_true(report.get("program_success") is Some(False))
  assert_true(report.get("assessment_complete") is Some(True))
  guard report.get("ledger") is Some(Object(current)) else { fail("ledger") }
  assert_true(current.get("transferred_bytes") is Some(String("17")))
  guard report.get("selection") is Some(Object(selection)) else {
    fail("selection")
  }
  assert_true(selection.get("reason") is Some(String("host_preferred")))
  guard selection.get("ledger_at_selection") is Some(Object(before)) else {
    fail("before")
  }
  assert_true(before.get("transferred_bytes") is Some(String("0")))
  guard selection.get("remaining_at_selection") is Some(Object(remaining)) else {
    fail("remaining")
  }
  assert_true(remaining.get("estimated_milliseconds") is Some(Null))
  guard selection.get("tasks") is Some(Array(tasks)) else { fail("tasks") }
  assert_eq(tasks.length(), 3)
  for task in tasks {
    guard task is Object(task) else { fail("task") }
    assert_eq(
      task.get("work_estimates"),
      Some(@json.parse("[{\"slots\":[0,1,2,3,4],\"milliseconds\":null}]")),
    )
  }
  let usage = @resources.ledger_usage(ledger)
  assert_true(@strategy.explain_captured_strategy(run, 1, 2000) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), usage)
  @strategy.close_captured_task_output(run, 0)
  assert_true(@strategy.captured_root_statistics(run) is None)
}

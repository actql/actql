///|
test "resource profiles bind implementation identity without identifying the resource by connector name" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let same_names = search_registry()
  let implementation = @connector.capability_registration_at(registry, 1).unwrap()
  let imports = Array::make(4, @strategy.ResidentImportEstimate::{
    milliseconds: Some(1L),
    transfer_bytes: 20L,
    scratch_bytes: 100L,
    table_bytes: 80L,
  })
  let first = @strategy.prepare_resident_profile(
    run,
    implementation,
    1000L,
    Some(1L),
    Some(1L),
    imports,
  ).unwrap()
  let second = @strategy.prepare_resident_profile(
    run,
    implementation,
    1000L,
    Some(1L),
    Some(1L),
    imports,
  ).unwrap()
  assert_false(physical_equal(first, second))
  assert_true(
    physical_equal(
      @strategy.resident_profile_registration(first),
      implementation,
    ),
  )
  assert_true(
    physical_equal(
      @strategy.resident_profile_registration(second),
      implementation,
    ),
  )
  let foreign = @strategy.prepare_resident_profile(
    run,
    @connector.capability_registration_at(same_names, 1).unwrap(),
    1000L,
    Some(1L),
    Some(1L),
    imports,
  ).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(1L))
  // The same run and identical descriptive name/costs do not bind another
  // registration's resource. A Local offer cannot borrow it either.
  assert_true(
    @strategy.resident_task_offer(run, offers[0], first, 100L)
    is Err(ForeignOffer(1)),
  )
  assert_true(
    @strategy.resident_task_offer(run, offers[1], foreign, 100L)
    is Err(ForeignOffer(1)),
  )
  @strategy.resident_task_offer(run, offers[1], first, 100L).unwrap() |> ignore
  @strategy.resident_task_offer(run, offers[1], second, 100L).unwrap() |> ignore
  @connector.close_capability_registry(registry)
  assert_true(
    @strategy.prepare_resident_profile(
      run,
      implementation,
      1000L,
      Some(1L),
      Some(1L),
      imports,
    )
    is Err(InvalidCapacity),
  )
}

///|
test "whole resident strategy counts one environment and one shared X import" {
  verify_resident_cost(64000000L)
}

///|
test "existing environment cleanup is charged to every remaining placement" {
  for state in ["new", "live", "closing", "settled"] {
    for unknown in [false, true] {
      verify_existing_cleanup(state, unknown)
    }
  }
}

///|
fn verify_existing_cleanup(state : String, unknown : Bool) -> Unit raise {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 10000,
    max_revisions: 4,
  }).unwrap()
  let initial = search_offers(run, registry, [1, 2, 3], Some(20L))
  @strategy.revise_strategy(run, initial, registry, None).unwrap() |> ignore
  captured_graph_local(run, 1, supplied_registry=Some(registry)).unwrap()
  let profile = @strategy.prepare_resident_profile(
    run,
    @connector.capability_registration_at(registry, 1).unwrap(),
    1000L,
    Some(5L),
    if unknown {
      None
    } else {
      Some(100L)
    },
    Array::make(4, @strategy.ResidentImportEstimate::{
      milliseconds: Some(0L),
      transfer_bytes: 20L,
      scratch_bytes: 100L,
      table_bytes: 80L,
    }),
  ).unwrap()
  let resident = []
  let local_offers = []
  for task in 2..<4 {
    let native = @strategy.prepare_task_offer(
      run,
      task,
      @connector.capability_registration_at(registry, 1).unwrap(),
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      { transfer_bytes: 100L, retained_bytes: 100L, execution_bytes: 2000L, },
      100,
    ).unwrap()
    resident.push(
      @strategy.resident_task_offer(run, native, profile, 100L).unwrap(),
    )
    local_offers.push(
      @strategy.prepare_task_offer(
        run,
        task,
        @connector.capability_registration_at(registry, 0).unwrap(),
        1,
        [{ work_slots: [0], milliseconds: Some(10L), }],
        { transfer_bytes: 0L, retained_bytes: 100L, execution_bytes: 1000L, },
        100,
      ).unwrap(),
    )
  }
  if state != "new" {
    assert_true(
      @strategy.revise_strategy(run, resident, registry, Some([0])).unwrap()
      is Selected(_),
    )
    let env = @strategy.begin_resident_environment(run, 2, 1000L).unwrap()
    @strategy.confirm_resident_environment(run, env, 1000L).unwrap()
    if state == "closing" || state == "settled" {
      @strategy.close_resident_environment(run, env).unwrap()
    }
    if state == "settled" {
      @strategy.settle_resident_environment(run, env).unwrap()
    }
  }
  let offers = resident.copy()
  for offer in local_offers {
    offers.push(offer)
  }
  let result = @strategy.revise_strategy(run, offers, registry, None).unwrap()
  let native_cost = @strategy.strategy_report_at(run, 0).unwrap().duration
  let local_cost = @strategy.strategy_report_at(run, 3).unwrap().duration
  if state == "live" {
    assert_eq(
      native_cost,
      if unknown {
        @cost.Unknown
      } else {
        @cost.Complete(102L)
      },
    )
    assert_eq(
      local_cost,
      if unknown {
        @cost.Unknown
      } else {
        @cost.Complete(120L)
      },
    )
    if !unknown {
      guard result is Selected(selected) else { abort("known selection") }
      assert_true(@strategy.strategy_resident_profile(selected, 2) is Some(_))
    }
  } else if state == "closing" {
    // Old cleanup is still owed. A proposed replacement owes its own lifecycle.
    assert_eq(
      native_cost,
      if unknown {
        @cost.Unknown
      } else {
        @cost.Complete(207L)
      },
    )
    assert_eq(
      local_cost,
      if unknown {
        @cost.Unknown
      } else {
        @cost.Complete(120L)
      },
    )
  } else {
    assert_eq(
      native_cost,
      if unknown {
        @cost.Unknown
      } else {
        @cost.Complete(107L)
      },
    )
    assert_eq(local_cost, @cost.Complete(20L))
    if !unknown {
      guard result is Selected(selected) else { abort("known selection") }
      assert_true(@strategy.strategy_resident_profile(selected, 2) is None)
    }
  }
  if unknown {
    assert_true(result is Deferred)
  }
}

///|
test "resident comparison releases last-use tables only after reserving output" {
  // X + A + B reaches 300 before X is retired. C then coexists with A and B.
  // Summing every table until DAG teardown incorrectly requires 400.
  verify_resident_cost(300L)
  verify_resident_cost(299L, resident_selected=false)
}

///|
fn verify_resident_cost(
  database_bytes : Int64,
  resident_selected? : Bool = true,
) -> Unit raise {
  let (run, _issuer) = captured_graph_fixture()
  let registry = search_registry()
  @strategy.configure_strategy_search(run, {
    max_offers: 9,
    max_strategies: 27,
    max_work: 10000,
    max_revisions: 2,
  }).unwrap()
  let profile = @strategy.prepare_resident_profile(
    run,
    @connector.capability_registration_at(registry, 1).unwrap(),
    database_bytes,
    Some(3L),
    Some(2L),
    Array::make(4, @strategy.ResidentImportEstimate::{
      milliseconds: Some(5L),
      transfer_bytes: 100L,
      scratch_bytes: 100L,
      table_bytes: 100L,
    }),
  ).unwrap()
  let offers = search_offers(run, registry, [1, 2, 3], Some(20L))
  for task in 1..<4 {
    let base = @strategy.prepare_task_offer(
      run,
      task,
      @connector.capability_registration_at(registry, 1).unwrap(),
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      {
        transfer_bytes: 10L,
        retained_bytes: 100L,
        execution_bytes: database_bytes + 100L,
      },
      100,
    ).unwrap()
    offers.push(
      @strategy.resident_task_offer(run, base, profile, 100L).unwrap(),
    )
  }
  guard @strategy.revise_strategy(run, offers, registry, None).unwrap()
    is Selected(selected) else {
    abort("expected resident selection")
  }
  let result = @strategy.strategy_assessment(selected)
  if !resident_selected {
    // Last-use release cannot be credited before B's output reservation.
    assert_not_eq(result.duration, @cost.Complete(13L))
    return
  }
  // setup 3 + one X import 5 + three tasks 3 + cleanup 2. A -> C reuses A.
  assert_eq(result.duration, @cost.Complete(13L))
  assert_eq(result.transfer_bytes, 130L)
  assert_eq(result.execution_bytes, database_bytes + 100L)
  assert_eq(result.retained_bytes, 300L)
}

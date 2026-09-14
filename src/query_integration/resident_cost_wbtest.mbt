///|
test "whole resident strategy counts one environment and one shared X import" {
  verify_resident_cost(64000000L)
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
      @planning.capability_registration_at(registry, 1).unwrap(),
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      {
        transfer_bytes: 10L,
        retained_bytes: 100L,
        execution_bytes: database_bytes + 100L,
      },
      100,
    ).unwrap()
    offers.push(@strategy.resident_task_offer(run, base, profile).unwrap())
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

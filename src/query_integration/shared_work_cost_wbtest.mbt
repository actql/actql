///|
test "shared work has arbitrary bounded slots and rejects overlapping coverage" {
  let (run, _) = captured_graph_fixture()
  let lines = [
    @cost.SerialEstimateLine::{ work_slots: [0, 2], milliseconds: Some(5L), },
    { work_slots: [1], milliseconds: Some(2L), },
  ]
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run)).planning_work
  let work = @strategy.prepare_shared_work(run, 3, lines, 8).unwrap()
  assert_eq(@strategy.shared_work_duration(work), @cost.Complete(7L))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).planning_work -
    before,
    8,
  )
  lines[0].work_slots[0] = 99
  lines.clear()
  assert_eq(@strategy.shared_work_duration(work), @cost.Complete(7L))
  assert_true(
    @strategy.prepare_shared_work(
      run,
      2,
      [
        { work_slots: [0, 1], milliseconds: Some(4L), },
        { work_slots: [1], milliseconds: Some(1L), },
      ],
      7,
    )
    is Err(Cost(DuplicateSlot(1))),
  )
  assert_true(
    @strategy.prepare_shared_work(
      run,
      3,
      [{ work_slots: [0, 1, 2], milliseconds: Some(1L), }],
      6,
    )
    is Err(OfferLimit),
  )
  assert_true(
    @strategy.prepare_shared_work(
      run,
      1,
      [{ work_slots: [0], milliseconds: Some(-1L), }],
      3,
    )
    is Err(Cost(NegativeDuration(0))),
  )
}

///|
test "missing shared work and missing durations stay unknown rather than becoming free" {
  let (run, _) = captured_graph_fixture()
  for
    lines in [
      [@cost.SerialEstimateLine::{ work_slots: [0], milliseconds: Some(0L), }],
      [{ work_slots: [0, 1], milliseconds: None, }],
      [],
    ] {
    let work = @strategy.prepare_shared_work(run, 2, lines, 10).unwrap()
    assert_eq(@strategy.shared_work_duration(work), @cost.Unknown)
  }
  assert_eq(
    @strategy.shared_work_duration(
      @strategy.prepare_shared_work(run, 0, [], 0).unwrap(),
    ),
    @cost.Complete(0L),
  )
}

///|
test "shared preparation copy and cleanup inventories compose without charging shared X twice" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 1).unwrap()
  let preparation_lines : Array[@cost.SerialEstimateLine] = [
    { work_slots: [0, 2], milliseconds: Some(5L), },
    { work_slots: [1], milliseconds: Some(2L), },
  ]
  let preparation = @strategy.prepare_shared_work(run, 3, preparation_lines, 8).unwrap()
  preparation_lines[0].work_slots[0] = 99
  preparation_lines.clear()
  let cleanup = @strategy.prepare_shared_work(
    run,
    2,
    [{ work_slots: [0, 1], milliseconds: Some(11L), }],
    5,
  ).unwrap()
  let copying = @strategy.prepare_shared_work(
    run,
    3,
    [
      { work_slots: [0, 1], milliseconds: Some(3L), },
      { work_slots: [2], milliseconds: Some(2L), },
    ],
    8,
  ).unwrap()
  let profile = @strategy.prepare_resident_profile(
    run,
    @connector.prepare_resource_binding(registry, registration).unwrap(),
    1000L,
    preparation,
    cleanup,
    Array::make(4, @strategy.ResidentImportEstimate::{
      work: copying,
      transfer_bytes: 20L,
      scratch_bytes: 100L,
      table_bytes: 80L,
    }),
  ).unwrap()
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 1,
    max_work: 10000,
    max_revisions: 1,
  }).unwrap()
  let offers = [1, 2, 3].map(task => {
    let base = @strategy.prepare_task_offer(
      run,
      task,
      registration,
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      { transfer_bytes: 100L, retained_bytes: 100L, execution_bytes: 2000L, },
      100,
    ).unwrap()
    @strategy.resident_task_offer(run, base, profile, 100L).unwrap()
  })
  assert_true(
    @strategy.revise_strategy(run, offers, registry, None) is Ok(Selected(_)),
  )
  let assessment = @strategy.strategy_assessment(
    @strategy.captured_dag_strategy(run).unwrap(),
  )
  // Preparation 7 + cleanup 11 + one X copy 5 + three tasks 3.
  assert_eq(assessment.duration, @cost.Complete(26L))
  assert_eq(assessment.transfer_bytes, 320L)
  guard @json.parse(
      @strategy.explain_captured_strategy(run, 20000, 2000).unwrap(),
    )
    is Object(report) else {
    fail("report")
  }
  guard report.get("selection") is Some(Object(selection)) else {
    fail("selection")
  }
  guard selection.get("tasks") is Some(Array(tasks)) else { fail("tasks") }
  guard tasks[0] is Object(first) else { fail("first task") }
  guard first.get("resident_profile") is Some(Object(resource)) else {
    fail("resource profile")
  }
  assert_eq(
    resource.get("preparation_work"),
    Some(
      @json.parse(
        "{\"required_slots\":3,\"lines\":[{\"slots\":[0,2],\"milliseconds\":\"5\"},{\"slots\":[1],\"milliseconds\":\"2\"}]}",
      ),
    ),
  )
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
}

///|
test "shared work cannot smuggle another graph owner into a resource profile" {
  let (run, _) = captured_graph_fixture()
  let (foreign, _) = captured_graph_fixture()
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 1).unwrap()
  let owned = @strategy.prepare_shared_work(run, 0, [], 0).unwrap()
  let other = @strategy.prepare_shared_work(foreign, 0, [], 0).unwrap()
  let imports = Array::make(4, @strategy.ResidentImportEstimate::{
    work: owned,
    transfer_bytes: 20L,
    scratch_bytes: 100L,
    table_bytes: 80L,
  })
  assert_true(
    @strategy.prepare_resident_profile(
      run,
      @connector.prepare_resource_binding(registry, registration).unwrap(),
      1000L,
      other,
      owned,
      imports,
    )
    is Err(InvalidCapacity),
  )
  assert_true(
    @strategy.prepare_resident_profile(
      run,
      @connector.prepare_resource_binding(registry, registration).unwrap(),
      1000L,
      owned,
      other,
      imports,
    )
    is Err(InvalidCapacity),
  )
  imports[0] = { ..imports[0], work: other, }
  assert_true(
    @strategy.prepare_resident_profile(
      run,
      @connector.prepare_resource_binding(registry, registration).unwrap(),
      1000L,
      owned,
      owned,
      imports,
    )
    is Err(InvalidCapacity),
  )
}

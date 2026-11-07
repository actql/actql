///|
test "exact Direct source read rejects wrong coordinates and retains the same Effect Run Ledger" {
  let plan = effect_operation_source_plan_fixture()
  guard plan.direct_occurrences is Some(selected) else {
    fail("missing original Direct inventory")
  }
  assert_true(
    @publication_host.client_direct_acquisition_occurrences_match_effect_program(
      selected,
      plan.prepared,
    ),
  )
  let (input, initial, _, parent) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    parent,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  assert_true(
    begin_installed_managed_run_source_read_at(run, 1, 0, 0)
    is Err(ForeignOriginal),
  )
  assert_true(
    begin_installed_managed_run_source_read_at(run, 0, 1, 0)
    is Err(ForeignOriginal),
  )
  assert_true(
    begin_installed_managed_run_source_read_at(run, 0, 0, 1) is Err(Unsupported),
  )
  assert_true(run.reads[0] is None)
  let read = begin_installed_managed_run_source_read_at(run, 0, 0, 0).unwrap()
  assert_true(
    read.managed_run is Some((original, task)) &&
    physical_equal(original, run) &&
    task == 0,
  )
  assert_true(
    read.ledger is Some(ledger) &&
    run.ledger is Some(original) &&
    physical_equal(ledger, original),
  )
  let (declaration, requirement, acquisition, _) = prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  assert_true(
    attach_installed_source_read_acquisition(
      read, declaration, requirement, acquisition, 1, 0,
    )
    is Err(ForeignOriginal),
  )
  attach_installed_source_read_acquisition(
    read, declaration, requirement, acquisition, 0, 0,
  ).unwrap()
  assert_true(
    begin_installed_managed_run_source_read_at(run, 0, 0, 0)
    is Err(AlreadyBound),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_true(
    begin_installed_managed_run_source_read_at(run, 0, 0, 0) is Err(Retired),
  )
}

///|
test "Direct selector layout includes growing inventory and temporary capture slots" {
  assert_true(installed_direct_occurrences_layout(-1) is None)
  let empty = installed_direct_occurrences_layout(0).unwrap()
  let single = installed_direct_occurrences_layout(1).unwrap()
  let pair = installed_direct_occurrences_layout(2).unwrap()
  assert_true(empty.0 == empty.1 && empty.0 > 0L)
  assert_true(single.0 > empty.0 && single.1 > single.0)
  assert_true(pair.0 > single.0 && pair.1 > single.1)
}

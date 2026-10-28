///|
fn registration_tail_fixture(
  failed? : Bool = false,
) -> (SourceRegistrationRead, Int) raise {
  let read = if failed {
    // This existing authored member has exactly12 nodes. It completes its
    // original Snapshot, leaving0 nodes for the subsequent declaration read.
    snapshot_emission_registration_read(max_local_nodes=12)
  } else {
    let (source, catalog, limits, _) = registration_read_fixture()
    begin_source_registration(
      source,
      catalog,
      limits,
      max_inputs=2,
      max_views=100,
      max_order_keys=100,
    ).unwrap()
  }
  assert_true(source_registration_local_tail_work(read) is None)
  assert_eq(advance_source_registration(read), RegistrationSelect)
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  assert_eq(advance_source_registration(read), RegistrationLocal)
  let local_maximum = source_registration_local_entry_work_bound(read).unwrap()
  let mut steps = 0
  while source_registration_local_phase(read) !=
        Some(@local_inputs.LocalEnvironmentDeclaration) {
    assert_true(steps < 10)
    assert_eq(advance_source_registration(read), RegistrationLocal)
    assert_true(source_registration_local_tail_work(read) is None)
    steps += 1
  }
  (read, local_maximum)
}

///|
test "Source forwards original successful Local tail debit once and retains its observation through transfer" {
  let (read, maximum) = registration_tail_fixture()
  let bound = source_registration_local_tail_work_bound(read).unwrap()
  let mut total = 0
  let mut calls = 0
  while source_registration_phase(read) == RegistrationLocal {
    assert_true(calls < 8)
    advance_source_registration(read) |> ignore
    let spent = source_registration_local_tail_work(read).unwrap()
    assert_true(spent >= 0)
    total += spent
    assert_true(total <= bound)
    calls += 1
  }
  assert_eq(calls, 5) // Two original declaration/reconciliation pairs and assembly.
  assert_eq(source_registration_phase(read), RegistrationComplete)
  let original = source_registration_local_tail_work(read)
  let (_, locals) = take_source_registration_result(read).unwrap().unwrap()
  assert_eq(
    @local_inputs.program_environment_usage(locals).work,
    maximum - bound + total,
  )
  assert_true(
    physical_equal(source_registration_local_tail_work(read), original),
  )
  clear_source_registration(read)
  assert_true(
    physical_equal(source_registration_local_tail_work(read), original),
  )
  assert_eq(source_registration_phase(read), RegistrationTransferred)
}

///|
test "Source leaves failed Local tail Usage absent without manufacturing a zero receipt" {
  let (read, _) = registration_tail_fixture(failed=true)
  assert_eq(advance_source_registration(read), RegistrationFailed)
  assert_eq(
    source_registration_local_failure_phase(read),
    Some(@local_inputs.LocalEnvironmentDeclaration),
  )
  assert_true(source_registration_local_tail_work(read) is None)
  assert_true(
    take_source_registration_result(read) is Some(Err(LocalInputs(Stage(0, _)))),
  )
  assert_true(take_source_registration_result(read) is None)
  clear_source_registration(read)
  assert_true(source_registration_local_tail_work(read) is None)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
}

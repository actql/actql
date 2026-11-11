///|
// Actual Common Mock/Task/Run/consumer owners with explicit synthetic physical
// and Account fixtures. No installed recipe, public Allow or real Provider is
// supplied. The same larger Ledger also retains an independent live sibling.
fn shared_mock_test_parent() -> @resources.LedgerLimits {
  let base = standard_limits().model.ledger
  {
    planning_work: 10100,
    attempts: 5,
    holdings: 101,
    transfer_bytes: 134072L,
    retained_bytes: base.retained_bytes + 1000L,
    execution_bytes: base.execution_bytes + 1000L,
  }
}

///|
fn shared_mock_test_finish(
  active : Execution,
  installation : @model.ModelMockInstallation,
  profile : @environment.ModelMockProfile,
  read : @publication_host.ClientModelReadPreparation,
  ledger : @resources.Ledger,
  sibling : @resources.CapacityReservation,
) -> Unit raise {
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.retire_original_model_mock(installation), Ok(true))
  assert_true(@environment.retire_model_mock_profile(profile))
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(@resources.capacity_reservation_open(sibling))
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true) is Ok(false),
  )
  @resources.settle_capacity(ledger, sibling).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
}

///|
test "shared original Mock keeps the same larger Run Ledger and typed result without retiring a sibling" {
  let calls = Ref(0)
  let sibling : Ref[@resources.CapacityReservation?] = Ref(None)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
    shared_parent=Some(shared_mock_test_parent()),
    shared_sibling=Some(sibling),
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work, 17)
  let work = match fixture_finish(active, initial_work=active.work) {
    Settling(_, work~) => work
    _ => abort("the original Mock must retain its one original settlement")
  }
  assert_eq(calls.val, 1)
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  let saved = capture(active).unwrap()
  assert_eq(saved.captures.length(), 1)
  assert_eq(saved.captures[0].provider_id, "mock")
  assert_true(
    saved.captures[0].value.value is @admitted.Object(fields) &&
    @admitted.element_at(fields, 1) is Some(("risk", @admitted.Text("low"))),
  )
  assert_true(@resources.capacity_reservation_open(sibling.val.unwrap()))
  shared_mock_test_finish(
    active,
    installation,
    profile,
    read,
    ledger,
    sibling.val.unwrap(),
  )
}

///|
test "shared original Mock retains its wire ceiling without physical transfer uncertainty" {
  let calls = Ref(0)
  let sibling : Ref[@resources.CapacityReservation?] = Ref(None)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
    shared_parent=Some(shared_mock_test_parent()),
    shared_sibling=Some(sibling),
  )
  let work = match fixture_finish(active, initial_work=active.work) {
    Settling(_, work~) => work
    _ => abort("the original Mock must retain its original settlement")
  }
  assert_eq(calls.val, 1)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).uncertain_transfer_bytes, 0L)
  // The original request/response ceiling remains reserved until cleanup;
  // knowing this implementation performs no I/O is not early retirement.
  assert_eq(@resources.ledger_usage(ledger).reserved_transfer_bytes, 66536L)
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  shared_mock_test_finish(
    active,
    installation,
    profile,
    read,
    ledger,
    sibling.val.unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).uncertain_transfer_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_transfer_bytes, 0L)
}

///|
test "shared original Mock preserves Unknown entry without inventing physical transfer" {
  let calls = Ref(0)
  let sibling : Ref[@resources.CapacityReservation?] = Ref(None)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
    entry_unknown=true,
    shared_parent=Some(shared_mock_test_parent()),
    shared_sibling=Some(sibling),
  )
  assert_true(
    fixture_finish(active, initial_work=active.work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  assert_true(@model.model_execution_unknown_calls(active.model.unwrap()))
  assert_true(capture(active) is None)
  assert_eq(calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).uncertain_transfer_bytes, 0L)
  assert_true(advance(active, 1) is Err(InvalidAdvance))
  shared_mock_test_finish(
    active,
    installation,
    profile,
    read,
    ledger,
    sibling.val.unwrap(),
  )
  assert_eq(calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger).uncertain_transfer_bytes, 0L)
}

///|
test "shared original Mock preserves Model attempts wire and retention caps despite larger Run capacity" {
  let base = standard_limits().model.ledger
  for
    (purpose, issue) in [
      (
        { ..base, attempts: 0, transfer_bytes: 133072L, },
        @resources.AttemptLimit,
      ),
      (
        // The unchanged fixture Host caps request bytes at 1000; response
        // bounds remain 65536. This is one byte below their actual sum.
        { ..base, attempts: 4, transfer_bytes: 66535L, },
        @resources.TransferLimit,
      ),
      (
        { ..base, attempts: 4, transfer_bytes: 133072L, retained_bytes: 100L, },
        @resources.RetentionLimit,
      ),
    ] {
    let calls = Ref(0)
    let sibling : Ref[@resources.CapacityReservation?] = Ref(None)
    let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
      calls,
      shared_parent=Some(shared_mock_test_parent()),
      shared_sibling=Some(sibling),
      purpose_ledger=Some(purpose),
      expected_purpose_issue=Some(issue),
    )
    assert_eq(calls.val, 0)
    assert_eq(@resources.ledger_usage(ledger).attempts, 0)
    assert_true(active.phase is Terminal)
    assert_eq(@resources.ledger_usage(ledger).planning_work, 17)
    shared_mock_test_finish(
      active,
      installation,
      profile,
      read,
      ledger,
      sibling.val.unwrap(),
    )
  }
}

///|
test "shared original Mock publication keeps parent live bytes and its own planning cap on the same Run" {
  let base = standard_limits().model.ledger
  let purpose = {
    ..base,
    planning_work: 1,
    attempts: 4,
    transfer_bytes: 133072L,
    retained_bytes: 300000L,
    execution_bytes: 6L,
  }
  let calls = Ref(0)
  let sibling : Ref[@resources.CapacityReservation?] = Ref(None)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
    shared_parent=Some(shared_mock_test_parent()),
    shared_sibling=Some(sibling),
    purpose_ledger=Some(purpose),
  )
  let work = match fixture_finish(active, initial_work=active.work) {
    Settling(_, work~) => work
    _ => abort("the original Mock must await its original settlement")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  assert_eq(calls.val, 1)
  let model = active.model.unwrap()
  let scope = active.call_scope.unwrap()
  // Settlement acknowledgement does not retire the original attempt metadata.
  // Retain 1000 request + 65536 response + 81920 Entry/evidence bytes, in
  // addition to Model startup 100, bootstrap/read 3+7 and sibling 20.
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 148586L)
  // Original bootstrap2 + read5 + Model startup5 + independent sibling10.
  // This fixture has no physical preflight workspace on its Mock attempt.
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 22L)
  let parent = shared_mock_test_parent()
  // Publication is a separate original Host lifetime on the SAME parent. Its
  // bytes do not consume Model call/output ceilings (300000/6 above), while
  // the existing publication planning step still has that purpose's cap1.
  // Fill exactly the independently inventoried parent remainder, then reject
  // one extra byte without changing usage. No ceiling is raised here.
  let retained = parent.retained_bytes - 148586L
  let workspace = parent.execution_bytes - 22L
  let grant = @model.reserve_original_model_publication_capacity(
    model, scope, retained, workspace,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @model.reserve_original_model_publication_capacity(model, scope, 1L, 0L)
    is Err(@model.Ledger(@resources.RetentionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @model.charge_original_model_observation_step(grant).unwrap()
  assert_true(
    @model.charge_original_model_observation_step(grant)
    is Err(@model.Ledger(@resources.PlanningLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work, 18)
  assert_true(@resources.capacity_reservation_open(sibling.val.unwrap()))
  assert_true(
    @model.release_original_model_publication_capacity(grant).unwrap(),
  )
  assert_false(
    @model.original_model_publication_capacity_current(grant, model, scope),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @model.reserve_original_model_publication_capacity(
      model,
      scope,
      1L,
      workspace + 1L,
    )
    is Err(@model.Ledger(@resources.ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let next = @model.reserve_original_model_publication_capacity(
    model, scope, 1L, workspace,
  ).unwrap()
  assert_true(@model.release_original_model_publication_capacity(next).unwrap())
  shared_mock_test_finish(
    active,
    installation,
    profile,
    read,
    ledger,
    sibling.val.unwrap(),
  )
}

///|
test "original Mock never erases another entered attempt's uncertain wire history" {
  let calls = Ref(0)
  let sibling : Ref[@resources.CapacityReservation?] = Ref(None)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
    shared_parent=Some(shared_mock_test_parent()),
    shared_sibling=Some(sibling),
  )
  // A distinct original reservation models prior Host responsibility on this
  // shared Run. Settling its capacity must not refund uncertain sent history.
  let prior = @resources.reserve_attempt(ledger, 1L, 0L, 0L).unwrap()
  @resources.mark_transfer_uncertain(ledger, prior, 1L).unwrap()
  @resources.settle_reservation(ledger, prior).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).uncertain_transfer_bytes, 1L)
  let work = match fixture_finish(active, initial_work=active.work) {
    Settling(_, work~) => work
    _ => abort("the original Mock must retain its settlement")
  }
  assert_eq(calls.val, 1)
  assert_eq(@resources.ledger_usage(ledger).attempts, 2)
  assert_eq(@resources.ledger_usage(ledger).uncertain_transfer_bytes, 1L)
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  assert_eq(@resources.ledger_usage(ledger).attempts, 2)
  assert_eq(calls.val, 1)
  shared_mock_test_finish(
    active,
    installation,
    profile,
    read,
    ledger,
    sibling.val.unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 2)
  assert_eq(@resources.ledger_usage(ledger).uncertain_transfer_bytes, 1L)
}

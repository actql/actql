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
test "shared original Mock preserves Model attempts wire and retention caps despite larger Run capacity" {
  let base = standard_limits().model.ledger
  for
    (purpose, issue) in [
      (
        { ..base, attempts: 0, transfer_bytes: 133072L, },
        @resources.AttemptLimit,
      ),
      (
        { ..base, attempts: 4, transfer_bytes: 131071L, },
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

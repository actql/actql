///|
// The typed input must come from the real bundled contract admission. Early
// refusal cases retain invalid values below so reaching configuration still
// cannot turn their denial/foreign/unresolved/claimed-start oracles into a pass.
fn native_values_work_test_installed_contracts() -> @local.ClientInstalledSequenceContracts {
  let assets = @host.client_local_product_assets()
  @local.prepare_installed_sequence_contracts(
    assets.registry, assets.values, Some(assets.fragment), assets.ordered,
  ).unwrap()
}

///|
// Matching Native definitions are separate from public CLI process acceptance.
test "Native Local Values profile accepts source-free original preparation" {
  let (_, prepared, _, _) = journal_test_run(
    "values-profile", "values-profile-run",
  )
  assert_true(native_client_local_values_profile_supported(prepared))
  assert_false(@resident.resident_source_compute_shape_supported(prepared))
}

///|
test "Native Local Values work rejects current denial before binding any Run" {
  let database = epoch_test_database("values-denied-before-bind")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "values-denied", "values-denied-run",
  )
  let failure = open_native_client_local_values_work(
    journal,
    request,
    prepared,
    compiled,
    definition,
    native_values_work_test_installed_contracts(),
    "{}",
    None,
    None,
    16,
    1000,
    () => false,
  ).unwrap_err()
  assert_true(
    native_client_values_work_failure_issue(failure) is AuthorizationDenied,
  )
  assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
  assert_true(failure.close())
  assert_true(failure.close())
  database.close_checked().unwrap()
}

///|
test "Native Local Values work rejects foreign original Run before configuration or start" {
  let database = epoch_test_database("values-foreign-original")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "values-original", "values-original-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let (_, _, _, foreign) = journal_test_run("values-original", "other-run")
  let failure = open_native_client_local_values_work(
    journal,
    request,
    prepared,
    compiled,
    foreign,
    native_values_work_test_installed_contracts(),
    "{}",
    None,
    None,
    16,
    1000,
    () => true,
  ).unwrap_err()
  assert_true(
    native_client_values_work_failure_issue(failure) is Journal(ForeignRun),
  )
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("Original Run lost")
  }
  assert_eq(
    @publication.publication_contract_identity(record.definition),
    @publication.publication_contract_identity(definition),
  )
  assert_false(record.physical_start_claimed)
  assert_true(failure.close())
  database.close_checked().unwrap()
}

///|
test "Native Local Values work never fills unresolved original Run history" {
  let database = epoch_test_database("values-unresolved-original")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "values-unresolved", "values-unresolved-run",
  )
  let failure = open_native_client_local_values_work(
    journal,
    request,
    prepared,
    compiled,
    definition,
    native_values_work_test_installed_contracts(),
    "{}",
    None,
    None,
    16,
    1000,
    () => true,
  ).unwrap_err()
  assert_true(
    native_client_values_work_failure_issue(failure)
    is Start(NeedsOriginalReconciliation),
  )
  assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
  assert_true(failure.close())
  database.close_checked().unwrap()
}

///|
test "Native Local Values work never repeats a previously claimed physical start" {
  let database = epoch_test_database("values-claimed-original")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "values-claimed", "values-claimed-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  claim_native_client_retained_work_first_start(journal, request, () => true).unwrap()
  |> ignore
  let failure = open_native_client_local_values_work(
    journal,
    request,
    prepared,
    compiled,
    definition,
    native_values_work_test_installed_contracts(),
    "{}",
    None,
    None,
    16,
    1000,
    () => true,
  ).unwrap_err()
  assert_true(
    native_client_values_work_failure_issue(failure)
    is Start(NeedsOriginalReconciliation),
  )
  assert_true(failure.close())
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("Original start lost")
  }
  assert_true(record.physical_start_claimed)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  database.close_checked().unwrap()
}

///|
test "Native Local Values uses current submit authority without borrowing Source read" {
  for (submit, expected) in [(true, true), (false, false)] {
    let host = local_source_authority_fixture(
      "values-authority-" + submit.to_string(),
      submit,
      false,
    )
    let crypto = epoch_test_crypto()
    let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
    let (request, _, _, _) = journal_test_run(
      "values-account",
      "values-account-run",
      scope~,
    )
    assert_eq(
      native_local_policy_authority(
        host,
        crypto,
        "operator",
        "cli",
        request,
        None,
      )
      is Ok(_),
      expected,
    )
    host.close().unwrap()
    assert_true(
      native_local_policy_authority(
        host,
        crypto,
        "operator",
        "cli",
        request,
        None,
      )
      is Err(_),
    )
  }
}

///|
test "Native Local Values retains the supplied Ledger and never replaces an exhausted one" {
  // Ledger limits below are nominal Resource test fixtures, not physical Native
  // funding or an installed command profile. The Journal is the real fixture.
  let assets = @host.client_local_product_assets()
  let installed = @local.prepare_installed_sequence_contracts(
    assets.registry, assets.values, Some(assets.fragment), assets.ordered,
  ).unwrap()
  for supplied in [false, true] {
    let suffix = supplied.to_string()
    let database = epoch_test_database("values-supplied-ledger-" + suffix)
    initialize_native_client_run_journal(database).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let (request, prepared, compiled, definition) = journal_test_run(
      "values-supplied-" + suffix,
      "values-supplied-run-" + suffix,
    )
    journal.bind_run(request, prepared, compiled, definition, true).unwrap()
    |> ignore
    let quoted = @local.single_source_free_local_ledger_limits(
      prepared,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    let limits = if supplied {
      quoted
    } else {
      {
        planning_work: 0,
        attempts: 0,
        holdings: 0,
        transfer_bytes: 0L,
        retained_bytes: 0L,
        execution_bytes: 0L,
      }
    }
    let ledger = @resources.create_ledger(limits).unwrap()
    let before = @resources.ledger_usage(ledger)
    let work = open_native_client_local_values_work(
      journal,
      request,
      prepared,
      compiled,
      definition,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      16,
      1000,
      () => true,
      ledger=Some(ledger),
    )
    if supplied {
      let work = work.unwrap()
      assert_true(
        physical_equal(@strategy.captured_dag_ledger(work.run), ledger),
      )
      assert_true(work.close())
      guard journal.lookup(request, true) is Ok(Retained(record)) else {
        fail("Original Run lost")
      }
      assert_true(record.physical_start_claimed)
    } else {
      let failure = work.unwrap_err()
      assert_true(
        native_client_values_work_failure_issue(failure) is Configuration,
      )
      assert_eq(@resources.ledger_usage(ledger), before)
      guard journal.lookup(request, true) is Ok(Retained(record)) else {
        fail("Original Run lost")
      }
      assert_false(record.physical_start_claimed)
      assert_true(failure.close())
    }
    database.close_checked().unwrap()
  }
}

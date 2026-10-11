///|
// An original accepted Source-free Effect is intentional here. The real Host
// must refuse unsupported acquisition without claiming a start. These cases
// do not establish Source execution, approved Effect dispatch or CLI acceptance.
fn local_effect_source_authority_fixture(
  name : String,
  submit : Bool,
  read : Bool,
) -> (
  NativeLocalHostConnection,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  Int64,
) raise {
  let host = local_source_authority_fixture(name, submit, read)
  let scope = host
    .authority_scope_cid("operator", "cli", epoch_test_crypto())
    .unwrap()
  let authority = host.epoch_authority().unwrap()
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "original-submit",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    native_client_effect_fixture_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = native_client_effect_fixture_preparation(intent)
  let (request, allowed, definition) = native_client_effect_fixture_run(
    preparation,
    reference,
    "original-effect",
    scope~,
  )
  let journal = host.run_journal().unwrap()
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  // Trusted fixture setup retains the original Run even for later authority
  // denial; the production acquisition entry still rechecks the real Host.
  journal
  .accept_submitted_effect_run(
    authority, reference, preparation, request, allowed, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("original Effect Run missing")
  }
  (host, request, allowed, definition, record.revision)
}

///|
test "Native Local Effect Source preflight requires independent submit and Source read before claiming work" {
  for
    (submit, read, denied) in [
      (false, false, true),
      (true, false, true),
      (false, true, true),
      (true, true, false),
    ] {
    let (host, request, allowed, definition, revision) = local_effect_source_authority_fixture(
      "local-effect-source-authority-" +
      submit.to_string() +
      "-" +
      read.to_string(),
      submit,
      read,
    )
    let result = host.check_effect_source_work(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      allowed,
      definition,
      "connector://crm/main/r#v",
    )
    if denied {
      assert_true(result is Err(AuthorizationDenied))
    } else {
      assert_true(result is Err(Work(UnsupportedGraph)))
    }
    guard host.journal.lookup(request, true) is Ok(Retained(record)) else {
      fail("preflight lost the original Effect Run")
    }
    assert_eq(record.revision, revision)
    assert_false(record.dispatch_reserved)
    assert_false(record.physical_start_claimed)
    assert_true(record.checkpoint is None)
    host.close().unwrap()
  }
}

///|
test "Native Local Effect Source preflight refuses foreign caller Source and lost adoption custody" {
  let (host, request, allowed, definition, revision) = local_effect_source_authority_fixture(
    "local-effect-source-foreign", true, true,
  )
  for
    (principal, connection, source) in [
      ("other", "cli", "connector://crm/main/r#v"),
      ("operator", "other", "connector://crm/main/r#v"),
      ("operator", "cli", "connector://crm/main/other#v"),
    ] {
    assert_true(
      host.check_effect_source_work(
        epoch_test_crypto(),
        principal,
        connection,
        request,
        allowed,
        definition,
        source,
      )
      is Err(AuthorizationDenied),
    )
  }
  guard host.journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("foreign preflight lost the original Effect Run")
  }
  assert_eq(record.revision, revision)
  assert_false(record.dispatch_reserved)
  assert_false(record.physical_start_claimed)
  let table = @utf8.encode("client_local_adoption")
  let key = @utf8.encode("adoption")
  assert_true(
    submitted_test_remove_record(
      host.database,
      table,
      table.length(),
      key,
      key.length(),
    ),
  )
  assert_true(
    host.check_effect_source_work(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      allowed,
      definition,
      "connector://crm/main/r#v",
    )
    is Err(AuthorizationDenied),
  )
  assert_true(host.check_binding() is Err(CustodyLost))
  assert_true(
    host.database.read("client_local_adoption", "adoption")
    is Err(@sqlite.NotFound),
  )
  host.close().unwrap()
}

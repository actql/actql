///|
fn named_host_test_reference(
  host : NativeLocalHostConnection,
  nonce : String,
) -> NativeClientSubmissionReference {
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let allowed = host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "submit",
    })
    is Ok(@authorization.Allow(_))
  let epoch = host.epoch.issue_epoch(scope, allowed, 1000.0).unwrap()
  prepare_native_client_submission_reference(epoch, nonce).unwrap()
}

///|
fn named_host_test_reopen(label : String) -> NativeLocalHostConnection {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/" +
    label +
    ".parent"
  begin_native_local_host_adoption(
    path,
    "host",
    path,
    "account.json",
    "operator",
    epoch_test_crypto(),
  )
  .unwrap()
  .open_journal(
    local_journal_test_library(),
    epoch_test_crypto(),
    100.0,
    8,
    8388608L,
  )
  .unwrap()
}

///|
test "Native named Host selects original Local namespace and authenticated actor" {
  let host = policy_reuse_host_fixture("named-host-coordinates")
  let crypto = epoch_test_crypto()
  let candidate = named_host_test_reference(host, "candidate")
  let intent = submitted_test_intent("SELECT 1 AS n")
  let result = host.resolve_or_bind_submitted_name(
    crypto,
    "operator",
    "cli",
    "public-name",
    intent,
    Some(candidate),
    1001.0,
  )
  let row = host.database.scan_after("client_submission_names", "").unwrap()
  let parsed = @host.decode_client_submitted_name_row(row.body).unwrap()
  let (key, scope, request_id, intent_cid) = @host.client_submitted_name_binding_fields(
    parsed.binding,
  )
  assert_true(result is Ok(NamedSubmission(true, _)))
  // Independent SHA256 of ["local","operator","public-name"], not caller DATA.
  assert_eq(
    row.key,
    "338eeea44c71d34c0ed48f1ff5b501daf5525d6e3af7536f2040425965aba2f6",
  )
  assert_eq(
    @host.client_submitted_name_key_fields(key),
    ("local", "operator", "public-name"),
  )
  assert_eq(scope, host.authority_scope_cid("operator", "cli", crypto).unwrap())
  assert_eq(request_id, candidate.request_id)
  assert_eq(intent_cid, @host.client_submitted_intent_cid(intent))
  assert_eq(host.journal.submitted_intent_custody().unwrap().0, 1)
  assert_eq(run_journal_custody(host.database, 8).unwrap().0, 0)
  host.close().unwrap()
}

///|
test "Native named Host observes the expired original before a foreign candidate" {
  let label = "named-host-original"
  let host = policy_reuse_host_fixture(label)
  let other = policy_reuse_host_fixture("named-host-other")
  let crypto = epoch_test_crypto()
  let candidate = named_host_test_reference(host, "original")
  let foreign = named_host_test_reference(other, "foreign")
  let intent = submitted_test_intent("SELECT 1 AS n")
  host
  .resolve_or_bind_submitted_name(
    crypto,
    "operator",
    "cli",
    "name",
    intent,
    Some(candidate),
    1001.0,
  )
  .unwrap()
  |> ignore
  host.close().unwrap()
  let host = named_host_test_reopen(label)
  guard host.resolve_or_bind_submitted_name(
      crypto,
      "operator",
      "cli",
      "name",
      intent,
      Some(foreign),
      5000.0,
    )
    is Ok(NamedSubmission(false, original)) else {
    other.close().unwrap()
    host.close().unwrap()
    fail("same original name unavailable")
  }
  assert_eq(original.reference.wire, candidate.wire)
  assert_true(native_client_submitted_run_admission(original) is None)
  assert_eq(host.journal.submitted_intent_custody().unwrap().0, 1)
  other.close().unwrap()
  host.close().unwrap()
}

///|
test "Native named Host current principal or connection deny has no clock or name mutation" {
  for foreign_principal in [false, true] {
    let host = policy_reuse_host_fixture(
      "named-host-deny-" + foreign_principal.to_string(),
    )
    let candidate = named_host_test_reference(host, "candidate")
    let before = host.database
      .read("client_submission_epoch", "authority")
      .unwrap()
    let result = host.resolve_or_bind_submitted_name(
      epoch_test_crypto(),
      if foreign_principal {
        "foreign"
      } else {
        "operator"
      },
      if foreign_principal {
        "cli"
      } else {
        "foreign"
      },
      "name",
      submitted_test_intent("SELECT 1 AS n"),
      Some(candidate),
      5000.0,
    )
    assert_true(result is Err(AuthorizationDenied))
    let after = host.database
      .read("client_submission_epoch", "authority")
      .unwrap()
    assert_eq(after.revision, before.revision)
    assert_eq(after.body, before.body)
    assert_eq(host.journal.submitted_name_control().unwrap().0, 0)
    host.close().unwrap()
  }
}

///|
test "Native named Host closed lifetime or foreign candidate never creates an original" {
  let host = policy_reuse_host_fixture("named-host-foreign-candidate")
  let other = policy_reuse_host_fixture("named-host-foreign-issuer")
  let candidate = named_host_test_reference(other, "candidate")
  let intent = submitted_test_intent("SELECT 1 AS n")
  assert_true(
    host.resolve_or_bind_submitted_name(
      epoch_test_crypto(),
      "operator",
      "cli",
      "name",
      intent,
      Some(candidate),
      1001.0,
    )
    is Err(Epoch(Unverifiable)),
  )
  assert_eq(host.journal.submitted_name_control().unwrap().0, 0)
  other.close().unwrap()
  host.close().unwrap()
  assert_true(
    host.resolve_or_bind_submitted_name(
      epoch_test_crypto(),
      "operator",
      "cli",
      "name",
      intent,
      None,
      1002.0,
    )
    is Err(AuthorizationDenied),
  )
}

///|
test "Native named Host preserves conflict priority and never reclaims an occupied name" {
  let host = policy_reuse_host_fixture("named-host-conflict")
  let crypto = epoch_test_crypto()
  let candidate = named_host_test_reference(host, "candidate")
  host
  .resolve_or_bind_submitted_name(
    crypto,
    "operator",
    "cli",
    "name",
    submitted_test_intent("SELECT 1 AS n"),
    Some(candidate),
    1001.0,
  )
  .unwrap()
  |> ignore
  assert_true(
    host.resolve_or_bind_submitted_name(
      crypto,
      "operator",
      "cli",
      "name",
      submitted_test_intent("SELECT 2 AS n"),
      None,
      1002.0,
    )
    is Err(ChangedIntent),
  )
  assert_eq(host.journal.submitted_name_control().unwrap().0, 1)
  assert_eq(host.journal.submitted_intent_custody().unwrap().0, 1)
  host.close().unwrap()
}

///|
test "Native named Host COMMIT ambiguity keeps Unknown and reconciles without another submission" {
  for reply_lost in [false, true] {
    let label = "named-host-unknown-" + reply_lost.to_string()
    let host = policy_reuse_host_fixture(label)
    let crypto = epoch_test_crypto()
    let candidate = named_host_test_reference(host, "candidate")
    let intent = submitted_test_intent("SELECT 1 AS n")
    submitted_test_fail_commit_after(host.database, 1, reply_lost)
    assert_true(
      host.resolve_or_bind_submitted_name(
        crypto,
        "operator",
        "cli",
        "name",
        intent,
        Some(candidate),
        1001.0,
      )
      is Err(TransactionUnknown),
    )
    assert_true(host.database.transaction_fenced())
    if !reply_lost {
      host.database.rollback().unwrap()
    }
    host.close().unwrap()
    let host = named_host_test_reopen(label)
    let result = host
      .resolve_or_bind_submitted_name(
        crypto,
        "operator",
        "cli",
        "name",
        intent,
        None,
        1002.0,
      )
      .unwrap()
    if reply_lost {
      guard result is NamedSubmission(false, original) else {
        host.close().unwrap()
        fail("lost reply original unavailable")
      }
      assert_eq(original.reference.wire, candidate.wire)
    } else {
      assert_true(result is UnresolvedName)
    }
    assert_eq(
      host.journal.submitted_intent_custody().unwrap().0,
      if reply_lost {
        1
      } else {
        0
      },
    )
    host.close().unwrap()
  }
}

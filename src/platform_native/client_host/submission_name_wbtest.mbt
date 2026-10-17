///|
fn named_test_setup(
  name : String,
  max_records? : Int = 8,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  NativeClientEpochAuthority,
  NativeClientSubmissionReference,
) {
  let setup = submitted_test_setup(name, max_records~)
  initialize_native_client_submitted_names(setup.0).unwrap()
  setup
}

///|
test "Native named original resolves before candidate and survives expired same-store reopen" {
  let label = "named-original-reopen"
  let (database, journal, authority, reference) = named_test_setup(label)
  let scope = "sha256:" + "a".repeat(64)
  let intent = submitted_test_intent("SELECT 1 AS n")
  guard journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      Some(reference),
      scope,
      true,
      1001.0,
    )
    is Ok(NamedSubmission(true, original)) else {
    fail("fresh name not committed")
  }
  assert_eq(original.reference.wire, reference.wire)
  // A candidate never selects the existing name's epoch or nonce.
  let unrelated = prepare_native_client_submission_reference(
    reference.epoch,
    "other",
  ).unwrap()
  guard journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      Some(unrelated),
      scope,
      true,
      1002.0,
    )
    is Ok(NamedSubmission(false, retained)) else {
    fail("original name not retained")
  }
  assert_eq(retained.reference.wire, reference.wire)
  assert_eq(journal.submitted_intent_custody().unwrap().0, 1)
  database.close_checked().unwrap()
  let database = epoch_test_database(label)
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let authority = open_native_client_epoch_authority(
    database,
    epoch_test_crypto(),
    100.0,
  ).unwrap()
  guard journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      None,
      scope,
      true,
      5000.0,
    )
    is Ok(NamedSubmission(false, original)) else {
    fail("expired original lookup unavailable")
  }
  assert_eq(original.reference.wire, reference.wire)
  assert_eq(journal.submitted_name_custody(authority).unwrap().0, 1)
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  database.close_checked().unwrap()
}

///|
test "Native named intent and authority scope conflict keep the same occupied index" {
  let (database, journal, authority, reference) = named_test_setup(
    "named-conflicts",
  )
  let scope = "sha256:" + "a".repeat(64)
  let intent = submitted_test_intent("SELECT 1 AS n")
  journal
  .resolve_or_bind_submitted_name(
    authority,
    "workspace",
    "actor",
    "name",
    intent,
    Some(reference),
    scope,
    true,
    1001.0,
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      submitted_test_intent("SELECT 2 AS n"),
      None,
      scope,
      true,
      1002.0,
    )
    is Err(ChangedIntent),
  )
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      None,
      "sha256:" + "b".repeat(64),
      true,
      1002.0,
    )
    is Err(ChangedIntent),
  )
  assert_eq(journal.submitted_name_custody(authority).unwrap().0, 1)
  database.close_checked().unwrap()
}

///|
test "Native missing name custody is unavailable without legacy reconstruction" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "named-old-missing",
  )
  let scope = "sha256:" + "a".repeat(64)
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      submitted_test_intent("SELECT 1 AS n"),
      Some(reference),
      scope,
      true,
      1001.0,
    )
    is Err(NamedSubmission(OriginalUnavailable)),
  )
  assert_true(
    database.read("client_submission_name_custody", "issued")
    is Err(@sqlite.NotFound),
  )
  assert_eq(journal.submitted_intent_custody().unwrap().0, 0)
  database.close_checked().unwrap()
}

///|
test "Native used reference and expired admission never acquire another name" {
  let (database, journal, authority, reference) = named_test_setup(
    "named-reference-used",
  )
  let scope = "sha256:" + "a".repeat(64)
  let intent = submitted_test_intent("SELECT 1 AS n")
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      Some(reference),
      scope,
      true,
      1002.0,
    )
    is Err(SubmissionReferenceUsed),
  )
  let fresh = prepare_native_client_submission_reference(
    reference.epoch,
    "unused",
  ).unwrap()
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "expired",
      intent,
      Some(fresh),
      scope,
      true,
      5000.0,
    )
    is Err(SubmissionEpochRejected(@scope.Expired)),
  )
  assert_eq(journal.submitted_name_custody(authority).unwrap().0, 0)
  database.close_checked().unwrap()
}

///|
test "Native named capacity is original finite issuance without eviction" {
  let (database, journal, authority, reference) = named_test_setup(
    "named-capacity",
    max_records=1,
  )
  let scope = "sha256:" + "a".repeat(64)
  let intent = submitted_test_intent("SELECT 1 AS n")
  journal
  .resolve_or_bind_submitted_name(
    authority,
    "workspace",
    "actor",
    "name",
    intent,
    Some(reference),
    scope,
    true,
    1001.0,
  )
  .unwrap()
  |> ignore
  let next = prepare_native_client_submission_reference(reference.epoch, "next").unwrap()
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "another",
      intent,
      Some(next),
      scope,
      true,
      1002.0,
    )
    is Err(CapacityExceeded),
  )
  guard journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      None,
      scope,
      true,
      1002.0,
    )
    is Ok(NamedSubmission(false, _)) else {
    fail("occupied name evicted")
  }
  database.close_checked().unwrap()
}

///|
test "Native name deletion and authenticator substitution refuse original custody" {
  for tamper in [false, true] {
    let (database, journal, authority, reference) = named_test_setup(
      "named-tamper-" + tamper.to_string(),
    )
    let scope = "sha256:" + "a".repeat(64)
    let intent = submitted_test_intent("SELECT 1 AS n")
    journal
    .resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      Some(reference),
      scope,
      true,
      1001.0,
    )
    .unwrap()
    |> ignore
    let original = database.scan_after("client_submission_names", "").unwrap()
    if tamper {
      let row = @host.decode_client_submitted_name_row(original.body).unwrap()
      database
      .compare_exchange(
        "client_submission_names",
        original.key,
        original.revision,
        @host.client_submitted_name_row_body({
          binding: row.binding,
          authenticator: Bytes::make(32, 0),
        }).unwrap(),
      )
      .unwrap()
      |> ignore
    } else {
      let ns = b"client_submission_names"
      let key = @utf8.encode(original.key)
      assert_true(
        submitted_test_remove_record(
          database,
          ns,
          ns.length(),
          key,
          key.length(),
        ),
      )
    }
    assert_true(
      journal.resolve_or_bind_submitted_name(
        authority,
        "workspace",
        "actor",
        "name",
        intent,
        None,
        scope,
        true,
        1002.0,
      )
      is Err(CustodyLost),
    )
    database.close_checked().unwrap()
  }
}

///|
test "Native named lost commit reply retains unknown and same-name lookup after reopen" {
  for reply_lost in [false, true] {
    let label = "named-commit-" + reply_lost.to_string()
    let (database, journal, authority, reference) = named_test_setup(label)
    let scope = "sha256:" + "a".repeat(64)
    let intent = submitted_test_intent("SELECT 1 AS n")
    submitted_test_fail_commit_after(database, 1, reply_lost)
    assert_true(
      journal.resolve_or_bind_submitted_name(
        authority,
        "workspace",
        "actor",
        "name",
        intent,
        Some(reference),
        scope,
        true,
        1001.0,
      )
      is Err(TransactionUnknown),
    )
    assert_true(database.transaction_fenced())
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let database = epoch_test_database(label)
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let authority = open_native_client_epoch_authority(
      database,
      epoch_test_crypto(),
      100.0,
    ).unwrap()
    let result = journal
      .resolve_or_bind_submitted_name(
        authority,
        "workspace",
        "actor",
        "name",
        intent,
        None,
        scope,
        true,
        1002.0,
      )
      .unwrap()
    if reply_lost {
      assert_true(result is NamedSubmission(false, _))
      assert_eq(journal.submitted_intent_custody().unwrap().0, 1)
    } else {
      assert_true(result is UnresolvedName)
      assert_eq(journal.submitted_intent_custody().unwrap().0, 0)
    }
    assert_eq(
      journal.submitted_name_custody(authority).unwrap().0,
      if reply_lost {
        1
      } else {
        0
      },
    )
    database.close_checked().unwrap()
  }
}

///|
test "Native named long original coordinates fit the fixed physical index without narrowing" {
  let (database, journal, authority, reference) = named_test_setup(
    "named-long-index",
  )
  let scope = "sha256:" + "a".repeat(64)
  let intent = submitted_test_intent("SELECT 1 AS n")
  let namespace_id = "界".repeat(256)
  let actor = "界".repeat(256)
  let name = "é".repeat(128)
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      namespace_id,
      actor,
      name,
      intent,
      Some(reference),
      scope,
      true,
      1001.0,
    )
    is Ok(NamedSubmission(true, _)),
  )
  let row = database.scan_after("client_submission_names", "").unwrap()
  assert_eq(@utf8.encode(row.key).length(), 64)
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      namespace_id,
      actor,
      name,
      intent,
      None,
      scope,
      true,
      1002.0,
    )
    is Ok(NamedSubmission(false, _)),
  )
  database.close_checked().unwrap()
}

///|
test "Native named current deny and foreign physical authority leave original rows unchanged" {
  let (database, journal, authority, reference) = named_test_setup(
    "named-current",
  )
  let scope = "sha256:" + "a".repeat(64)
  let intent = submitted_test_intent("SELECT 1 AS n")
  let epoch_before = database
    .read("client_submission_epoch", "authority")
    .unwrap()
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      Some(reference),
      scope,
      false,
      5000.0,
    )
    is Err(AuthorizationDenied),
  )
  let (other, _, foreign, _) = named_test_setup("named-foreign")
  assert_true(
    journal.resolve_or_bind_submitted_name(
      foreign,
      "workspace",
      "actor",
      "name",
      intent,
      Some(reference),
      scope,
      true,
      5000.0,
    )
    is Err(InvalidSubmission),
  )
  assert_eq(
    database.read("client_submission_epoch", "authority").unwrap().body,
    epoch_before.body,
  )
  assert_eq(journal.submitted_intent_custody().unwrap().0, 0)
  assert_eq(journal.submitted_name_custody(authority).unwrap().0, 0)
  other.close_checked().unwrap()
  database.close_checked().unwrap()
}

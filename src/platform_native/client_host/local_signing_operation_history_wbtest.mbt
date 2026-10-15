///|
// Real current Host/Account/private Root/SQLite and public PEM custody. The
// retained Signing grant and subject are metadata fixtures, not a signature,
// paired capture or operational approval. No private-key body is read.
test "Signing operation history selects its original attempt without caller use ID or issuer issue" {
  let (host, key, original) = signing_history_host_fixture(
    "operation-history-host",
    retained_use_id="original-signing-attempt",
  )
  let before = run_record_body(
    host.journal.retained(original.request).unwrap().unwrap(),
  ).unwrap()
  let read = key
    .lookup_original_signing_operation(
      "operator",
      "cli",
      original.request,
      original.operation_id,
    )
    .unwrap()
  let (grant, use_id, ordinal) = @credential.local_signing_credential_use_projection(
    read.original_use(),
  )
  assert_eq(grant, local_original_grant_cid(original.grant))
  assert_eq(use_id, "original-signing-attempt")
  assert_eq(ordinal, 1)
  assert_eq(read.observed_outcome(), @credential_resource.Unknown)
  assert_false(
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "credential/credential-authority-a",
      operation: "issue",
    })
    is Ok(@authorization.Allow(_)),
  )
  assert_eq(
    run_record_body(host.journal.retained(original.request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
}

///|
test "Signing operation history refuses legacy caller-selected use without changing generic history" {
  let (host, key, original) = signing_history_host_fixture(
    "operation-history-legacy",
  )
  assert_true(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      original.operation_id,
      "history-use",
    )
    is Ok(_),
  )
  assert_true(
    key.lookup_original_signing_operation(
      "operator",
      "cli",
      original.request,
      original.operation_id,
    )
    is Err(HistoryCredential(@credential_resource.Journal(@sqlite.NotFound))),
  )
  assert_true(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      original.operation_id,
      "history-use",
    )
    is Ok(_),
  )
  host.close().unwrap()
}

///|
test "Signing operation history keeps current Client denial foreign operation and expired-use eligibility separate" {
  let (host, key, original) = signing_history_host_fixture(
    "operation-history-expired",
    retained_use_id="original-signing-attempt",
    expires_at="2020-01-01T00:00:00.000Z",
  )
  assert_true(
    key.lookup_original_signing_operation(
      "operator",
      "cli",
      original.request,
      original.operation_id,
    )
    is Ok(_),
  )
  assert_true(
    key.lookup_original_signing_operation(
      "operator",
      "cli",
      original.request,
      "foreign-operation",
    )
    is Err(HistoryUnavailable),
  )
  assert_true(
    key.lookup_original_signing_operation(
      "foreign",
      "cli",
      original.request,
      original.operation_id,
    )
    is Err(HistoryOriginal(AuthorizationDenied)),
  )
  host.close().unwrap()
  let (denied, denied_key, denied_original) = signing_history_host_fixture(
    "operation-history-denied",
    client_read=false,
    retained_use_id="original-signing-attempt",
  )
  assert_true(
    denied_key.lookup_original_signing_operation(
      "operator",
      "cli",
      denied_original.request,
      denied_original.operation_id,
    )
    is Err(HistoryOriginal(AuthorizationDenied)),
  )
  denied.close().unwrap()
}

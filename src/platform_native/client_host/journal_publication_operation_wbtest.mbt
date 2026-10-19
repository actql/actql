///|
// Real Journal/SQLite and existing Account diagnostics. These callbacks trace
// the deep operations; they are not an installed business/Read supplier.
test "Publication original routing preserves one policy packet and named read authority" {
  let host = policy_host_fixture("publication-original-route")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "publication-original-request",
    "publication-original-run",
    scope~,
  )
  host.journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let calls : Array[String] = []
  let operations = journal_test_operation_access(host.database, calls)
  let authority = native_local_policy_authority_for(
    host,
    crypto,
    "operator",
    "cli",
    request,
    SubmitOriginals,
  ).unwrap()
  let first = host.journal
    .retain_publication_policy_originals(
      request,
      prepared,
      compiled,
      definition,
      authority,
      operations=Some(operations),
    )
    .unwrap()
  assert_true(first.publication_policy_originals is Some(_))
  assert_true(
    calls.contains(
      "compare_exchange:client_runs:" + @host.client_request_scope_cid(request),
    ),
  )
  assert_false(first.dispatch_reserved)
  assert_false(first.physical_start_claimed)
  calls.clear()
  let again = host.journal
    .retain_publication_policy_originals(
      request,
      prepared,
      compiled,
      definition,
      authority,
      operations=Some(operations),
    )
    .unwrap()
  assert_eq(again.revision, first.revision)
  assert_eq(
    again.publication_policy_originals,
    first.publication_policy_originals,
  )
  assert_false(
    calls.any(value => {
      value.has_prefix("insert:") || value.has_prefix("compare_exchange:")
    }),
  )
  let read = native_local_policy_authority_for(
    host,
    crypto,
    "operator",
    "cli",
    request,
    ReadResultPolicy("answer"),
  ).unwrap()
  let cid = @host.prepared_client_publication_data_policy_cid(prepared).unwrap()
  let packet = host.journal
    .lookup_publication_policy_original(
      request,
      cid,
      read,
      reads=Some(operations.reads),
    )
    .unwrap()
  assert_eq(@publication.captured_effect_dependency_body_cid(packet), cid)
  assert_false(
    calls.any(value => {
      value.has_prefix("insert:") || value.has_prefix("compare_exchange:")
    }),
  )
  assert_true(
    native_local_policy_authority_for(
      host,
      crypto,
      "foreign",
      "cli",
      request,
      ReadResultPolicy("answer"),
    )
    is Err(AuthorizationDenied),
  )
  host.close().unwrap()
  crypto.close_checked().unwrap()
}

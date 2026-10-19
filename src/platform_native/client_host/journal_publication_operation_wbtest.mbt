///|
// Real Journal/SQLite and existing Account diagnostics. These callbacks trace
// the deep operations; they are not an installed business/Read supplier.
test "Publication original routing preserves one policy packet and named read authority" {
  let host = policy_host_fixture("publication-original-route")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, unselected_compiled, definition) = journal_test_run(
    "publication-original-request",
    "publication-original-run",
    scope~,
  )
  // A source-free Program has no contributing Source policy. Retain this
  // rejection and explicitly admit the independent original fixture body.
  assert_eq(@host.prepared_client_publication_data_policy_cid(prepared), None)
  assert_true(
    run_policy_originals_wire(prepared, compiled=unselected_compiled)
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  let cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let body = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let compiled = @host.with_client_source_free_result_policy(
    unselected_compiled, cid, body, 65536, 8192, 64,
  ).unwrap()
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
  let first = selected_policy_require(
    host.journal.retain_publication_policy_originals(
      request,
      prepared,
      compiled,
      definition,
      authority,
      operations=Some(operations),
    ),
    "retain publication originals",
    issue => {
      match issue {
        Physical(value) => selected_policy_sqlite_issue(value)
        PublicationPolicy(@checked.MissingDependency) => "MissingDependency"
        PublicationPolicy(@checked.ForeignBody) => "ForeignBody"
        PublicationPolicy(@checked.BudgetExceeded) => "BudgetExceeded"
        _ => selected_policy_journal_issue(issue)
      }
    },
  )
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

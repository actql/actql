///|
// These Native definitions require a matching physical fixture to execute.
// Matching compiler success alone is not transaction/restart acceptance.
fn local_policy_test_packet(
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  run_id : String,
) -> (@publication.PublicationContract, @host.ClientLocalRunPolicyOriginal) {
  let profile = @host.client_local_run_policy_profile(
    @host.client_local_product_common_originals(
      "/Users/operator/.actql-local",
      "2026-10-12T00:00:00.000Z",
      @host.client_local_product_assets(),
    ).unwrap(),
  ).unwrap()
  let definition = @host.issue_client_compiled_run_definition(
    compiled, "local-test", run_id, "2026-10-13T00:00:00.001Z", "2026-10-14T00:00:00.001Z",
  ).unwrap()
  let original = @host.bind_client_local_run_policy_original(
    profile,
    @host.admit_client_submission_reference_record(reference.wire).unwrap(),
    request,
    definition,
    @host.issue_client_local_run_retention_policy(
      profile, "2026-10-13T00:00:00.001Z",
    ).unwrap(),
    "2026-10-13T00:00:00.001Z",
    "sha256:" + "a".repeat(64),
    "sha256:" + "f".repeat(64),
  ).unwrap()
  (definition, original)
}

///|
test "finite Policy and first Run admission commit and reopen as the same original" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "local-policy-accept-reopen",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, _, request, compiled, _) = submitted_run_test_input(
    reference, "policy-run",
  )
  let (definition, packet) = local_policy_test_packet(
    reference, request, compiled, "policy-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let accept = () => {
    journal.accept_original_submitted_run(
      authority,
      reference,
      @host.client_submitted_intent_cid(intent),
      request,
      definition,
      scope,
      true,
      local_run_policy_original=Some(packet),
      current_fence=Some(() => true),
    )
  }
  let accepted = accept().unwrap()
  let repeated = accept().unwrap()
  assert_eq(repeated.revision, accepted.revision)
  let run = journal.retained(request).unwrap().unwrap()
  assert_eq(
    run.local_run_policy_originals,
    Some(@utf8.decode(@host.client_local_run_policy_original_body(packet))),
  )
  assert_false(run.physical_start_claimed)
  assert_false(run.dispatch_reserved)
  database.close_checked().unwrap()
  let reopened = epoch_test_database("local-policy-accept-reopen")
  let restored = open_native_client_run_journal(reopened, 8)
    .unwrap()
    .retained(request)
    .unwrap()
    .unwrap()
  assert_eq(restored.local_run_policy_originals, run.local_run_policy_originals)
  assert_eq(restored.revision, run.revision)
  assert_eq(
    @publication.publication_contract_identity(restored.definition),
    @publication.publication_contract_identity(definition),
  )
  reopened.close_checked().unwrap()
}

///|
test "missing accepted Policy cannot be backfilled even before physical start" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "local-policy-missing-refused",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, _, request, compiled, _) = submitted_run_test_input(
    reference, "policy-run",
  )
  let (definition, packet) = local_policy_test_packet(
    reference, request, compiled, "policy-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_original_submitted_run(
    authority,
    reference,
    @host.client_submitted_intent_cid(intent),
    request,
    definition,
    scope,
    true,
  )
  .unwrap()
  |> ignore
  let before = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_true(
    journal.accept_original_submitted_run(
      authority,
      reference,
      @host.client_submitted_intent_cid(intent),
      request,
      definition,
      scope,
      true,
      local_run_policy_original=Some(packet),
      current_fence=Some(() => true),
    )
    is Err(CustodyLost),
  )
  let after = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  database.close_checked().unwrap()
}

///|
test "Policy acceptance refuses absent and revoked current fence without committing a Run" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "local-policy-fence-refused",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, _, request, compiled, _) = submitted_run_test_input(
    reference, "policy-run",
  )
  let (definition, packet) = local_policy_test_packet(
    reference, request, compiled, "policy-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  assert_true(
    journal.accept_original_submitted_run(
      authority,
      reference,
      @host.client_submitted_intent_cid(intent),
      request,
      definition,
      scope,
      true,
      local_run_policy_original=Some(packet),
    )
    is Err(AuthorizationDenied),
  )
  let mut checks = 0
  assert_true(
    journal.accept_original_submitted_run(
      authority,
      reference,
      @host.client_submitted_intent_cid(intent),
      request,
      definition,
      scope,
      true,
      local_run_policy_original=Some(packet),
      current_fence=Some(() => {
        checks += 1
        checks < 3
      }),
    )
    is Err(AuthorizationDenied),
  )
  assert_true(journal.retained(request) is Ok(None))
  assert_true(
    journal.retained_submission(reference).unwrap().unwrap().run_admission
    is None,
  )
  database.close_checked().unwrap()
}

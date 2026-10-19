///|
// Actual selected configuration and SQLite transaction diagnostics. The fixed
// test routing callbacks are not an installed Read/SQL pair or business supply.
fn local_policy_operation_input(
  host : NativeLocalHostConnection,
  name : String,
) -> (
  NativeLocalRunPolicyBinding,
  NativeClientSubmissionReference,
  NativeClientSubmittedPreparation,
  @host.ClientRequestIdentity,
  @host.ClientCompiledRun,
) raise {
  let policy = effect_finite_policy_binding(host)
  let epoch = host.epoch.issue_epoch(policy.scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(epoch, name).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    preparation_values_document() +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = submitted_prepare(intent).unwrap()
  guard preparation.preparation is Computation(prepared) else {
    fail("expected original computation")
  }
  let (request, _, compiled, _) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    name + "-run",
    scope=policy.scope,
  )
  host.journal
  .record_submitted_intent(
    host.epoch,
    reference,
    intent,
    policy.scope,
    true,
    1001.0,
  )
  .unwrap()
  |> ignore
  (policy, reference, preparation, request, compiled)
}

///|
test "finite Policy original routing retains its first issuance without resampling" {
  let host = effect_finite_policy_host("policy-original-route")
  let (policy, reference, preparation, request, compiled) = local_policy_operation_input(
    host, "original-policy",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(host.database, calls)
  let current_read = () => {
    policy.current_for(host.journal, Some(request), false)
  }
  let current_submission = () => {
    policy.current_for(host.journal, Some(request), true)
  }
  let observed_at = "2026-10-13T00:00:00.001Z"
  let candidate = policy
    .prepare_submission_policy_with_operations(
      reference,
      preparation,
      request,
      observed_at,
      1002.0,
      current_read,
      current_submission,
      operations=Some(operations),
    )
    .unwrap()
  guard candidate is Pending(retention, issued_at) else {
    fail("missing first original candidate")
  }
  let definition = @host.issue_client_compiled_run_definition(
    compiled, "local-test", "original-policy-run", observed_at, "2026-10-14T00:00:00.001Z",
  ).unwrap()
  let original = @host.bind_client_local_run_policy_original(
    policy.profile,
    @host.admit_client_submission_reference_record(reference.wire).unwrap(),
    request,
    definition,
    retention,
    issued_at,
    host.adoption_cid(),
    policy.read_selection_cid,
  ).unwrap()
  policy
  .accept_submitted_run_with_operations(
    reference,
    preparation,
    request,
    compiled,
    definition,
    original,
    1003.0,
    current_submission,
    operations=Some(operations),
  )
  .unwrap()
  |> ignore
  let saved = host.journal.retained(request).unwrap().unwrap()
  assert_eq(
    saved.local_run_policy_originals,
    Some(@utf8.decode(@host.client_local_run_policy_original_body(original))),
  )
  assert_true(calls.contains("compare_exchange:client_run_custody:issued"))
  assert_true(
    calls.contains(
      "insert:client_runs:" + @host.client_request_scope_cid(request),
    ),
  )
  calls.clear()
  let restored = policy
    .prepare_submission_policy_with_operations(
      reference,
      preparation,
      request,
      "not-a-new-time",
      1004.0,
      current_read,
      current_submission,
      operations=Some(operations),
    )
    .unwrap()
  guard restored is Accepted(packet) else {
    fail("saved original was not reused")
  }
  assert_eq(
    @host.client_local_run_policy_original_body(packet),
    @host.client_local_run_policy_original_body(original),
  )
  assert_false(
    calls.any(value => {
      value.has_prefix("insert:") || value.has_prefix("compare_exchange:")
    }),
  )
  let after = host.journal.retained(request).unwrap().unwrap()
  assert_eq(after.revision, saved.revision)
  assert_false(after.physical_start_claimed)
  host.close().unwrap()
}

///|
test "finite Policy original routing refuses changed current before Run admission" {
  let host = effect_finite_policy_host("policy-original-current")
  let (policy, reference, preparation, request, compiled) = local_policy_operation_input(
    host, "policy-current",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(host.database, calls)
  let current = Ref(true)
  let authorized = () => {
    current.val && policy.current_for(host.journal, Some(request), true)
  }
  let observed_at = "2026-10-13T00:00:00.001Z"
  let candidate = policy
    .prepare_submission_policy_with_operations(
      reference,
      preparation,
      request,
      observed_at,
      1002.0,
      authorized,
      authorized,
      operations=Some(operations),
    )
    .unwrap()
  guard candidate is Pending(retention, issued_at) else {
    fail("missing first candidate")
  }
  let definition = @host.issue_client_compiled_run_definition(
    compiled, "local-test", "policy-current-run", observed_at, "2026-10-14T00:00:00.001Z",
  ).unwrap()
  let original = @host.bind_client_local_run_policy_original(
    policy.profile,
    @host.admit_client_submission_reference_record(reference.wire).unwrap(),
    request,
    definition,
    retention,
    issued_at,
    host.adoption_cid(),
    policy.read_selection_cid,
  ).unwrap()
  current.val = false
  calls.clear()
  assert_true(
    policy.accept_submitted_run_with_operations(
      reference,
      preparation,
      request,
      compiled,
      definition,
      original,
      1003.0,
      authorized,
      operations=Some(operations),
    )
    is Err(AuthorizationDenied),
  )
  assert_false(
    calls.any(value => {
      value.has_prefix("insert:") || value.has_prefix("compare_exchange:")
    }),
  )
  assert_true(host.journal.retained(request).unwrap() is None)
  assert_true(
    host.journal.retained_submission(reference).unwrap().unwrap().run_admission
    is None,
  )
  host.close().unwrap()
}

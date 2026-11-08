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
// A checked two-stage Effect lies outside the former one-task execution
// profile. Preparing its finite lifetime must not accept/start that Program.
// This explicit legacy-library transaction case is not Source/Model execution,
// a backed captured Read, normal installation or physical cleanup acceptance.
test "finite Effect lifetime preparation does not require a one-task execution profile" {
  let host = effect_finite_policy_host("policy-composed-effect-preparation")
  defer host.close() |> ignore
  let policy = effect_finite_policy_binding(host)
  let epoch = host.epoch
    .issue_epoch(
      policy.scope,
      policy.current_for(host.journal, None, true),
      1000.0,
    )
    .unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "composed-effect-policy",
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"composed-effect-policy","stages":[{"id":"capture","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"string","nullable":false}},"rows":[{"value":"policy-only"}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}},{"id":"apply","inputs":{"input":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"select":["value"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"apply","result":"out"}}}}
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" + document + ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = native_client_effect_fixture_preparation(intent)
  guard preparation.preparation is EffectComputation(prepared) else {
    fail("original checked composed Effect required")
  }
  let graph = @strategy.checked_effect_computation_graph(
    @host.prepared_client_effect_computation_graph(prepared),
  )
  assert_eq(@strategy.graph_task_count(graph), 2)
  let request = @host.prepare_client_effect_request_identity(
    prepared,
    policy.scope,
    reference.request_id,
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  host.journal
  .record_submitted_intent(
    host.epoch,
    reference,
    intent,
    policy.scope,
    policy.current_for(host.journal, Some(request), true),
    1001.0,
  )
  .unwrap()
  |> ignore
  let before = host.journal.retained_submission(reference).unwrap().unwrap()
  assert_true(before.run_admission is None)
  assert_true(host.journal.retained(request).unwrap() is None)
  let observed_at = "2026-10-13T00:00:00.001Z"
  guard policy.prepare_submission_policy(
      reference, preparation, request, observed_at, 1002.0,
    )
    is Ok(Pending(retention, issued_at)) else {
    fail("checked Effect lifetime preparation must precede execution support")
  }
  assert_eq(issued_at, observed_at)
  assert_eq(
    @publication.result_retention_interval_state(retention, observed_at),
    Ok("available"),
  )
  let after = host.journal.retained_submission(reference).unwrap().unwrap()
  assert_eq(after.revision, before.revision)
  assert_true(after.run_admission is None)
  assert_true(host.journal.retained(request).unwrap() is None)
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
  let saved_intent = host.database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  let saved_count = host.database.read("client_run_custody", "issued").unwrap()
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
  // Authentication still advances the original monotonic epoch clock. It
  // cannot issue another Run, replace its intent or resample the saved Policy.
  assert_true(
    calls.contains("compare_exchange:client_submission_epoch:authority"),
  )
  for value in calls {
    if value.has_prefix("insert:") || value.has_prefix("compare_exchange:") {
      assert_eq(value, "compare_exchange:client_submission_epoch:authority")
    }
  }
  let after_intent = host.database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  let after_count = host.database.read("client_run_custody", "issued").unwrap()
  assert_eq(after_intent.body, saved_intent.body)
  assert_eq(after_intent.revision, saved_intent.revision)
  assert_eq(after_count.body, saved_count.body)
  assert_eq(after_count.revision, saved_count.revision)
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

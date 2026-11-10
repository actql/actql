///|
// Real selected finite profile, existing adoption/journal, and actual pinned
// libraries. These definitions perform no Compute, Store payload or Provider I/O.
// Native type checking alone does not establish these transaction cases.
fn effect_finite_policy_host(
  name : String,
  existing? : Bool = false,
  publish? : Bool = true,
) -> NativeLocalHostConnection raise {
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = base + "/" + name
  let names = [
    "profile.json", "read.json", "run.json", "retention.json", "store.json",
  ]
  if !existing {
    let parent = @filesystem.open_private_root(base).unwrap()
    parent.create_directory(name).unwrap() |> ignore
    parent.close().unwrap()
    let originals = @host.client_local_product_finite_originals(
      root,
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
      @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
      "2026-10-10T00:00:00.000Z",
      @host.client_local_product_assets(),
    ).unwrap()
    let selected = @filesystem.open_private_root(root).unwrap()
    for name in ["account.json", ..names] {
      let original = originals
        .iter()
        .find_first(pair => pair.0 == name)
        .unwrap().1
      let bytes = if name == "account.json" && !publish {
        @utf8.encode(
          @utf8.decode(original).replace(
            old="\"cancel\",\"publish\",\"read\",\"submit\"",
            new="\"cancel\",\"read\",\"submit\"",
          ),
        )
      } else {
        original
      }
      let writer = selected.create_writer(name + ".stage", 65536L).unwrap()
      writer.append(bytes).unwrap()
      writer.seal(name).unwrap() |> ignore
    }
    selected.close().unwrap()
  }
  begin_native_local_host_adoption(
    root,
    "host",
    root,
    "account.json",
    "local-cli",
    epoch_test_crypto(),
    existing_only=existing,
    configuration_files=names,
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
fn effect_finite_policy_binding(
  host : NativeLocalHostConnection,
) -> NativeLocalRunPolicyBinding {
  host
  .bind_run_policy_profile(
    epoch_test_crypto(),
    "local-cli",
    "local",
    "profile.json",
    "read.json",
    "run.json",
    "retention.json",
    "store.json",
  )
  .unwrap()
}

///|
test "Native Effect finite Policy commits with original material and reopens without issuance" {
  let name = "effect-finite-policy-original"
  let host = effect_finite_policy_host(name)
  defer host.close() |> ignore
  let policy = effect_finite_policy_binding(host)
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host,
    "finite-original",
    principal="local-cli",
    connection="local",
  )
  let accepted = policy
    .accept_submitted_effect_values_run_policy(
      reference, preparation, request, allowed, definition, issued, "2026-10-10T00:00:00.000Z",
      1002.0,
    )
    .unwrap()
  let record = host.journal.retained(request).unwrap().unwrap()
  assert_true(record.effect_material_originals is Some(_))
  assert_true(record.publication_policy_originals is Some(_))
  assert_true(record.local_run_policy_originals is Some(_))
  assert_eq(accepted.run_admission.unwrap().revision, record.revision)
  assert_false(record.physical_start_claimed)
  assert_false(record.dispatch_reserved)
  guard record.run_observation_originals is Some(observation_wire) else {
    fail("first Effect admission omitted original Run observation evidence")
  }
  let observation = read_native_run_observation_originals(
    observation_wire, definition,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(observation.prepared()),
    @publication.run_evidence_value_json(
      @host.client_effect_allowed_run_prepared(allowed),
    ),
  )
  assert_eq(
    @publication.run_evidence_value_json(observation.authorization()),
    @publication.run_evidence_value_json(
      @host.client_effect_allowed_run_authorization(allowed),
    ),
  )
  let saved = policy
    .lookup_submitted_run_policy(reference, request, 1003.0)
    .unwrap()
  let wire = @host.client_local_run_policy_original_body(saved)
  assert_eq(
    @host.client_local_run_policy_original_issued_at(saved),
    "2026-10-10T00:00:00.000Z",
  )
  assert_eq(
    @host.client_local_run_policy_original_read_expires_at(saved),
    "2026-10-11T00:00:00.000Z",
  )
  assert_true(
    @publication.publication_contract_json(
      @host.client_local_run_policy_original_retention(saved),
    ).contains("\"delete_by\":\"2026-10-12T00:00:00.000Z\""),
  )
  // Lookup precedes any constructor, including an invalid candidate time.
  guard policy.prepare_submission_policy(
      reference, preparation, request, "not-a-time", 1003.0,
    )
    is Ok(Accepted(again)) else {
    fail("finite.saved.lookup")
  }
  assert_eq(@host.client_local_run_policy_original_body(again), wire)
  assert_eq(
    policy
    .accept_submitted_effect_values_run_policy(
      reference, preparation, request, allowed, definition, issued, "not-a-time",
      1003.0,
    )
    .unwrap().revision,
    accepted.revision,
  )
  let after = host.journal.retained(request).unwrap().unwrap()
  assert_eq(run_record_body(after).unwrap(), run_record_body(record).unwrap())
  host.close().unwrap()
  let reopened = effect_finite_policy_host(name, existing=true)
  defer reopened.close() |> ignore
  let restored = effect_finite_policy_binding(reopened)
    .lookup_submitted_run_policy(reference, request, 1004.0)
    .unwrap()
  assert_eq(@host.client_local_run_policy_original_body(restored), wire)
  assert_eq(
    reopened.journal.retained(request).unwrap().unwrap().revision,
    record.revision,
  )
}

///|
test "Native Effect next-day fresh request keeps the old finite original and separate endpoints" {
  let host = effect_finite_policy_host("effect-finite-policy-nextday")
  defer host.close() |> ignore
  let policy = effect_finite_policy_binding(host)
  let saved : Array[(@host.ClientRequestIdentity, Bytes)] = []
  for
    (nonce, issued_at, available, deletion, metadata) in [
      (
        "finite-day-one", "2026-10-10T00:00:00.000Z", "2026-10-11T00:00:00.000Z",
        "2026-10-12T00:00:00.000Z", "2026-10-17T00:00:00.000Z",
      ),
      (
        "finite-day-two", "2026-10-11T00:00:00.001Z", "2026-10-12T00:00:00.001Z",
        "2026-10-13T00:00:00.001Z", "2026-10-18T00:00:00.001Z",
      ),
    ] {
    let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
      host,
      nonce,
      principal="local-cli",
      connection="local",
      created_at=issued_at,
      valid_until=available,
    )
    policy
    .accept_submitted_effect_values_run_policy(
      reference, preparation, request, allowed, definition, issued, issued_at, 1002.0,
    )
    .unwrap()
    |> ignore
    let original = policy
      .lookup_submitted_run_policy(reference, request, 1003.0)
      .unwrap()
    let retention = @publication.publication_contract_json(
      @host.client_local_run_policy_original_retention(original),
    )
    assert_eq(
      @host.client_local_run_policy_original_issued_at(original),
      issued_at,
    )
    assert_eq(
      @host.client_local_run_policy_original_read_expires_at(original),
      available,
    )
    assert_true(retention.contains("\"delete_by\":\"" + deletion + "\""))
    assert_true(
      retention.contains("\"metadata_delete_by\":\"" + metadata + "\""),
    )
    for (request, wire) in saved {
      assert_eq(
        run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
        wire,
      )
    }
    saved.push(
      (
        request,
        run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
      ),
    )
  }
  assert_eq(saved.length(), 2)
}

///|
test "Native Effect finite Policy refuses missing accepted custody rather than backfill" {
  let host = effect_finite_policy_host("effect-finite-policy-missing")
  defer host.close() |> ignore
  let policy = effect_finite_policy_binding(host)
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host,
    "finite-missing",
    principal="local-cli",
    connection="local",
  )
  host
  .accept_submitted_effect_material_original(
    epoch_test_crypto(),
    "local-cli",
    "local",
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
    1002.0,
    source_free_run_file=Some("run.json"),
  )
  .unwrap()
  |> ignore
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_true(
    host.journal.retained(request).unwrap().unwrap().local_run_policy_originals
    is None,
  )
  assert_true(
    policy.accept_submitted_effect_values_run_policy(
      reference, preparation, request, allowed, definition, issued, "2026-10-10T00:00:00.000Z",
      1003.0,
    )
    is Err(Journal(CustodyLost)),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
}

///|
test "Native Effect finite Policy requires independent current publish without a Run side effect" {
  let host = effect_finite_policy_host(
    "effect-finite-policy-denied",
    publish=false,
  )
  defer host.close() |> ignore
  let policy = effect_finite_policy_binding(host)
  assert_false(
    host.authorize({
      principal: "local-cli",
      connection: "local",
      resource: "run",
      operation: "publish",
    })
    is Ok(@authorization.Allow(_)),
  )
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host,
    "finite-denied",
    principal="local-cli",
    connection="local",
  )
  let before = host.journal.retained_submission(reference).unwrap().unwrap()
  assert_true(
    policy.accept_submitted_effect_values_run_policy(
      reference, preparation, request, allowed, definition, issued, "2026-10-10T00:00:00.000Z",
      1002.0,
    )
    is Err(Journal(AuthorizationDenied)),
  )
  assert_true(host.journal.retained(request).unwrap() is None)
  assert_true(
    host.journal.retained_submission(reference).unwrap().unwrap().run_admission
    is None,
  )
  assert_eq(
    host.journal.retained_submission(reference).unwrap().unwrap().revision,
    before.revision,
  )
}

///|
test "saved Run policy joins the command context without a read transaction" {
  let host = effect_finite_policy_host("effect-policy-command-read")
  defer host.close() |> ignore
  let policy = effect_finite_policy_binding(host)
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host,
    "command-read",
    principal="local-cli",
    connection="local",
  )
  policy
  .accept_submitted_effect_values_run_policy(
    reference, preparation, request, allowed, definition, issued, "2026-10-10T00:00:00.000Z",
    1002.0,
  )
  .unwrap()
  |> ignore
  let calls : Array[String] = []
  let operations = journal_test_operation_access(host.database, calls)
  host.epoch.begin_operation(false)
  host.journal.operation_active = true
  let first = policy
    .lookup_submitted_run_policy_with_operations(
      reference,
      request,
      1003.0,
      () => true,
      operations=Some(operations),
    )
    .unwrap()
  // Only the acknowledged epoch clock can write. The restored immutable
  // original must not add another transaction to the selected command.
  assert_eq(calls.filter(value => value == "begin").length(), 1)
  assert_eq(calls.filter(value => value == "commit").length(), 1)
  calls.clear()
  let again = policy
    .lookup_submitted_run_policy_with_operations(
      reference,
      request,
      1003.0,
      () => true,
      operations=Some(operations),
    )
    .unwrap()
  assert_eq(
    @host.client_local_run_policy_original_body(first),
    @host.client_local_run_policy_original_body(again),
  )
  assert_false(calls.contains("begin"))
  assert_false(calls.contains("commit"))
  // An outstanding flight cannot be joined or silently acknowledged.
  host.journal.transaction_active = true
  assert_true(
    policy.lookup_submitted_run_policy_with_operations(
      reference,
      request,
      1003.0,
      () => true,
      operations=Some(operations),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  host.journal.transaction_active = false
  assert_true(host.journal.operation_record is None)
  assert_true(host.journal.operation_submission is None)
  calls.clear()
  assert_true(
    policy.lookup_submitted_run_policy_with_operations(
      reference,
      request,
      1003.0,
      () => false,
      operations=Some(operations),
    )
    is Err(AuthorizationDenied),
  )
  assert_false(calls.contains("begin"))
  host.journal.operation_active = false
  host.journal.invalidate_operation_record()
  host.epoch.end_operation()
  calls.clear()
  policy
  .lookup_submitted_run_policy_with_operations(
    reference,
    request,
    1003.0,
    () => true,
    operations=Some(operations),
  )
  .unwrap()
  |> ignore
  // Ending the operation also retires the epoch clock observation. Its
  // standalone re-observation, Submission and Policy keep three transactions.
  assert_eq(calls.filter(value => value == "begin").length(), 3)
  assert_eq(calls.filter(value => value == "commit").length(), 3)
}

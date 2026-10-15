///|
fn worker_key_test_request(
  caller? : String = "worker-original-run",
) -> ClientRequestIdentity {
  let original = journal_encoding_original().request
  derive_client_request_identity(
    {
      program_definition_cid: client_request_program_cid(original),
      parameter_values_cid: client_request_parameters_cid(original),
    },
    "sha256:2403f9f91c600a51db56159017ac9512ac7bf590127aaa032eb993a285561568",
    caller,
    client_request_input_cid(original),
  ).unwrap()
}

///|
fn worker_key_test_retained(
  request? : ClientRequestIdentity = worker_key_test_request(),
  revision? : Int64 = 3L,
) -> ClientRetainedRunJournalRow {
  let record = { ..journal_encoding_original(), request, }
  read_client_retained_run_journal(
    request,
    (_, key) => {
      Ok(
        Some({
          key,
          revision,
          body: client_run_journal_row_body(record).unwrap(),
        }),
      )
    },
    run_append_validate,
    "custody",
  )
  .unwrap()
  .unwrap()
}

///|
test "worker journal key uses original adopted Store and retained Run lookup identity" {
  let store = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    adopted_current_test_ok(adopted_current_test_observation(store))
  }).unwrap()
  let request = worker_key_test_request()
  let retained = worker_key_test_retained()
  let original = bind_client_local_worker_run_journal_key(
    material, store, request, retained, "operator", "local",
  ).unwrap()
  let (table, key) = client_local_worker_run_journal_coordinates(
    original, store, retained,
  ).unwrap()
  assert_eq(table, "client_worker_originals")
  assert_eq(
    key,
    "sha256:7bc883aee393aff6c01d3929a296a5b9da3e16c69451d2de88dd78d2b054e456/" +
    client_request_scope_cid(request),
  )
  // Control revision is not a new worker operation or a new journal epoch.
  assert_eq(
    client_local_worker_run_journal_coordinates(
      original,
      store,
      worker_key_test_retained(revision=41L),
    ).unwrap(),
    (table, key),
  )
}

///|
test "worker journal key refuses foreign Store before any current callback" {
  let store = Ref(0)
  let calls = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    calls.val += 1
    adopted_current_test_ok(adopted_current_test_observation(store))
  }).unwrap()
  let request = worker_key_test_request()
  let retained = worker_key_test_retained()
  let original = bind_client_local_worker_run_journal_key(
    material, store, request, retained, "operator", "local",
  ).unwrap()
  let before = calls.val
  assert_true(
    client_local_worker_run_journal_coordinates(original, Ref(0), retained)
    is Err(Current(ForeignStore)),
  )
  assert_eq(calls.val, before)
}

///|
test "worker journal key refuses other Run intent and caller without changing original" {
  let store = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    adopted_current_test_ok(adopted_current_test_observation(store))
  }).unwrap()
  let request = worker_key_test_request()
  let retained = worker_key_test_retained()
  let original = bind_client_local_worker_run_journal_key(
    material, store, request, retained, "operator", "local",
  ).unwrap()
  let before = client_local_worker_run_journal_coordinates(
    original, store, retained,
  ).unwrap()
  assert_true(
    client_local_worker_run_journal_coordinates(
      original,
      store,
      worker_key_test_retained(
        request=worker_key_test_request(caller="other-run"),
      ),
    )
    is Err(ForeignRun),
  )
  assert_true(
    bind_client_local_worker_run_journal_key(
      material, store, request, retained, "another-principal", "local",
    )
    is Err(ForeignRun),
  )
  let changed = {
    ..request,
    caller_input_intent_cid: "sha256:" + "a".repeat(64),
  }
  assert_true(
    bind_client_local_worker_run_journal_key(
      material, store, changed, retained, "operator", "local",
    )
    is Err(ForeignRun),
  )
  assert_eq(
    client_local_worker_run_journal_coordinates(original, store, retained).unwrap(),
    before,
  )
}

///|
test "worker journal key preserves unknown physical failure and changed adoption refusal" {
  let store = Ref(0)
  let mode = Ref(0)
  let material = bind_client_local_adopted_host_material(store, () => {
    match mode.val {
      1 => adopted_current_test_ok(CommitUnknown)
      2 => Err("physical-query-failure")
      3 =>
        adopted_current_test_ok(
          adopted_current_test_observation(
            store,
            body=b"{\"configuration_custody_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"device\":\"7\",\"inode\":\"9\",\"intent_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"version\":\"actql-native-local-journal-custody/0.1\"}",
          ),
        )
      _ => adopted_current_test_ok(adopted_current_test_observation(store))
    }
  }).unwrap()
  let retained = worker_key_test_retained()
  let original = bind_client_local_worker_run_journal_key(
    material,
    store,
    worker_key_test_request(),
    retained,
    "operator",
    "local",
  ).unwrap()
  mode.val = 1
  assert_true(
    client_local_worker_run_journal_coordinates(original, store, retained)
    is Err(Current(CommitUnknown)),
  )
  mode.val = 2
  assert_true(
    client_local_worker_run_journal_coordinates(original, store, retained)
    is Err(Current(Physical("physical-query-failure"))),
  )
  mode.val = 3
  assert_true(
    client_local_worker_run_journal_coordinates(original, store, retained)
    is Err(Current(ChangedCurrent)),
  )
}

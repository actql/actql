///|
// This is a real legacy SystemSQLite/explicit Crypto component fixture. Its
// authored current/lifetime counters do not supply an installed Read pair.
fn read_snapshot_selected_original(
  name : String,
  accepted_policy? : Bool = false,
) -> (
  NativeLocalHostConnection,
  NativeLocalReadPolicyBinding,
  @host.ClientRequestIdentity,
  @result_access.NativeResultReadFacts,
) raise {
  let host = selected_read_roles_fixture(name, accepted_policy~)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("local-cli", "local", crypto).unwrap()
  let epoch = host.epoch.issue_epoch(scope, true, 1000.0).unwrap()
  let policy = host
    .bind_run_policy_profile(
      crypto,
      "local-cli",
      "local",
      name + ".profile",
      name + ".read-a",
      name + ".run-a",
      name + ".retention",
      name + ".store",
    )
    .unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "selected-read",
  ).unwrap()
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
    fail("selected preparation missing")
  }
  let (request, _, compiled, _) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    "selected-read-run",
    scope~,
  )
  let definition = @host.issue_client_compiled_run_definition(
    compiled, "local-test", "selected-read-run", "2026-10-13T00:00:00.001Z", "2026-10-14T00:00:00.001Z",
  ).unwrap()
  host.journal
  .record_submitted_intent(host.epoch, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let retention = @host.issue_client_local_run_retention_policy(
    policy.profile,
    "2026-10-13T00:00:00.001Z",
  ).unwrap()
  policy
  .accept_issued_submitted_run_policy(
    reference, preparation, request, compiled, definition, retention, "2026-10-13T00:00:00.001Z",
    1002.0,
  )
  .unwrap()
  |> ignore
  let binding = host
    .bind_result_read_policy_for_run(policy, reference, request, 1003.0)
    .unwrap()
  let facts : @result_access.NativeResultReadFacts = {
    request: {
      namespace_id: "original-namespace",
      authority_scope_cid: scope,
      run_definition_cid: @publication.publication_contract_identity(definition),
      principal_id: "local-cli",
      purpose: "cli-read",
      result_name: "answer",
      format: "jsonl",
      attempt_id: "original-read",
    },
    public_index_entry_cid: "",
    result_manifest_cid: "",
    result_artifact_cid: "",
    result_definition_cid: "",
    material_generation_cid: "",
    observed_at: "2026-10-13T01:00:00.001Z",
  }
  (host, binding, request, facts)
}

///|
test "selected read snapshot shares original admission and rejects changed target or retired current" {
  let (host, binding, request, facts) = read_snapshot_selected_original(
    "read-snapshot-original",
  )
  let calls : Array[String] = []
  let reads = journal_test_read_access(host.database, calls)
  let full = Ref(0)
  let live = Ref(true)
  let material = @host.bind_client_local_adopted_host_material(host.database, () => {
    host.current_adoption_material_with_reads(
      () => {
        full.val += 1
        host.check_binding()
      },
      reads=Some(reads),
      snapshot_current=Some(() => if live.val { Ok(()) } else { Err(Closed) }),
    )
  }).unwrap()
  full.val = 0
  let first = read_binding_in_journal_snapshot(host.journal, reads, () => {
    match binding.require_request_in_snapshot(request, facts, material, reads) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    guard host.journal.admitted_record is Some((_, _, _, _, admitted)) else {
      return Err(Journal(CustodyLost))
    }
    match host.journal.retained(request, reads=Some(reads)) {
      Ok(Some(same)) => Ok(physical_equal(admitted, same))
      _ => Err(Journal(CustodyLost))
    }
  }).unwrap()
  assert_true(first)
  assert_eq(full.val, 1)
  assert_true(host.journal.admitted_record is None)
  assert_true(host.journal.admitted_adoption is None)
  let key = @host.client_request_scope_cid(request)
  let before = host.database.read("client_runs", key).unwrap()
  let changed = read_binding_in_journal_snapshot(host.journal, reads, () => {
    match binding.require_request_in_snapshot(request, facts, material, reads) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    // The existing Run-definition index requires valid JSON on writes.
    // Keep the original row corrupt so its current check performs the refusal.
    match
      host.database.compare_exchange("client_runs", key, before.revision, b"{}") {
      Err(issue) => return Err(Journal(Physical(issue)))
      Ok(_) => ()
    }
    binding.require_current_in_snapshot(material, reads)
  })
  assert_true(changed is Err(Journal(CustodyLost)))
  assert_eq(full.val, 2)
  let after = host.database.read("client_runs", key).unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  live.val = false
  assert_true(
    read_binding_in_journal_snapshot(host.journal, reads, () => {
      binding.require_request_in_snapshot(request, facts, material, reads)
    })
    is Err(Adoption(Closed)),
  )
  assert_eq(full.val, 2)
  assert_true(host.journal.admitted_adoption is None)
  host.close().unwrap()
}

///|
test "read snapshot preserves commit and rollback uncertainty plus original body issue" {
  for lost_commit in [true, false] {
    let database = epoch_test_database(
      "read-snapshot-unknown-" + lost_commit.to_string(),
    )
    initialize_native_client_run_journal(database).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let calls : Array[String] = []
    let original = journal_test_read_access(database, calls)
    // The rollback port executes the same original rollback, then reports a
    // controlled lost ACK. It never retries a transaction or resets its fence.
    let reads : NativeClientJournalReadAccess = {
      ..original,
      transaction: operation => {
        let result = (original.transaction)(operation)
        if !lost_commit && operation is JournalRollback && result is Ok(_) {
          Err(@sqlite.Physical("controlled rollback reply lost"))
        } else {
          result
        }
      },
    }
    if lost_commit {
      client_test_fail_commit_reply(database, 1)
    }
    let result = read_binding_in_journal_snapshot(journal, reads, () => {
      if lost_commit {
        Ok(1)
      } else {
        Err(PolicyNotSelected)
      }
    })
    if lost_commit {
      assert_true(result is Err(OriginalRead(None, TransactionUnknown)))
    } else {
      assert_true(
        result is Err(OriginalRead(Some(PolicyNotSelected), TransactionUnknown)),
      )
    }
    assert_true(journal.fenced)
    assert_true(database.transaction_fenced())
    assert_true(journal.admitted_record is None)
    assert_true(journal.admitted_adoption is None)
    calls.clear()
    assert_true(
      read_binding_in_journal_snapshot(journal, reads, () => Ok(2))
      is Err(Journal(Fenced)),
    )
    assert_eq(calls, [])
    database.close_checked().unwrap()
  }
}

///|
// Actual selected-file/accepted-Run/Journal/Crypto component. The metadata below
// deliberately exercises the private post-Store-resolution seam; it is not a
// physical Store publication, payload read, grant or ordinary CLI acceptance.
test "accepted Run root correspondence cannot select another body Result or Request" {
  let (host, binding, request, initial) = read_snapshot_selected_original(
    "accepted-policy-root",
    accepted_policy=true,
  )
  defer host.close() |> ignore
  assert_true(binding.selection.policy is AcceptedRunPolicy)
  let facts = {
    ..initial,
    public_index_entry_cid: "sha256:" + "a".repeat(64),
    result_manifest_cid: "sha256:" + "b".repeat(64),
    result_artifact_cid: "sha256:" + "c".repeat(64),
    result_definition_cid: "sha256:" + "d".repeat(64),
    material_generation_cid: "sha256:" + "e".repeat(64),
  }
  let cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let body = @publication.admit_captured_effect_dependency_body(
    "data_policy",
    Some(cid),
    "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(
    binding.read_admission_originals(request, facts, cid)
    is Err(PolicyNotSelected),
  )
  binding.retain_result_policy_original(request, facts, body).unwrap()
  let originals = binding.read_admission_originals(request, facts, cid).unwrap()
  assert_true(
    originals.ceiling.wire.contains("\"data_policy_cids\":[\"" + cid + "\"]"),
  )
  assert_eq(binding.selected_policy_cids(request, facts, cid).unwrap(), [cid])
  assert_true(
    binding.selected_policy_cids(request, facts, "sha256:" + "f".repeat(64))
    is Err(PolicyNotSelected),
  )
  for
    foreign in [
      { ..facts, public_index_entry_cid: "sha256:" + "f".repeat(64), },
      { ..facts, result_manifest_cid: "sha256:" + "f".repeat(64), },
      { ..facts, result_artifact_cid: "sha256:" + "f".repeat(64), },
      { ..facts, result_definition_cid: "sha256:" + "f".repeat(64), },
      { ..facts, material_generation_cid: "sha256:" + "f".repeat(64), },
      { ..facts, request: { ..facts.request, result_name: "different", }, },
      { ..facts, request: { ..facts.request, attempt_id: "different", }, },
    ] {
    assert_true(
      binding.selected_policy_cids(request, foreign, cid)
      is Err(PolicyNotSelected),
    )
  }
  let (foreign, _, _, _) = journal_test_run(
    "foreign-policy-request",
    "foreign-policy-run",
    scope=binding.scope,
  )
  assert_true(
    binding.selected_policy_cids(foreign, facts, cid) is Err(PolicyNotSelected),
  )
  let missing = { ..binding, run_policy_original: None, }
  assert_true(
    missing.selected_policy_cids(request, facts, cid) is Err(PolicyNotSelected),
  )
  // Literal mode is unchanged: the same root must still occur in its exact
  // independent configured list, and all original list values enter the ceiling.
  let literal = {
    ..binding,
    selection: {
      ..binding.selection,
      policy: ExplicitPolicyCids([cid, "sha256:" + "f".repeat(64)]),
    },
  }
  assert_eq(literal.selected_policy_cids(request, facts, cid).unwrap(), [
    cid,
    "sha256:" + "f".repeat(64),
  ])
  assert_true(
    literal.selected_policy_cids(request, facts, "sha256:" + "a".repeat(64))
    is Err(PolicyNotSelected),
  )
  // Losing the exact accepted packet cannot be repaired by a retained root.
  guard binding.run_policy_original is Some((reference, bound, _)) else {
    fail("missing original packet")
  }
  let changed = {
    ..binding,
    run_policy_original: Some((reference, bound, b"{}")),
  }
  assert_true(
    changed.read_admission_originals(request, facts, cid)
    is Err(Journal(CustodyLost)),
  )
}

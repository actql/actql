///|
test "Native read preimages preserve independent Unicode line ending and key order vectors" {
  let crypto = epoch_test_crypto()
  let body = local_read_preimage(crypto, [
    ("a", Text("e\u0301\r\n")),
    ("b", Texts(["é", "e\u0301"])),
    ("c", Quantity(1)),
  ]).unwrap()
  // Independent UTF-8 JSON/SHA-256 vector, not a product-derived expectation.
  assert_eq(
    body.wire,
    "{\"a\":\"e\u0301\\r\\n\",\"b\":[\"é\",\"e\u0301\"],\"c\":1}",
  )
  assert_eq(
    body.cid,
    "sha256:8e2e245d6b8fe04bd3f83fcc25d65df70d930c575168641f2b56e019fd2c61e8",
  )
  for text in ["é\r\n", "e\u0301\r", "e\u0301\n"] {
    assert_false(
      local_read_preimage(crypto, [
        ("a", Text(text)),
        ("b", Texts(["é", "e\u0301"])),
        ("c", Quantity(1)),
      ]).unwrap().cid ==
      body.cid,
    )
  }
  assert_true(
    local_read_preimage(crypto, [("b", Quantity(1)), ("a", Quantity(2))])
    is Err(Encoding),
  )
}

///|
fn read_evidence_fixture(
  name : String,
  legacy_evidence? : Bool = false,
) -> (
  NativeLocalHostConnection,
  NativeLocalReadPolicyBinding,
  @host.ClientRequestIdentity,
  @result_access.NativeResultReadFacts,
  Int64,
) raise {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(root).unwrap()
  let file = name + ".read.json"
  let writer = parent.create_writer(name + ".read.stage", 65536L).unwrap()
  // Independent whole-body digest of the source-free effective Policy wire.
  let policy_cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  writer
  .append(
    @utf8.encode(
      local_read_original_wire.replace_all(
        old="sha256:" + "a".repeat(64),
        new=policy_cid,
      ),
    ),
  )
  .unwrap()
  writer.seal(file).unwrap() |> ignore
  let host = policy_host_fixture(name, files=[file], legacy_evidence~)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, unselected_compiled, definition) = journal_test_run(
    "read-request",
    "read-run",
    scope~,
  )
  // Source-free preparation has no contributing Source policy. This fixture
  // must explicitly admit its original policy on the existing compiled Owner;
  // neither its CID nor the read selection synthesizes provenance or a grant.
  assert_eq(@host.prepared_client_publication_data_policy_cid(prepared), None)
  assert_true(
    @host.client_compiled_run_publication_policy_bodies(
      unselected_compiled, 65536, 8192, 64,
    )
    is Err(@checked.MissingDependency),
  )
  let policy_body = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let compiled = @host.with_client_source_free_result_policy(
    unselected_compiled, policy_cid, policy_body, 65536, 8192, 64,
  ).unwrap()
  assert_eq(
    @host.client_compiled_run_publication_policy_bodies(
      compiled, 65536, 8192, 64,
    ).unwrap(),
    [("data_policy", policy_cid, policy_body)],
  )
  host
  .run_journal()
  .unwrap()
  .bind_run(request, prepared, compiled, definition, true)
  .unwrap()
  |> ignore
  let record = host
    .retain_publication_policy_originals(
      crypto, "operator", "cli", request, prepared, compiled, definition,
    )
    .unwrap()
  let binding = host
    .bind_result_read_policy(crypto, file, "operator", "cli")
    .unwrap()
  let facts : @result_access.NativeResultReadFacts = {
    request: {
      namespace_id: "original-namespace",
      authority_scope_cid: scope,
      run_definition_cid: @publication.publication_contract_identity(definition),
      principal_id: "operator",
      purpose: "inspection",
      result_name: "answer",
      format: "jsonl",
      attempt_id: "original-read",
    },
    public_index_entry_cid: "sha256:" + "b".repeat(64),
    result_manifest_cid: "sha256:" + "c".repeat(64),
    result_artifact_cid: "sha256:" + "d".repeat(64),
    result_definition_cid: "sha256:" + "e".repeat(64),
    material_generation_cid: "sha256:" + "f".repeat(64),
    observed_at: "2026-10-11T00:00:00.000Z",
  }
  // These stand-alone custody cases exercise the private post-resolution step.
  // The constructed Store references are never passed to the public admit_read
  // boundary, grant issuer or payload. Actual Store/CLI acceptance is separate.
  (host, binding, request, facts, record.revision)
}

///|
test "Native read originals are durable idempotent per attempt and preserve Run control revision" {
  let name = "local-read-evidence-reopen"
  let (host, binding, original, facts, revision) = read_evidence_fixture(name)
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let first = binding.retain_read_admission(original, facts, policy).unwrap()
  let repeated = binding.retain_read_admission(original, facts, policy).unwrap()
  assert_eq(first.egress_admission_cid, repeated.egress_admission_cid)
  assert_eq(first.authorization_context_cid, repeated.authorization_context_cid)
  assert_eq(first.max_uses, 1)
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"1",
  )
  let second = binding
    .retain_read_admission(
      original,
      {
        ..facts,
        request: { ..facts.request, attempt_id: "explicit-new-read", },
      },
      policy,
    )
    .unwrap()
  assert_false(second.egress_admission_cid == first.egress_admission_cid)
  assert_false(
    second.authorization_context_cid == first.authorization_context_cid,
  )
  assert_eq(second.data_ceiling_cid, first.data_ceiling_cid)
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"2",
  )
  let usage = host.database
    .capacity_usage("client_local_read_evidence")
    .unwrap()
  assert_eq(usage.reserved_bytes, 65536L)
  assert_eq(usage.reserved_objects, 1L)
  guard host.run_journal().unwrap().lookup(original, true)
    is Ok(Retained(before)) else {
    fail("Run missing")
  }
  assert_eq(before.revision, revision)
  host.close().unwrap()
  let reopened = policy_host_fixture(name, existing=true, files=[
    name + ".read.json",
  ])
  let binding = reopened
    .bind_result_read_policy(
      epoch_test_crypto(),
      name + ".read.json",
      "operator",
      "cli",
    )
    .unwrap()
  let restored = binding.retain_read_admission(original, facts, policy).unwrap()
  assert_eq(restored.egress_admission_cid, first.egress_admission_cid)
  assert_eq(
    reopened.database.read("client_local_read_custody", "issued").unwrap().body,
    b"2",
  )
  guard reopened.run_journal().unwrap().lookup(original, true)
    is Ok(Retained(after)) else {
    fail("original Run lost")
  }
  assert_eq(after.revision, revision)
  reopened.close().unwrap()
}

///|
test "Native read originals refuse missing rewritten custody or lost reservation without repair" {
  for
    failure in [
      "missing-witness", "missing-body", "rewritten-body", "lost-reservation",
    ] {
    let (host, binding, original, facts, revision) = read_evidence_fixture(
      "local-read-" + failure,
    )
    let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
    let first = binding.retain_read_admission(original, facts, policy).unwrap()
    let table = if failure == "missing-witness" {
      "client_local_read_custody"
    } else {
      "client_local_read_evidence"
    }
    let key = if failure == "missing-witness" {
      "issued"
    } else {
      first.egress_admission_cid
    }
    if failure == "rewritten-body" {
      host.database.begin_immediate().unwrap()
      assert_true(
        host.database.compare_exchange(table, key, 0L, b"{}")
        is Err(@sqlite.Physical(_)),
      )
      let saved = host.database.read(table, key).unwrap()
      host.database
      .remove_exact(table, key, saved.revision, saved.body)
      .unwrap()
      host.database
      .insert(
        table,
        key,
        read_evidence_wrong_packet(
          @host.client_request_identity_record_wire(original).unwrap(),
        ),
      )
      .unwrap()
      |> ignore
      host.database.commit().unwrap()
    } else if failure == "lost-reservation" {
      assert_true(
        host.database
        .release_capacity(
          "client_local_read_evidence",
          @host.client_request_scope_cid(original),
          65536L,
          1L,
        )
        .unwrap(),
      )
    } else {
      let table = @utf8.encode(table)
      let key = @utf8.encode(key)
      assert_true(
        submitted_test_remove_record(
          host.database,
          table,
          table.length(),
          key,
          key.length(),
        ),
      )
    }
    assert_true(
      binding.retain_read_admission(original, facts, policy)
      is Err(Journal(CustodyLost)),
    )
    guard host.run_journal().unwrap().lookup(original, true)
      is Ok(Retained(after)) else {
      fail("control history lost")
    }
    assert_eq(after.revision, revision)
    if failure == "lost-reservation" {
      assert_eq(
        host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_objects,
        0L,
      )
    }
    host.close().unwrap()
  }
}

///|
test "Native read evidence refusal rolls back reservations and preserves original admission" {
  let (host, binding, original, facts, revision) = read_evidence_fixture(
    "local-read-refusal",
  )
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  assert_true(
    binding.retain_read_admission(original, facts, "sha256:" + "f".repeat(64))
    is Err(PolicyNotSelected),
  )
  assert_eq(
    host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_bytes,
    0L,
  )
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"0",
  )
  let first = binding.retain_read_admission(original, facts, policy).unwrap()
  assert_true(
    binding.retain_read_admission(
      original,
      { ..facts, observed_at: "2026-10-12T00:00:00.000Z", },
      policy,
    )
    is Err(PolicyExpired),
  )
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"1",
  )
  let empty_attempt = {
    ..facts,
    request: { ..facts.request, attempt_id: "", },
  }
  assert_true(
    binding.retain_read_admission(original, empty_attempt, policy)
    is Err(SelectionMismatch),
  )
  let repeated = binding.retain_read_admission(original, facts, policy).unwrap()
  assert_eq(first.egress_admission_cid, repeated.egress_admission_cid)
  guard host.run_journal().unwrap().lookup(original, true)
    is Ok(Retained(after)) else {
    fail("control Run lost")
  }
  assert_eq(after.revision, revision)
  host.close().unwrap()
}

///|
test "Native finite read evidence capacity refuses new attempts without changing Run or prior proof" {
  let (host, binding, original, facts, revision) = read_evidence_fixture(
    "local-read-capacity",
  )
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let first = binding.retain_read_admission(original, facts, policy).unwrap()
  let mut exhausted = false
  let mut accepted = 1
  // The explicit finite pool is at most 64 originals and 65,536 bytes/Run.
  // Do not evict prior evidence, enlarge it or retry an exhausted pool.
  for index in 1..<=64 {
    let next = {
      ..facts,
      request: { ..facts.request, attempt_id: "explicit-" + index.to_string(), },
    }
    match binding.retain_read_admission(original, next, policy) {
      Ok(_) => accepted += 1
      Err(Journal(CapacityExceeded)) => {
        exhausted = true
        break
      }
      Err(_) => fail("unexpected read evidence refusal")
    }
  }
  assert_true(exhausted)
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    @utf8.encode(accepted.to_string()),
  )
  let repeat = binding.retain_read_admission(original, facts, policy).unwrap()
  assert_eq(repeat.egress_admission_cid, first.egress_admission_cid)
  assert_eq(
    host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_bytes,
    65536L,
  )
  guard host.run_journal().unwrap().lookup(original, true)
    is Ok(Retained(after)) else {
    fail("control Run lost")
  }
  assert_eq(after.revision, revision)
  host.close().unwrap()
}

///|
// Real legacy Library/SQLite diagnostics for the routed transaction. These
// callbacks do not supply an operational Read/SQL pair or a payload grant.
test "Routed read evidence preserves reservation CAS rollback and complete custody" {
  let (host, binding, original, facts, revision) = read_evidence_fixture(
    "routed-read-evidence",
  )
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let calls : Array[String] = []
  let access = journal_test_operation_access(host.database, calls)
  let failed : NativeClientJournalOperationAccess = {
    ..access,
    compare_exchange: (table, key, row_revision, body) => {
      if table == "client_local_read_custody" {
        calls.push("refuse-issued-cas")
        Err(@sqlite.Collision)
      } else {
        (access.compare_exchange)(table, key, row_revision, body)
      }
    },
  }
  assert_true(
    binding.retain_read_admission_with_operations(
      original,
      facts,
      policy,
      operations=Some(failed),
    )
    is Err(Journal(Physical(@sqlite.Collision))),
  )
  assert_true(calls.contains("refuse-issued-cas"))
  assert_true(calls.contains("rollback"))
  assert_true(
    calls.any(value => value.has_prefix("insert:client_local_read_evidence:")),
  )
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"0",
  )
  assert_true(
    host.database.scan_after("client_local_read_evidence", "")
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_objects,
    0L,
  )
  calls.clear()
  let admitted = binding
    .retain_read_admission_with_operations(
      original,
      facts,
      policy,
      operations=Some(access),
    )
    .unwrap()
  let repeated = binding
    .retain_read_admission_with_operations(
      original,
      facts,
      policy,
      operations=Some(access),
    )
    .unwrap()
  assert_eq(admitted.egress_admission_cid, repeated.egress_admission_cid)
  assert_eq(calls.filter(value => value == "read-evidence-schema").length(), 2)
  assert_eq(calls.filter(value => value == "read-evidence-usage").length(), 2)
  assert_false(
    calls.any(value => value.has_prefix("scan:client_local_read_evidence:")),
  )
  assert_false(calls.contains("capacity:client_local_read_evidence"))
  assert_true(
    calls.contains(
      "read:client_runs:" + @host.client_request_scope_cid(original),
    ),
  )
  assert_eq(
    host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_objects,
    1L,
  )
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"1",
  )
  assert_eq(
    host.journal.retained(original).unwrap().unwrap().revision,
    revision,
  )
  assert_true(
    host.database.insert("client_local_read_evidence", "foreign", b"{}")
    is Err(@sqlite.Physical(_)),
  )
  let foreign = read_evidence_wrong_packet("foreign")
  host.database
  .insert("client_local_read_evidence", "foreign", foreign)
  .unwrap()
  |> ignore
  let delivered = binding
    .retained_read_admission_with_operations(
      original,
      facts,
      policy,
      operations=Some(access),
    )
    .unwrap()
  assert_eq(delivered.egress_admission_cid, admitted.egress_admission_cid)
  // Whole-history corruption is still diagnosed explicitly. An unrelated
  // row is not part of this target's read authority or retained reservation.
  assert_true(
    host.read_evidence_custody(binding.crypto, operations=Some(access))
    is Err(CustodyLost),
  )
  assert_eq(
    host.database.read("client_local_read_evidence", "foreign").unwrap().body,
    foreign,
  )
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"1",
  )
  host.close().unwrap()
}

///|
// Closed physical packet shape, deliberately invalid semantic originals. The
// SQLite index does not issue request, policy, authorization or CID authority.
fn read_evidence_wrong_packet(request : String) -> Bytes {
  local_adoption_record([
    ("authorization_context", "changed"),
    ("data_ceiling", "changed"),
    ("egress_admission", "changed"),
    ("request", request),
  ]).unwrap()
}

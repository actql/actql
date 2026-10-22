///|
test "Native delivery authorization never repairs a missing admission or creates another attempt" {
  let (host, binding, original, facts, revision) = read_evidence_fixture(
    "read-delivery-retained",
  )
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  assert_true(
    binding.retained_read_admission(original, facts, policy)
    is Err(Journal(CustodyLost)),
  )
  assert_eq(
    host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_bytes,
    0L,
  )
  let admitted = binding.retain_read_admission(original, facts, policy).unwrap()
  for _ in 0..<3 {
    let restored = binding
      .retained_read_admission(original, facts, policy)
      .unwrap()
    assert_eq(restored.egress_admission_cid, admitted.egress_admission_cid)
    assert_eq(
      restored.authorization_context_cid,
      admitted.authorization_context_cid,
    )
    assert_eq(restored.data_ceiling_cid, admitted.data_ceiling_cid)
  }
  assert_true(
    binding.retained_read_admission(
      original,
      {
        ..facts,
        request: { ..facts.request, attempt_id: "unadmitted-attempt", },
      },
      policy,
    )
    is Err(Journal(CustodyLost)),
  )
  assert_true(
    binding.retained_read_admission(
      original,
      { ..facts, result_artifact_cid: "sha256:" + "a".repeat(64), },
      policy,
    )
    is Err(Journal(CustodyLost)),
  )
  assert_true(
    binding.retained_read_admission(
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
  assert_eq(
    host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_bytes,
    65536L,
  )
  guard host.run_journal().unwrap().lookup(original, true)
    is Ok(Retained(record)) else {
    fail("original Run lost")
  }
  assert_eq(record.revision, revision)
  host.close().unwrap()
}

///|
test "Native delivery proof lookup after reopen preserves custody and refuses lost reservation" {
  let name = "read-delivery-reopen"
  let (host, binding, original, facts, revision) = read_evidence_fixture(name)
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let first = binding.retain_read_admission(original, facts, policy).unwrap()
  host.close().unwrap()
  let reopened = policy_host_fixture(name, existing=true, files=[
    name + ".read.json",
  ])
  let restored = reopened
    .bind_result_read_policy(
      epoch_test_crypto(),
      name + ".read.json",
      "operator",
      "cli",
    )
    .unwrap()
  assert_eq(
    restored.retained_read_admission(original, facts, policy).unwrap().egress_admission_cid,
    first.egress_admission_cid,
  )
  assert_true(
    reopened.database
    .release_capacity(
      "client_local_read_evidence",
      @host.client_request_scope_cid(original),
      65536L,
      1L,
    )
    .unwrap(),
  )
  assert_true(
    restored.retained_read_admission(original, facts, policy)
    is Err(Journal(CustodyLost)),
  )
  assert_eq(
    reopened.database.capacity_usage("client_local_read_evidence").unwrap().reserved_bytes,
    0L,
  )
  assert_eq(
    reopened.database.read("client_local_read_custody", "issued").unwrap().body,
    b"1",
  )
  guard reopened.run_journal().unwrap().lookup(original, true)
    is Ok(Retained(record)) else {
    fail("original Run lost")
  }
  assert_eq(record.revision, revision)
  reopened.close().unwrap()
}

///|
test "Native read request gate binds original Run current selection and finite stdout ceiling before admission" {
  let (host, binding, original, facts, revision) = read_evidence_fixture(
    "read-request-gate",
  )
  assert_true(
    binding.authorize_read_request(
      original,
      facts.request,
      facts.observed_at,
      max_output_bytes=Some(65536),
    )
    is Ok(_),
  )
  assert_true(
    binding.authorize_read_request(
      original,
      facts.request,
      facts.observed_at,
      max_output_bytes=Some(65537),
    )
    is Err(SelectionMismatch),
  )
  assert_true(
    binding.authorize_read_request(
      original,
      { ..facts.request, run_definition_cid: "sha256:" + "a".repeat(64), },
      facts.observed_at,
    )
    is Err(Journal(ForeignRun)),
  )
  assert_true(
    binding.authorize_read_request(
      original,
      { ..facts.request, purpose: "unselected-destination", },
      facts.observed_at,
    )
    is Err(SelectionMismatch),
  )
  assert_true(
    binding.authorize_read_request(
      original,
      { ..facts.request, principal_id: "different-principal", },
      facts.observed_at,
    )
    is Err(AuthorizationDenied),
  )
  assert_true(
    binding.authorize_read_request(
      original,
      facts.request,
      "2026-10-12T00:00:00.000Z",
    )
    is Err(PolicyExpired),
  )
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"0",
  )
  assert_eq(
    host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_bytes,
    0L,
  )
  guard host.run_journal().unwrap().lookup(original, true)
    is Ok(Retained(record)) else {
    fail("original Run lost")
  }
  assert_eq(record.revision, revision)
  host.close().unwrap()
}

///|
test "retained delivery selects only its original evidence and reserved holding" {
  let (host, binding, original, facts, revision) = read_evidence_fixture(
    "read-delivery-target-only",
  )
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let admitted = binding.retain_read_admission(original, facts, policy).unwrap()
  assert_true(
    host.database.insert(
      "client_local_read_evidence", "unrelated", b"unrelated malformed history",
    )
    is Err(@sqlite.Physical(_)),
  )
  host.database
  .insert(
    "client_local_read_evidence",
    "unrelated",
    read_evidence_wrong_packet("unrelated"),
  )
  .unwrap()
  |> ignore
  let calls : Array[String] = []
  let access = journal_test_operation_access(host.database, calls)
  let retained = binding
    .retained_read_admission_with_operations(
      original,
      facts,
      policy,
      operations=Some(access),
    )
    .unwrap()
  assert_eq(retained.egress_admission_cid, admitted.egress_admission_cid)
  assert_eq(calls.filter(value => value.has_prefix("read-capacity:")), [
    "read-capacity:client_local_read_evidence:" +
    @host.client_request_scope_cid(original),
  ])
  assert_eq(
    calls.filter(value => value.has_prefix("read:client_local_read_evidence:")),
    ["read:client_local_read_evidence:" + admitted.egress_admission_cid],
  )
  for table in ["host", "issued"] {
    assert_eq(
      calls
      .filter(value => value == "read:client_local_read_custody:" + table)
      .length(),
      1,
    )
  }
  assert_false(
    calls.any(value => {
      value.has_prefix("scan:client_local_read_") ||
      value == "capacity:client_local_read_evidence" ||
      value.has_prefix("reserve:") ||
      value.has_prefix("insert:") ||
      value.has_prefix("compare_exchange:")
    }),
  )
  assert_true(
    host.read_evidence_custody(binding.crypto, operations=Some(access))
    is Err(CustodyLost),
  )
  let packet = host.database
    .read("client_local_read_evidence", admitted.egress_admission_cid)
    .unwrap()
  host.database.begin_immediate().unwrap()
  assert_true(
    host.database.compare_exchange(
      "client_local_read_evidence",
      admitted.egress_admission_cid,
      packet.revision,
      b"changed target",
    )
    is Err(@sqlite.Physical(_)),
  )
  host.database
  .remove_exact(
    "client_local_read_evidence",
    admitted.egress_admission_cid,
    packet.revision,
    packet.body,
  )
  .unwrap()
  host.database
  .insert(
    "client_local_read_evidence",
    admitted.egress_admission_cid,
    read_evidence_wrong_packet(
      @host.client_request_identity_record_wire(original).unwrap(),
    ),
  )
  .unwrap()
  |> ignore
  host.database.commit().unwrap()
  assert_true(
    binding.retained_read_admission_with_operations(
      original,
      facts,
      policy,
      operations=Some(access),
    )
    is Err(Journal(CustodyLost)),
  )
  assert_eq(
    host.journal.retained(original).unwrap().unwrap().revision,
    revision,
  )
  host.close().unwrap()
}

///|
// Actual legacy SystemSQLite/explicit Crypto diagnostics. These do not supply
// an operational Read/SQL pair, selected component or ordinary CLI artifact.
test "read evidence schema is observed once in the original Journal snapshot" {
  let (host, _, original, _, _) = read_evidence_fixture(
    "evidence-index-snapshot",
  )
  assert_eq(host.database.client_read_evidence_schema().unwrap(), 1)
  let calls : Array[String] = []
  let access = journal_test_operation_access(host.database, calls)
  let wire = @host.client_request_identity_record_wire(original).unwrap()
  let usage = host.journal
    .transaction_with_reads(
      () => {
        for _ in 0..<2 {
          match
            host.journal.require_read_evidence_schema(reads=Some(access.reads)) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
        }
        read_client_journal_evidence_usage(
          host.database,
          wire,
          64L,
          65536L,
          Some(access),
        ).map_err(issue => Physical(issue))
      },
      reads=Some(access.reads),
    )
    .unwrap()
  assert_eq(usage, (0L, 0L))
  assert_eq(calls.filter(value => value == "read-evidence-schema").length(), 1)
  assert_eq(calls.filter(value => value == "read-evidence-usage").length(), 1)
  assert_false(
    calls.any(value => {
      value.has_prefix("scan:") || value == "install read evidence schema"
    }),
  )
  assert_eq(host.journal.observed_evidence_schema, None)
  let foreign = epoch_test_database("evidence-index-foreign")
  calls.clear()
  assert_true(
    read_client_journal_evidence_usage(foreign, wire, 64L, 65536L, Some(access))
    is Err(@sqlite.Collision),
  )
  assert_true(
    install_journal_read_evidence_schema(foreign, 0L, Some(access))
    is Err(@sqlite.Collision),
  )
  assert_eq(calls, [])
  foreign.close_checked().unwrap()
  host.close().unwrap()
}

///|
test "authorized bounded evidence migration preserves prior originals and permits indexed append" {
  let (host, binding, original, facts, _) = read_evidence_fixture(
    "evidence-index-legacy",
    legacy_evidence=true,
  )
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  assert_true(
    binding.retain_read_admission(original, facts, policy)
    is Err(Journal(CustodyLost)),
  )
  assert_eq(host.database.client_read_evidence_schema().unwrap(), 0)
  assert_eq(
    host.database.capacity_usage("client_local_read_evidence").unwrap().reserved_objects,
    0L,
  )
  // Assemble two new prior-format originals through the same checked codecs and
  // real transaction. The index is absent, as in the earlier implementation.
  let bodies = binding
    .read_admission_originals(original, facts, policy)
    .unwrap()
  let packet = local_read_evidence_packet(original, bodies).unwrap()
  let second_bodies = binding
    .read_admission_originals(
      original,
      { ..facts, request: { ..facts.request, attempt_id: "second-legacy", }, },
      policy,
    )
    .unwrap()
  let second_packet = local_read_evidence_packet(original, second_bodies).unwrap()
  host.database.begin_immediate().unwrap()
  assert_true(
    host.database
    .reserve_capacity_in_transaction(
      "client_local_read_evidence",
      @host.client_request_scope_cid(original),
      65536L,
      1L,
      host.journal.max_records.to_int64() * 65536L,
      host.journal.max_records.to_int64(),
    )
    .unwrap(),
  )
  host.database
  .insert("client_local_read_evidence", bodies.egress.cid, packet)
  .unwrap()
  |> ignore
  host.database
  .insert("client_local_read_evidence", second_bodies.egress.cid, second_packet)
  .unwrap()
  |> ignore
  host.database
  .compare_exchange("client_local_read_custody", "issued", 0L, b"1")
  .unwrap()
  |> ignore
  host.database
  .compare_exchange("client_local_read_custody", "issued", 1L, b"2")
  .unwrap()
  |> ignore
  host.database.commit().unwrap()
  let epoch = host.database
    .read("client_submission_epoch", "authority")
    .unwrap()
  assert_true(
    host.migrate_journal_append_metadata("operator", "cli", 1L)
    is Err(CapacityExceeded),
  )
  assert_eq(host.database.client_read_evidence_schema().unwrap(), 0)
  assert_eq(
    host.database.read("client_local_read_evidence", bodies.egress.cid).unwrap().body,
    packet,
  )
  host.migrate_journal_append_metadata("operator", "cli", 1024L).unwrap()
  assert_eq(host.database.client_read_evidence_schema().unwrap(), 1)
  let saved = host.database
    .read("client_local_read_evidence", bodies.egress.cid)
    .unwrap()
  assert_eq(saved.body, packet)
  assert_eq(saved.revision, 0L)
  let same_epoch = host.database
    .read("client_submission_epoch", "authority")
    .unwrap()
  assert_eq(same_epoch.body, epoch.body)
  assert_eq(same_epoch.revision, epoch.revision)
  assert_eq(
    binding.retain_read_admission(original, facts, policy).unwrap().egress_admission_cid,
    bodies.egress.cid,
  )
  binding
  .retain_read_admission(
    original,
    { ..facts, request: { ..facts.request, attempt_id: "new-after-index", }, },
    policy,
  )
  .unwrap()
  |> ignore
  assert_eq(
    host.database.read("client_local_read_custody", "issued").unwrap().body,
    b"3",
  )
  host.close().unwrap()
}

///|
test "evidence migration install refusal and lost commit never publish a format ACK" {
  for lost_commit in [false, true] {
    let (host, _, _, _, _) = read_evidence_fixture(
      "evidence-index-refusal-" + lost_commit.to_string(),
      legacy_evidence=true,
    )
    let calls : Array[String] = []
    let access = journal_test_operation_access(host.database, calls)
    let access = if lost_commit {
      access
    } else {
      { ..access, install_read_evidence_schema: _ => Err(@sqlite.Busy), }
    }
    if lost_commit {
      client_test_fail_commit_reply(host.database, 1)
    }
    let result = host.journal.transaction_with_reads(
      () => {
        host.migrate_read_evidence_schema_locked(1024L, operations=Some(access))
      },
      reads=Some(access.reads),
    )
    assert_eq(host.journal.observed_evidence_schema, None)
    if lost_commit {
      assert_true(result is Err(TransactionUnknown))
      assert_true(host.database.transaction_fenced())
      assert_true(host.journal.transaction(() => Ok(())) is Err(Fenced))
    } else {
      assert_true(result is Err(Physical(@sqlite.Busy)))
      assert_true(calls.contains("rollback"))
      assert_eq(host.database.client_read_evidence_schema().unwrap(), 0)
      assert_false(host.database.transaction_fenced())
    }
    host.close().unwrap()
  }
}

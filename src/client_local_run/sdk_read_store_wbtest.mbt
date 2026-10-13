///|
// Actual Common SELECT1/Receipt/stored-chain fixture; the row/current supplier
// below is a typed boundary fixture, not physical SQLite ACK or real Wasm.
test "SDK grant requires exact retained original evidence and preserves selected expiry" {
  let fixture = sdk_read_fixture()
  let at = "2026-10-13T00:00:04.000Z"
  let original = prepare_local_sdk_read_originals(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    at,
    16,
  ).unwrap()
  let (key, packet) = local_sdk_read_evidence_packet(original).unwrap()
  assert_eq(key, original.egress.1)
  assert_true(packet.length() <= 65536)
  let parsed = @json.parse(@utf8.decode(packet))
  guard parsed is Object(parsed) else { fail("Expected exact evidence object") }
  assert_eq(
    parsed.get("authorization_context"),
    Some(@json.to_json(original.authorization.0)),
  )
  assert_eq(parsed.get("data_ceiling"), Some(@json.to_json(original.ceiling.0)))
  assert_eq(
    parsed.get("egress_admission"),
    Some(@json.to_json(original.egress.0)),
  )
  assert_eq(
    parsed.get("request"),
    Some(
      @json.to_json(
        @host.client_request_identity_record_wire(original.request).unwrap(),
      ),
    ),
  )
  let queries : Array[(String, String)] = []
  let unchanged : () -> Result[Unit, String] = () => Ok(())
  let first = prepare_local_sdk_read_evidence_from_store(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    at,
    16,
    (_, _) => Ok(None),
    unchanged,
  ).unwrap()
  guard first is Append(first_row) else {
    fail("Expected first evidence proposal")
  }
  assert_eq(first_row.key, key)
  assert_eq(first_row.body, packet)
  assert_eq(first_row.revision, 0L)
  let projected = @json.parse(
    local_sdk_read_evidence_decision_wire(first).unwrap(),
  )
  guard projected is Object(projected) else {
    fail("Expected closed physical proposal")
  }
  assert_eq(projected.get("kind"), Some(@json.to_json("append")))
  assert_eq(
    projected.get("table"),
    Some(@json.to_json("client_local_read_evidence")),
  )
  assert_eq(projected.get("key"), Some(@json.to_json(key)))
  assert_eq(projected.get("body"), Some(@json.to_json(@utf8.decode(packet))))
  let retained = prepare_local_sdk_read_evidence_from_store(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    at,
    16,
    (_, _) => Ok(Some({ key, revision: 0L, body: packet, })),
    unchanged,
  ).unwrap()
  assert_true(retained is Retained(_))
  let checked = Ref(0)
  let current : () -> Result[Unit, String] = () => {
    checked.val += 1
    Ok(())
  }
  let grant = issue_local_sdk_read_grant_from_store(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    at,
    16,
    (table, actual_key) => {
      queries.push((table, actual_key))
      Ok(Some({ key, revision: 0L, body: packet, }))
    },
    current,
  ).unwrap()
  assert_eq(queries, [("client_local_read_evidence", key)])
  assert_eq(checked.val, 3)
  assert_eq(@publication.publication_contract_name(grant), "result_read_grant")
  let body = @json.parse(@publication.publication_contract_json(grant))
  guard body is Object(body) else { fail("Expected existing grant object") }
  // Fixed independent selection values, never copied product output as an oracle.
  assert_eq(body.get("purpose"), Some(@json.to_json("python-local-read")))
  assert_eq(
    body.get("expires_at"),
    Some(@json.to_json("2026-10-14T00:00:00.001Z")),
  )
  assert_eq(body.get("max_bytes"), Some(@json.to_json(65536.0)))
  assert_eq(body.get("max_uses"), Some(@json.to_json(1.0)))
  assert_eq(
    body.get("data_ceiling_cid"),
    Some(@json.to_json(original.ceiling.1)),
  )
  assert_eq(
    body.get("authorization_context_cid"),
    Some(@json.to_json(original.authorization.1)),
  )
  assert_eq(
    body.get("egress_admission_cid"),
    Some(@json.to_json(original.egress.1)),
  )
  (fixture.cleanup)()
}

///|
test "SDK missing changed failed or invalidated evidence cannot issue a grant or repair custody" {
  let fixture = sdk_read_fixture()
  let at = "2026-10-13T00:00:04.000Z"
  let original = prepare_local_sdk_read_originals(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    at,
    16,
  ).unwrap()
  let (key, packet) = local_sdk_read_evidence_packet(original).unwrap()
  let invoke = (read, current, observed_at) => {
    issue_local_sdk_read_grant_from_store(
      fixture.preflight,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      "answer",
      "jsonl",
      "sdk-read-original",
      observed_at,
      16,
      read,
      current,
    )
  }
  let current : () -> Result[Unit, String] = () => Ok(())
  assert_true(invoke((_, _) => Ok(None), current, at) is Err(MissingEvidence))
  assert_true(
    invoke((_, _) => Err("query_failed"), current, at)
    is Err(Observation("query_failed")),
  )
  let changed : Array[@host.ClientJournalPhysicalRow] = [
    { key: "foreign-key", revision: 0L, body: packet, },
    { key, revision: 1L, body: packet, },
    { key, revision: 0L, body: @utf8.encode("changed-body"), },
  ]
  for row in changed {
    assert_true(
      invoke((_, _) => Ok(Some(row)), current, at) is Err(ChangedEvidence),
    )
  }
  let queries = Ref(0)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    _,
    _,
  ) => {
    queries.val += 1
    Ok(Some({ key, revision: 0L, body: packet, }))
  }
  assert_true(
    invoke(read, () => Err("current_lost"), at)
    is Err(Observation("current_lost")),
  )
  assert_eq(queries.val, 0)
  assert_true(
    invoke(read, current, "2026-10-14T00:00:00.001Z")
    is Err(Preparation(Expired)),
  )
  assert_eq(queries.val, 0)
  for refused_check in [2, 3] {
    let checks = Ref(0)
    assert_true(
      invoke(
        read,
        () => {
          checks.val += 1
          if checks.val == refused_check {
            Err("current_lost")
          } else {
            Ok(())
          }
        },
        at,
      )
      is Err(Observation("current_lost")),
    )
    assert_eq(checks.val, refused_check)
  }
  // A callback invalidating the actual original view cannot reuse cached
  // materials or promote a physical row to an admitted grant.
  assert_true(
    invoke(
      (_, _) => {
        fixture.owner.cancel()
        Ok(Some({ key, revision: 0L, body: packet, }))
      },
      current,
      at,
    )
    is Err(Preparation(StoredChain(_))),
  )
  assert_eq(local_sdk_read_evidence_packet(original).unwrap(), (key, packet))
  (fixture.cleanup)()
}

///|
test "SDK final current callback cannot issue against a cancelled original view" {
  let fixture = sdk_read_fixture()
  let at = "2026-10-13T00:00:04.000Z"
  let original = prepare_local_sdk_read_originals(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    at,
    16,
  ).unwrap()
  let (key, packet) = local_sdk_read_evidence_packet(original).unwrap()
  let checks = Ref(0)
  let result : Result[
    @publication.PublicationContract,
    LocalSDKReadStoreIssue[String],
  ] = issue_local_sdk_read_grant_from_store(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    at,
    16,
    (_, _) => Ok(Some({ key, revision: 0L, body: packet, })),
    () => {
      checks.val += 1
      if checks.val == 3 {
        fixture.owner.cancel()
      }
      Ok(())
    },
  )
  assert_eq(checks.val, 3)
  assert_true(result is Err(Preparation(StoredChain(_))))
  (fixture.cleanup)()
}

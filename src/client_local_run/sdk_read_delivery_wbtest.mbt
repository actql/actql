///|
fn sdk_delivery_evidence(fixture : SDKReadFixture) -> (String, Bytes) {
  let originals = prepare_local_sdk_read_originals(
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
    "2026-10-13T00:00:04.000Z",
    16,
  ).unwrap()
  local_sdk_read_evidence_packet(originals).unwrap()
}

///|
fn sdk_delivery_prepare(
  fixture : SDKReadFixture,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String],
  current : () -> Result[Unit, String],
) -> Result[LocalSDKReadDeliveryPreparation, LocalSDKReadDeliveryIssue[String]] {
  prepare_local_sdk_read_delivery_from_store(
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
    "2026-10-13T00:00:04.000Z",
    16,
    read,
    current,
  )
}

///|
// Actual checked SELECT1 and complete stored-chain Owner; the Store supplier
// is a typed read fixture, not physical COMMIT/Wasmtime/product acceptance.
test "SDK delivery selects original first-attempt usage and streaming materials without writes" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let (key, packet) = sdk_delivery_evidence(fixture)
  let queries : Array[(String, String)] = []
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    requested_key,
  ) => {
    queries.push((table, requested_key))
    if table == "client_local_read_evidence" {
      Ok(Some({ key, revision: 0L, body: packet, }))
    } else {
      Ok(None)
    }
  }
  let prepared = sdk_delivery_prepare(fixture, read, () => Ok(())).unwrap()
  let (_, grant_cid) = local_sdk_read_delivery_original(prepared, 0).unwrap()
  let (_, attempt_cid) = local_sdk_read_delivery_original(prepared, 1).unwrap()
  let (streaming, _) = local_sdk_read_delivery_original(prepared, 2).unwrap()
  let (usage_key, revision, wire) = local_sdk_read_delivery_usage_row(prepared)
  assert_eq(usage_key, grant_cid)
  assert_eq(revision, None)
  assert_eq(
    local_sdk_read_delivery_attempt_key(prepared),
    "15c5ce53e793d368893655a92627f00fbcd5437b99471c16a90393db9bb9d214",
  )
  assert_eq(queries, [
    ("client_local_read_evidence", key),
    ("delivery_attempt", local_sdk_read_delivery_attempt_key(prepared)),
    ("result_read_grant_usage", grant_cid),
    ("client_local_read_evidence", key),
  ])
  let usage = @json.parse(@utf8.decode(wire))
  guard usage is Object(usage) else { fail("Expected existing usage wire") }
  assert_eq(usage.get("max_uses"), Some(@json.to_json(1)))
  assert_eq(usage.get("use_count"), Some(@json.to_json(1)))
  assert_eq(
    usage.get("version"),
    Some(@json.to_json("actql-result-read-grant-usage/0.1")),
  )
  assert_eq(
    usage.get("delivery_attempt_cids"),
    Some(@json.to_json([attempt_cid])),
  )
  let streaming = @json.parse(streaming)
  guard streaming is Object(streaming) else {
    fail("Expected streaming record")
  }
  assert_eq(streaming.get("state"), Some(@json.to_json("streaming")))
  assert_eq(streaming.get("confirmed_byte_count"), Some(@json.to_json(0)))
  assert_true(
    local_sdk_read_delivery_original(prepared, 3) is Err(InvalidOriginal),
  )
  // A previous claimed use without its attempt row is unresolved, not a
  // fresh delivery or permission to replay the original payload.
  assert_true(
    sdk_delivery_prepare(
      fixture,
      (table, requested_key) => {
        if table == "result_read_grant_usage" {
          Ok(Some({ key: requested_key, revision: 7L, body: wire, }))
        } else {
          read(table, requested_key)
        }
      },
      () => Ok(()),
    )
    is Err(UnresolvedUsage),
  )
  let empty_usage = @utf8.encode(
    "{\"delivery_attempt_cids\":[],\"grant_cid\":\"" +
    grant_cid +
    "\",\"max_uses\":1,\"use_count\":0,\"version\":\"actql-result-read-grant-usage/0.1\"}",
  )
  let retained = sdk_delivery_prepare(
    fixture,
    (table, requested_key) => {
      if table == "result_read_grant_usage" {
        Ok(Some({ key: requested_key, revision: 7L, body: empty_usage, }))
      } else {
        read(table, requested_key)
      }
    },
    () => Ok(()),
  ).unwrap()
  assert_eq(
    local_sdk_read_delivery_usage_row(retained),
    (usage_key, Some(7L), wire),
  )
}

///|
test "SDK delivery keeps lookup failure existing attempt and post-callback invalidation distinct" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let (key, packet) = sdk_delivery_evidence(fixture)
  let evidence : (String, String) -> Result[
    @host.ClientJournalPhysicalRow?,
    String,
  ] = (table, _) => {
    if table == "client_local_read_evidence" {
      Ok(Some({ key, revision: 0L, body: packet, }))
    } else {
      Ok(None)
    }
  }
  assert_true(
    sdk_delivery_prepare(
      fixture,
      (table, requested_key) => {
        if table == "delivery_attempt" {
          Err("original query failed")
        } else {
          evidence(table, requested_key)
        }
      },
      () => Ok(()),
    )
    is Err(Observation("original query failed")),
  )
  assert_true(
    sdk_delivery_prepare(
      fixture,
      (table, requested_key) => {
        if table == "delivery_attempt" {
          Ok(
            Some({
              key: requested_key,
              revision: 0L,
              body: b"opaque-saved-attempt",
            }),
          )
        } else {
          evidence(table, requested_key)
        }
      },
      () => Ok(()),
    )
    is Err(ExistingAttempt),
  )
  assert_true(
    sdk_delivery_prepare(
      fixture,
      (table, requested_key) => {
        if table == "result_read_grant_usage" {
          Ok(
            Some({ key: requested_key, revision: 0L, body: b"invalid-usage", }),
          )
        } else {
          evidence(table, requested_key)
        }
      },
      () => Ok(()),
    )
    is Err(Usage(DeliveryGrantUsageInvalidWire)),
  )
  let valid = Ref(true)
  assert_true(
    sdk_delivery_prepare(
      fixture,
      (table, requested_key) => {
        if table == "result_read_grant_usage" {
          valid.val = false
        }
        evidence(table, requested_key)
      },
      () => if valid.val { Ok(()) } else { Err("publisher revoked") },
    )
    is Err(Store(Observation("publisher revoked"))),
  )
  assert_true(
    sdk_delivery_prepare(
      fixture,
      (table, requested_key) => {
        if table == "result_read_grant_usage" {
          ignore(fixture.owner.cancel())
        }
        evidence(table, requested_key)
      },
      () => Ok(()),
    )
    is Err(Store(Preparation(StoredChain(_)))),
  )
}

///|
test "SDK delivery storage projects six original CAS writes and rejects partial installations" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let (key, packet) = sdk_delivery_evidence(fixture)
  let prepare = (
    read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String],
  ) => {
    prepare_local_sdk_read_delivery_storage_from_store(
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
      "2026-10-13T00:00:04.000Z",
      16,
      read,
      () => Ok(()),
    )
  }
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    _,
  ) => {
    if table == "client_local_read_evidence" {
      Ok(Some({ key, revision: 0L, body: packet, }))
    } else {
      Ok(None)
    }
  }
  let wire = prepare(read).unwrap()
  assert_true(@utf8.encode(wire).length() <= 1048576)
  guard @json.parse(wire) is Array(rows) && rows.length() == 6 else {
    fail("Expected six original physical writes")
  }
  let tables = [
    "publication_contract", "publication_contract", "publication_contract", "delivery_attempt",
    "result_read_grant_usage", "delivery_record_head",
  ]
  for ordinal in 0..<6 {
    guard rows[ordinal] is Object(row) else { fail("Expected closed row") }
    assert_eq(row.length(), 4)
    assert_eq(row.get("table"), Some(@json.to_json(tables[ordinal])))
    assert_eq(row.get("revision"), Some(@json.parse("null")))
  }
  assert_true(
    prepare((table, requested_key) => {
      if table == "publication_contract" {
        Ok(
          Some({ key: requested_key, revision: 0L, body: b"retained-contract", }),
        )
      } else {
        read(table, requested_key)
      }
    })
    is Err(UnresolvedUsage),
  )
  assert_true(
    prepare((table, requested_key) => {
      if table == "delivery_record_head" {
        Err("original head query failed")
      } else {
        read(table, requested_key)
      }
    })
    is Err(Observation("original head query failed")),
  )
}

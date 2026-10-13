///|
fn sdk_delivery_saved_rows(
  fixture : SDKReadFixture,
) -> Map[String, @host.ClientJournalPhysicalRow] {
  let (key, packet) = sdk_delivery_evidence(fixture)
  let rows : Map[String, @host.ClientJournalPhysicalRow] = Map([])
  rows.set("client_local_read_evidence|" + key, {
    key,
    revision: 0L,
    body: packet,
  })
  let read = (table, key) => Ok(rows.get(table + "|" + key))
  let prepared = sdk_delivery_prepare(fixture, read, () => Ok(())).unwrap()
  for ordinal in 0..<3 {
    let (wire, cid) = local_sdk_read_delivery_original(prepared, ordinal).unwrap()
    rows.set("publication_contract|" + cid, {
      key: cid,
      revision: 0L,
      body: @utf8.encode(wire),
    })
  }
  let attempt_key = local_sdk_read_delivery_attempt_key(prepared)
  let (_, attempt_cid) = local_sdk_read_delivery_original(prepared, 1).unwrap()
  let (record, _) = local_sdk_read_delivery_original(prepared, 2).unwrap()
  rows.set("delivery_attempt|" + attempt_key, {
    key: attempt_key,
    revision: 0L,
    body: @utf8.encode(attempt_cid),
  })
  rows.set("delivery_record_head|" + attempt_cid, {
    key: attempt_cid,
    revision: 0L,
    body: @utf8.encode(record),
  })
  let (usage_key, _, usage) = local_sdk_read_delivery_usage_row(prepared)
  rows.set("result_read_grant_usage|" + usage_key, {
    key: usage_key,
    revision: 0L,
    body: usage,
  })
  rows
}

///|
fn sdk_delivery_observe(
  fixture : SDKReadFixture,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String],
  current : () -> Result[Unit, String],
) -> Result[
  LocalSDKReadDeliveryObservation,
  LocalSDKReadDeliveryObservationIssue[String],
] {
  observe_local_sdk_read_delivery_from_store(
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
    16,
    read,
    current,
  )
}

///|
// Real Common checker/Run/Receipt/stored-chain Owners; the bounded row/current
// supplier is a typed fixture, not physical SQLite ACK or actual Wasm.
test "SDK delivery lookup preserves streaming and older original attempt without new usage" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let rows = sdk_delivery_saved_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  let original = sdk_delivery_observe(fixture, read, () => Ok(())).unwrap()
  let wire = local_sdk_read_delivery_lookup_wire(
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
    16,
    read,
    () => Ok(()),
  ).unwrap()
  assert_true(@utf8.encode(wire).length() <= 8192)
  guard @json.parse(wire) is Object(found) else {
    fail("Expected closed found wire")
  }
  assert_eq(found.length(), 4)
  assert_eq(found.get("kind"), Some(@json.to_json("found")))
  assert_eq(found.get("hostReleaseReceipt"), Some(@json.parse("null")))
  assert_eq(
    local_sdk_read_delivery_observation_action(original),
    @publication.DeliveryRejectUnresolvedAttempt,
  )
  assert_eq(
    local_sdk_read_delivery_observation_original(original, 3).unwrap(),
    None,
  )
  assert_true(
    local_sdk_read_delivery_observation_original(original, 4)
    is Err(InvalidOriginal),
  )
  let (grant_wire, grant_cid) = local_sdk_read_delivery_observation_original(
      original, 0,
    )
    .unwrap()
    .unwrap()
  let grant = @publication.admit_publication_contract(
    "result_read_grant", grant_wire, 65536, 8192, 64,
  ).unwrap()
  // Historical metadata remains available after the original grant expires;
  // the same saved grant cannot authorize a fresh payload at this later time.
  assert_false(
    @publication.result_read_grant_valid_at(grant, "2026-10-15T00:00:00.000Z"),
  )
  assert_true(sdk_delivery_observe(fixture, read, () => Ok(())) is Ok(_))
  let materials = fixture.owner
    .observed_result_read_materials(fixture.view, "answer", 16)
    .unwrap()
  let older = @publication.issue_delivery_attempt(
    materials.index,
    materials.manifest,
    grant,
    "answer",
    "jsonl",
    "sdk-read-original",
    "2026-10-13T00:00:03.000Z",
    65536,
    8192,
    64,
  ).unwrap()
  let older_cid = @publication.publication_contract_identity(older)
  rows.set("publication_contract|" + older_cid, {
    key: older_cid,
    revision: 0L,
    body: @utf8.encode(@publication.publication_contract_json(older)),
  })
  let attempt_key = "15c5ce53e793d368893655a92627f00fbcd5437b99471c16a90393db9bb9d214"
  rows.set("delivery_attempt|" + attempt_key, {
    key: attempt_key,
    revision: 0L,
    body: @utf8.encode(older_cid),
  })
  let usage = @publication.prepare_delivery_grant_usage_claim(
    grant,
    None,
    older,
    65536,
    8192,
    64,
  ).unwrap()
  rows.set("result_read_grant_usage|" + grant_cid, {
    key: grant_cid,
    revision: 0L,
    body: @utf8.encode(@publication.delivery_grant_usage_claim_wire(usage)),
  })
  let record = @publication.issue_delivery_record(
    older,
    None,
    "streaming",
    0,
    "exact",
    None,
    None,
    None,
    None,
    "2026-10-13T00:00:03.000Z",
    [],
    65536,
    8192,
    64,
  ).unwrap()
  rows.set("delivery_record_head|" + older_cid, {
    key: older_cid,
    revision: 0L,
    body: @utf8.encode(@publication.publication_contract_json(record)),
  })
  let retained = sdk_delivery_observe(fixture, read, () => Ok(())).unwrap()
  let (wire, cid) = local_sdk_read_delivery_observation_original(retained, 1)
    .unwrap()
    .unwrap()
  assert_eq(cid, older_cid)
  guard @json.parse(wire) is Object(body) else {
    fail("Expected actual saved attempt")
  }
  assert_eq(
    body.get("requested_at"),
    Some(@json.to_json("2026-10-13T00:00:03.000Z")),
  )
  assert_eq(
    local_sdk_read_delivery_observation_action(retained),
    @publication.DeliveryRejectUnresolvedAttempt,
  )
}

///|
test "SDK delivery lookup separates confirmed miss query failure partial usage and foreign grant" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let rows = sdk_delivery_saved_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  assert_eq(
    local_sdk_read_delivery_lookup_wire(
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
      16,
      (table, key) => {
        if table == "delivery_attempt" {
          Ok(None)
        } else {
          read(table, key)
        }
      },
      () => Ok(()),
    ).unwrap(),
    "{\"kind\":\"not_found\"}",
  )
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, key) => {
        if table == "delivery_attempt" {
          Ok(None)
        } else {
          read(table, key)
        }
      },
      () => Ok(()),
    )
    is Err(MissingAttempt),
  )
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, key) => {
        if table == "delivery_attempt" {
          Err("original lookup failed")
        } else {
          read(table, key)
        }
      },
      () => Ok(()),
    )
    is Err(Observation("original lookup failed")),
  )
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, key) => {
        if table == "result_read_grant_usage" {
          Ok(None)
        } else {
          read(table, key)
        }
      },
      () => Ok(()),
    )
    is Err(MissingOriginal),
  )
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, key) => {
        if table == "publication_contract" {
          Ok(
            Some({
              key: "sha256:" + "0".repeat(64),
              revision: 0L,
              body: b"foreign-contract",
            }),
          )
        } else {
          read(table, key)
        }
      },
      () => Ok(()),
    )
    is Err(ChangedOriginal),
  )
  let observed = sdk_delivery_observe(fixture, read, () => Ok(())).unwrap()
  let (_, grant_cid) = local_sdk_read_delivery_observation_original(observed, 0)
    .unwrap()
    .unwrap()
  let empty_usage = @utf8.encode(
    "{\"delivery_attempt_cids\":[],\"grant_cid\":\"" +
    grant_cid +
    "\",\"max_uses\":1,\"use_count\":0,\"version\":\"actql-result-read-grant-usage/0.1\"}",
  )
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, key) => {
        if table == "result_read_grant_usage" {
          Ok(Some({ key, revision: 0L, body: empty_usage, }))
        } else {
          read(table, key)
        }
      },
      () => Ok(()),
    )
    is Err(MissingOriginal),
  )
  let partial = sdk_delivery_observe(
    fixture,
    (table, key) => {
      if table == "delivery_record_head" {
        Ok(None)
      } else {
        read(table, key)
      }
    },
    () => Ok(()),
  ).unwrap()
  assert_eq(
    local_sdk_read_delivery_observation_action(partial),
    @publication.ExistingDeliveryAttemptInvalid,
  )
  assert_eq(
    local_sdk_read_delivery_observation_original(partial, 2).unwrap(),
    None,
  )
}

///|
test "SDK delivery lookup rechecks current publisher and original chain after head observation" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let rows = sdk_delivery_saved_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  let current = Ref(true)
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, key) => {
        if table == "delivery_record_head" {
          current.val = false
        }
        read(table, key)
      },
      () => if current.val { Ok(()) } else { Err("publisher revoked") },
    )
    is Err(Store(Observation("publisher revoked"))),
  )
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, key) => {
        if table == "delivery_record_head" {
          ignore(fixture.owner.cancel())
        }
        read(table, key)
      },
      () => Ok(()),
    )
    is Err(Store(Preparation(StoredChain(_)))),
  )
}

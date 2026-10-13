///|
fn sdk_payload_current(
  fixture : SDKReadFixture,
  first : LocalSDKReadDeliveryPreparation,
  at : String,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String],
  current : () -> Result[Unit, String],
) -> Result[Unit, LocalSDKReadPayloadCodecIssue[String]] {
  validate_local_sdk_payload_encoding_current(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    first,
    "answer",
    "jsonl",
    "sdk-read-original",
    at,
    16,
    read,
    current,
  )
}

///|
// Existing checked publication and typed Store supplier, not physical bytes,
// permission renewal, terminal delivery, actual Wasm or installed acceptance.
test "SDK payload current projection preserves the original grant and streaming head" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let first = sdk_payload_codec_first(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  let grant = @publication.publication_contract_json(first.grant)
  assert_true(
    sdk_payload_current(fixture, first, "2026-10-13T00:00:05.000Z", read, () => {
      Ok(())
    })
    is Ok(_),
  )
  assert_eq(@publication.publication_contract_json(first.grant), grant)
  let observation = sdk_delivery_observe(fixture, read, () => Ok(())).unwrap()
  assert_true(observation.receipt is None)
}

///|
test "SDK payload current rejects query failure expiry and callback revocation" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let first = sdk_payload_codec_first(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  assert_true(
    sdk_payload_current(
      fixture,
      first,
      "2026-10-13T00:00:05.000Z",
      (_, _) => Err("query-failed"),
      () => Ok(()),
    )
    is Err(Original(Observation("query-failed"))),
  )
  assert_true(
    sdk_payload_current(fixture, first, "2026-10-15T00:00:00.000Z", read, () => {
      Ok(())
    })
    is Err(Store(Preparation(Expired))),
  )
  let current = Ref(true)
  assert_true(
    sdk_payload_current(
      fixture,
      first,
      "2026-10-13T00:00:05.000Z",
      (table, key) => {
        let row = rows.get(table + "|" + key)
        current.val = false
        Ok(row)
      },
      () => if current.val { Ok(()) } else { Err("revoked") },
    )
    is Err(Original(Store(Observation("revoked")))),
  )
}

///|
test "SDK payload current rejects a substituted grant without creating a receipt" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let original = sdk_payload_codec_first(fixture)
  let foreign : LocalSDKReadDeliveryPreparation = {
    grant: original.attempt,
    attempt: original.attempt,
    streaming: original.streaming,
    attempt_key: original.attempt_key,
    usage_key: original.usage_key,
    usage_revision: original.usage_revision,
    usage: original.usage,
  }
  let rows = sdk_payload_codec_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  assert_true(
    sdk_payload_current(fixture, foreign, "2026-10-13T00:00:05.000Z", read, () => {
      Ok(())
    })
    is Err(ChangedOriginal),
  )
  assert_true(
    sdk_delivery_observe(fixture, read, () => Ok(())).unwrap().receipt is None,
  )
  let cancelled = @publication.issue_delivery_record(
    original.attempt,
    Some(original.streaming),
    "cancelled",
    0,
    "exact",
    None,
    None,
    None,
    None,
    "2026-10-13T00:00:05.000Z",
    [],
    65536,
    8192,
    64,
  ).unwrap()
  let attempt_cid = @publication.publication_contract_identity(original.attempt)
  let evidence_reads = Ref(0)
  assert_true(
    sdk_payload_current(
      fixture,
      original,
      "2026-10-13T00:00:05.000Z",
      (table, key) => {
        let row = rows.get(table + "|" + key)
        if table == "client_local_read_evidence" {
          evidence_reads.val += 1
          if evidence_reads.val == 2 {
            rows.set("delivery_record_head|" + attempt_cid, {
              key: attempt_cid,
              revision: 1L,
              body: @utf8.encode(
                @publication.publication_contract_json(cancelled),
              ),
            })
          }
        }
        Ok(row)
      },
      () => Ok(()),
    )
    is Err(ChangedOriginal),
  )
}

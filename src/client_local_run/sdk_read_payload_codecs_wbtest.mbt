///|
fn sdk_payload_codec_first(
  fixture : SDKReadFixture,
) -> LocalSDKReadDeliveryPreparation {
  let (key, packet) = sdk_delivery_evidence(fixture)
  sdk_delivery_prepare(
    fixture,
    (table, _) => {
      if table == "client_local_read_evidence" {
        Ok(Some({ key, revision: 0L, body: packet, }))
      } else {
        Ok(None)
      }
    },
    () => Ok(()),
  ).unwrap()
}

///|
fn sdk_payload_codec_rows(
  fixture : SDKReadFixture,
) -> Map[String, @host.ClientJournalPhysicalRow] {
  let rows = sdk_delivery_saved_rows(fixture)
  let original = fixture.owner
    .observed_result_read_materials(fixture.view, "answer", 16)
    .unwrap().read
  // The independent numeric literal uses the existing Number delivery schema.
  // Its value and expected jsonl bytes below are not copied from a serializer.
  rows.set("result_schema|" + original.result_schema_cid, {
    key: original.result_schema_cid,
    revision: 0L,
    body: b"{\"n\":{\"nullable\":false,\"type\":\"number\"}}",
  })
  rows
}

///|
fn sdk_payload_codecs(
  fixture : SDKReadFixture,
  first : LocalSDKReadDeliveryPreparation,
  at : String,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String],
  current : () -> Result[Unit, String],
) -> Result[
  (@publication.DurableResultRowFrames, @publication.ResultDeliverySerializer),
  LocalSDKReadPayloadCodecIssue[String],
] {
  prepare_local_sdk_read_payload_codecs(
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
    65536,
    65536,
    read,
    current,
  )
}

///|
// Real checked task/Receipt/stored chain and existing codecs; typed Store
// supplier only. No physical reader, byte disclosure, sink ACK or real Wasm.
test "SDK payload codec selects original schema order and existing bounded codecs" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let first = sdk_payload_codec_first(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  let (frames, serializer) = sdk_payload_codecs(
    fixture,
    first,
    "2026-10-13T00:00:05.000Z",
    (table, key) => Ok(rows.get(table + "|" + key)),
    () => Ok(()),
  ).unwrap()
  assert_eq(@publication.begin_result_delivery(serializer), Ok(""))
  assert_eq(
    @publication.feed_durable_result_row_frames(frames, b"[{\"n\":"),
    Ok([]),
  )
  assert_eq(
    @publication.feed_durable_result_row_frames(frames, b"1}]"),
    Ok(["{\"n\":1}"]),
  )
  assert_eq(
    @publication.next_result_delivery_row(serializer, "{\"n\":1}"),
    Ok("{\"n\":1}\n"),
  )
  assert_eq(
    @publication.finish_durable_result_row_frames(frames),
    Ok({ bytes: 9, rows: 1, }),
  )
  assert_eq(@publication.finish_result_delivery(serializer), Ok(""))
  // Codec completion has no delivery receipt or Store/Run terminal meaning.
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, key) => Ok(rows.get(table + "|" + key)),
      () => Ok(()),
    ).unwrap().receipt
    is None,
  )
}

///|
test "SDK payload codec refuses query failure foreign schema and expired byte access" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let first = sdk_payload_codec_first(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  assert_true(
    sdk_payload_codecs(
      fixture,
      first,
      "2026-10-13T00:00:05.000Z",
      (table, key) => {
        if table == "result_schema" {
          Err("query-failed")
        } else {
          read(table, key)
        }
      },
      () => Ok(()),
    )
    is Err(Observation("query-failed")),
  )
  assert_true(
    sdk_payload_codecs(
      fixture,
      first,
      "2026-10-13T00:00:05.000Z",
      (table, key) => {
        if table == "result_schema" {
          Ok(
            Some({
              key,
              revision: 0L,
              body: b"{\"n\":{\"nullable\":false,\"type\":\"string\"}}",
            }),
          )
        } else {
          read(table, key)
        }
      },
      () => Ok(()),
    )
    is Err(Schema(_)),
  )
  assert_true(sdk_delivery_observe(fixture, read, () => Ok(())) is Ok(_))
  assert_true(
    sdk_payload_codecs(fixture, first, "2026-10-15T00:00:00.000Z", read, () => {
      Ok(())
    })
    is Err(Store(Preparation(Expired))),
  )
}

///|
test "SDK payload codec refuses schema callback revocation and changed initial record" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let first = sdk_payload_codec_first(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  let current = Ref(true)
  assert_true(
    sdk_payload_codecs(
      fixture,
      first,
      "2026-10-13T00:00:05.000Z",
      (table, key) => {
        if table == "result_schema" {
          current.val = false
        }
        Ok(rows.get(table + "|" + key))
      },
      () => if current.val { Ok(()) } else { Err("revoked") },
    )
    is Err(Store(Observation("revoked"))),
  )
  let changed : LocalSDKReadDeliveryPreparation = {
    ..first,
    streaming: first.attempt,
  }
  assert_true(
    sdk_payload_codecs(
      fixture,
      changed,
      "2026-10-13T00:00:05.000Z",
      (table, key) => Ok(rows.get(table + "|" + key)),
      () => Ok(()),
    )
    is Err(ChangedOriginal),
  )
}

///|
test "SDK payload codec rechecks original delivery head after schema callback" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let first = sdk_payload_codec_first(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  let changed = @publication.issue_delivery_record(
    first.attempt,
    Some(first.streaming),
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
  let attempt_cid = @publication.publication_contract_identity(first.attempt)
  assert_true(
    sdk_payload_codecs(
      fixture,
      first,
      "2026-10-13T00:00:05.000Z",
      (table, key) => {
        if table == "result_schema" {
          rows.set("delivery_record_head|" + attempt_cid, {
            key: attempt_cid,
            revision: 1L,
            body: @utf8.encode(@publication.publication_contract_json(changed)),
          })
        }
        Ok(rows.get(table + "|" + key))
      },
      () => Ok(()),
    )
    is Err(ChangedOriginal),
  )
}

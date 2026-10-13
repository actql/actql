///|
// Independent SHA256 of the literal SDK jsonl vector, not product output.
let sdk_payload_expected_delivery_hash = "cedf74272c9fc8db5448283a93277e7e7eb7534b71df3bd8ab35fd9b1b73404c"

///|
fn sdk_payload_encoding_fixture(
  fixture : SDKReadFixture,
) -> LocalSDKPayloadEncoding {
  let first = sdk_payload_codec_first(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  prepare_local_sdk_payload_encoding_from_store(
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
    "2026-10-13T00:00:05.000Z",
    16,
    65536,
    65536,
    read,
    () => Ok(()),
  ).unwrap()
}

///|
// Existing checked SELECT1/receipt/full chain and actual codecs/sink Owner.
// The physical byte supplier is an independent fixed vector, not a File/SDK
// sink, Store ACK, real Wasm or installed product acceptance.
test "SDK payload encoding separates physical EOF serialization and sink receipt" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  assert_true(encoding.prepare_input() is Ok(_))
  assert_eq(encoding.feed(b"[{\"n\":", false), Ok(b""))
  assert_true(
    encoding.confirm_finished() is Err(Sink(DeliverySinkSourceIncomplete)),
  )
  assert_eq(encoding.feed(b"1}]", true), Ok(b"{\"n\":1}\n"))
  assert_true(encoding.prepare_input() is Err(Sink(DeliverySinkClosed)))
  assert_true(
    encoding.confirm_finished() is Err(Sink(DeliverySinkSourceIncomplete)),
  )
  assert_eq(encoding.confirm_chunk(), Ok(8L))
  let receipt = encoding.confirm_finished().unwrap()
  guard @json.parse(@publication.publication_contract_json(receipt))
    is Object(body) else {
    fail("Expected original delivery receipt")
  }
  assert_eq(body.get("delivered_byte_count"), Some(@json.parse("8")))
  assert_eq(body.get("result_name"), Some(@json.to_json("answer")))
  assert_eq(
    body.get("delivered_sha256"),
    Some(@json.to_json(sdk_payload_expected_delivery_hash)),
  )
  // Receipt generation still does not install a delivery head or finish Run.
  let rows = sdk_payload_codec_rows(fixture)
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
test "SDK payload encoding rejects changed content without a sink success" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  // Same byte/row counts as the original, but independently different value.
  assert_true(encoding.feed(b"[{\"n\":2}]", true) is Err(ContentMismatch))
  assert_true(encoding.confirm_chunk() is Err(ContentMismatch))
  assert_true(encoding.confirm_finished() is Err(ContentMismatch))
  assert_true(encoding.feed(b"[{\"n\":1}]", true) is Err(ContentMismatch))
  encoding.cancel_frames()
}

///|
test "SDK payload encoding preserves outstanding sink progress before next input" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  assert_eq(encoding.feed(b"[{\"n\":1}", false), Ok(b"{\"n\":1}\n"))
  assert_true(
    encoding.prepare_input() is Err(Sink(DeliverySinkChunkOutstanding)),
  )
  assert_true(
    encoding.feed(b"]", true) is Err(Sink(DeliverySinkChunkOutstanding)),
  )
  assert_eq(encoding.confirm_chunk(), Ok(8L))
  assert_true(encoding.prepare_input() is Ok(_))
  assert_eq(encoding.feed(b"]", true), Ok(b""))
  assert_true(encoding.confirm_finished() is Ok(_))
  encoding.cancel_frames()
  assert_true(encoding.prepare_input() is Err(Frames(DurableRowFrameClosed)))
  assert_true(encoding.confirm_finished() is Err(Frames(DurableRowFrameClosed)))
}

///|
test "SDK payload encoder cannot substitute a different serialization for the original attempt" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let first = sdk_payload_codec_first(fixture)
  let reads = Ref(0)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    _,
    _,
  ) => {
    reads.val += 1
    Ok(None)
  }
  assert_true(
    prepare_local_sdk_payload_encoding_from_store(
      fixture.preflight,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      first,
      "answer",
      "json",
      "sdk-read-original",
      "2026-10-13T00:00:05.000Z",
      16,
      65536,
      65536,
      read,
      () => Ok(()),
    )
    is Err(Codecs(Original(Store(Preparation(InvalidSelection))))),
  )
  assert_eq(reads.val, 0)
}

///|
test "SDK payload empty outputs retain cumulative progress through independent 4 4 1 framing" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  // Independent slices of the original nine-byte JSON literal, not a codec
  // implementation in Python or an inferred sink acknowledgement.
  assert_eq(encoding.feed(b"[{\"n", false), Ok(b""))
  assert_eq(encoding.observe_empty_output(), Ok(0L))
  assert_true(
    encoding.confirm_chunk() is Err(Sink(DeliverySinkNoOutstandingChunk)),
  )
  assert_eq(encoding.feed(b"\":1}", false), Ok(b"{\"n\":1}\n"))
  assert_true(
    encoding.observe_empty_output() is Err(Sink(DeliverySinkChunkOutstanding)),
  )
  assert_eq(encoding.confirm_chunk(), Ok(8L))
  assert_eq(encoding.feed(b"]", true), Ok(b""))
  assert_eq(encoding.observe_empty_output(), Ok(8L))
  assert_true(encoding.confirm_finished() is Ok(_))
  assert_true(encoding.observe_empty_output() is Err(Sink(DeliverySinkClosed)))
  encoding.cancel_frames()
  assert_true(
    encoding.observe_empty_output() is Err(Frames(DurableRowFrameClosed)),
  )
}

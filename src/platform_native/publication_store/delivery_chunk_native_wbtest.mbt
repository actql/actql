///|
test "native delivery fills selected chunks across original rows and confirms exact prefixes" {
  guard native_payload_fixture("delivery-chunks", 4096L)
    is Some((store, authority, _, _)) else {
    fail("Native SQLite delivery fixture is required")
  }
  let rows = Array::makei(32, index => "{\"n\":" + index.to_string() + "}")
  let payload = "[" + rows.join(",") + "]"
  let request = native_payload_request(
    authority,
    "delivery-chunks",
    1024L,
    row_count=32L,
  )
  let writer = store.begin_payload(request).unwrap()
  writer.append(@utf8.encode(payload)).unwrap()
  let info = writer.seal().unwrap()
  let csv = "\"n\"\n" +
    Array::makei(32, index => index.to_string() + "\n").join("")
  for
    (format, text) in [
      ("jsonl", rows.join("\n") + "\n"),
      ("json", payload),
      ("csv", csv),
    ] {
    let stream = store
      .open_confirmed_payload_delivery(
        info.material_generation_cid,
        format,
        "{\"n\":{\"nullable\":false,\"type\":\"integer\"}}",
        ["n"],
        64,
        64,
        16,
        4,
        1024L,
      )
      .unwrap()
    // Explicit standalone construction port: this proves batching protocol,
    // not the installed original Read's physical funding implementation.
    let constructions = Ref(0)
    stream.source.chunk_construction = Some(target => {
      if target != 64 {
        return Err(InvalidConfiguration)
      }
      constructions.val += 1
      Ok(())
    })
    let expected = @utf8.encode(text)
    let mut offset = 0
    let mut chunks = 0
    while true {
      // Larger requests cannot enlarge the original selected input window.
      let chunk = stream.next(256).unwrap()
      assert_eq(chunk.bytes.length(), Int::min(64, expected.length() - offset))
      assert_eq(
        chunk.bytes,
        expected[offset:offset + chunk.bytes.length()].to_owned(),
      )
      offset += chunk.bytes.length()
      if chunk.bytes.length() > 0 {
        chunks += 1
        if chunks == 1 && format == "jsonl" {
          // Eight complete rows fill64 exactly. The ninth serializer call is
          // not allowed merely to discover whether another row follows.
          assert_eq(stream.source.emitted_rows, 8L)
          assert_false(chunk.eof)
        }
        if chunk.eof {
          assert_true(
            stream.next(64)
            is Err(SinkProgress(@publication.DeliverySinkClosed)),
          )
        } else {
          assert_true(
            stream.next(64)
            is Err(SinkProgress(@publication.DeliverySinkChunkOutstanding)),
          )
        }
        assert_eq(stream.confirm_chunk().unwrap(), offset.to_int64())
      }
      if chunk.eof {
        break
      }
    }
    assert_eq(chunks, (expected.length() + 63) / 64)
    assert_eq(constructions.val, 1)
    let summary = stream.confirm_sink_finished().unwrap()
    assert_eq(summary.bytes, expected.length().to_int64())
    assert_eq(summary.rows, 32L)
    assert_eq(summary.delivery_digest, "sha256:" + @sha.hex(expected))
    stream.close().unwrap()
    stream.close().unwrap()
    assert_true(stream.next(64) is Err(Closed))
  }
  store.reclaim_payload(info.material_generation_cid).unwrap()
  assert_true(store.close().unwrap())
}

///|
test "native delivery spans a row and stops before a later serialization refusal" {
  guard native_payload_fixture("delivery-boundaries", 4096L)
    is Some((store, authority, _, _)) else {
    fail("Native SQLite delivery fixture is required")
  }
  let request = native_payload_request(
    authority, "delivery-no-lookahead", 1024L,
  )
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"[{\"n\":0},{\"wrong\":1}]").unwrap()
  let info = writer.seal().unwrap()
  let stream = store
    .open_confirmed_payload_delivery(
      info.material_generation_cid,
      "jsonl",
      "{\"n\":{\"nullable\":false,\"type\":\"integer\"}}",
      ["n"],
      64,
      64,
      16,
      4,
      1024L,
    )
    .unwrap()
  stream.source.chunk_construction = Some(_ => Ok(()))
  let first = stream.next(5).unwrap()
  assert_eq(first.bytes, b"{\"n\":")
  assert_eq(stream.source.emitted_rows, 1L)
  assert_false(first.eof)
  assert_eq(stream.confirm_chunk().unwrap(), 5L)
  let rest = stream.next(3).unwrap()
  assert_eq(rest.bytes, b"0}\n")
  assert_eq(stream.source.emitted_rows, 1L)
  assert_false(rest.eof)
  assert_eq(stream.confirm_chunk().unwrap(), 8L)
  assert_true(
    stream.next(64)
    is Err(Delivery(@publication.DeliverySerializationInvalidRow)),
  )
  assert_true(
    store.reclaim_payload(info.material_generation_cid) is Err(ReaderBusy),
  )
  stream.close().unwrap()
  assert_true(stream.next(64) is Err(Closed))
  store.reclaim_payload(info.material_generation_cid).unwrap()
  assert_true(store.close().unwrap())
}

///|
test "native delivery refuses construction before advancing and leaves unmanaged chunks unchanged" {
  guard native_payload_fixture("delivery-funding", 4096L)
    is Some((store, authority, _, _)) else {
    fail("Native SQLite delivery fixture is required")
  }
  let writer = store
    .begin_payload(native_payload_request(authority, "delivery-funding", 1024L))
    .unwrap()
  writer.append(b"[{\"n\":0},{\"n\":1}]").unwrap()
  let info = writer.seal().unwrap()
  let schema = "{\"n\":{\"nullable\":false,\"type\":\"integer\"}}"
  let stream = store
    .open_payload_delivery(
      info.material_generation_cid,
      "jsonl",
      schema,
      ["n"],
      64,
      64,
      16,
      4,
      1024L,
    )
    .unwrap()
  let calls = Ref(0)
  stream.chunk_construction = Some(_ => {
    calls.val += 1
    Err(DeliveryLimit)
  })
  assert_true(stream.next(64) is Err(DeliveryLimit))
  assert_eq(calls.val, 1)
  assert_eq(stream.funded_chunk_bytes, 0)
  assert_eq(stream.emitted_bytes, 0L)
  assert_eq(stream.emitted_rows, 0L)
  assert_eq(stream.pending_offset, 0)
  assert_eq(stream.queued_rows.length(), 0)
  stream.close().unwrap()
  assert_true(stream.next(64) is Err(Closed))
  let unmanaged = store
    .open_payload_delivery(
      info.material_generation_cid,
      "jsonl",
      schema,
      ["n"],
      64,
      64,
      16,
      4,
      1024L,
    )
    .unwrap()
  assert_true(unmanaged.chunk_construction is None)
  assert_eq(unmanaged.next(64).unwrap().bytes, b"{\"n\":0}\n")
  unmanaged.close().unwrap()
  let retired = store
    .open_payload_delivery(
      info.material_generation_cid,
      "jsonl",
      schema,
      ["n"],
      64,
      64,
      16,
      4,
      1024L,
    )
    .unwrap()
  retired.chunk_construction = Some(_ => {
    retired.close().unwrap()
    Ok(())
  })
  assert_true(retired.next(64) is Err(Closed))
  assert_eq(retired.funded_chunk_bytes, 0)
  assert_eq(retired.emitted_rows, 0L)
  store.reclaim_payload(info.material_generation_cid).unwrap()
  let empty_writer = store
    .begin_payload(
      native_payload_request(
        authority,
        "delivery-empty-chunks",
        16L,
        row_count=0L,
      ),
    )
    .unwrap()
  empty_writer.append(b"[]").unwrap()
  let empty = empty_writer.seal().unwrap()
  for (format, expected) in [("jsonl", ""), ("json", "[]"), ("csv", "\"n\"\n")] {
    let stream = store
      .open_payload_delivery(
        empty.material_generation_cid,
        format,
        schema,
        ["n"],
        2,
        64,
        16,
        4,
        64L,
      )
      .unwrap()
    stream.chunk_construction = Some(_ => Ok(()))
    let (actual, summary) = native_delivery_all(stream, 64)
    assert_eq(actual, expected)
    assert_eq(summary.rows, 0L)
    assert_eq(summary.bytes, expected.length().to_int64())
  }
  store.reclaim_payload(empty.material_generation_cid).unwrap()
  assert_true(store.close().unwrap())
}

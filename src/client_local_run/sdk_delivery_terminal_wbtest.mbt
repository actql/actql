///|
fn sdk_terminal_prepare(
  fixture : SDKReadFixture,
  encoding : LocalSDKPayloadEncoding,
  at : String,
  rows : Map[String, @host.ClientJournalPhysicalRow],
) -> Result[LocalSDKDeliveryTerminal, LocalSDKDeliveryTerminalIssue[String]] {
  encoding.prepare_terminal_from_store(
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
    (table, key) => Ok(rows.get(table + "|" + key)),
    () => Ok(()),
  )
}

///|
fn sdk_terminal_observe(
  fixture : SDKReadFixture,
  terminal : LocalSDKDeliveryTerminal,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String],
  current : () -> Result[Unit, String],
) -> Result[Unit, LocalSDKDeliveryTerminalIssue[String]] {
  terminal.observe_from_store(
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
fn sdk_terminal_saved_rows(
  rows : Map[String, @host.ClientJournalPhysicalRow],
  terminal : LocalSDKDeliveryTerminal,
) -> Unit {
  for contract in [terminal.receipt, terminal.record] {
    let cid = @publication.publication_contract_identity(contract)
    rows.set("publication_contract|" + cid, {
      key: cid,
      revision: 0L,
      body: @utf8.encode(@publication.publication_contract_json(contract)),
    })
  }
  rows.set("delivery_record_head|" + terminal.head_key, {
    key: terminal.head_key,
    revision: 1L,
    body: @utf8.encode(@publication.publication_contract_json(terminal.record)),
  })
}

///|
// Existing checked publication and actual framer/serializer/sink/issuance.
// Typed Store double only: no SQLite COMMIT, real Wasm, SDK sink or Run finish.
test "SDK terminal proposal requires explicit sink completion and is not saved success" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  assert_eq(encoding.feed(b"[{\"n\":1}]", true), Ok(b"{\"n\":1}\n"))
  assert_true(
    sdk_terminal_prepare(fixture, encoding, "2026-10-13T00:00:06.000Z", rows)
    is Err(Encoding(Sink(DeliverySinkSourceIncomplete))),
  )
  assert_eq(encoding.confirm_chunk(), Ok(8L))
  let terminal = sdk_terminal_prepare(
    fixture, encoding, "2026-10-13T00:00:06.000Z", rows,
  ).unwrap()
  guard @json.parse(@publication.publication_contract_json(terminal.record))
    is Object(body) else {
    fail("Expected original terminal record")
  }
  assert_eq(body.get("confirmed_byte_count"), Some(@json.parse("8")))
  assert_eq(body.get("state"), Some(@json.to_json("succeeded")))
  assert_eq(body.get("sequence"), Some(@json.parse("1")))
  assert_eq(
    body.get("observed_at"),
    Some(@json.to_json("2026-10-13T00:00:06.000Z")),
  )
  assert_eq(
    body.get("delivered_sha256"),
    Some(@json.to_json(sdk_payload_expected_delivery_hash)),
  )
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  let packet = terminal.storage_from_store(read, () => Ok(())).unwrap()
  guard @json.parse(packet) is Array(entries) else {
    fail("Expected terminal CAS array")
  }
  assert_eq(entries.length(), 3)
  assert_true(
    sdk_terminal_observe(fixture, terminal, read, () => Ok(()))
    is Err(UnresolvedOriginal),
  )
  let cached = sdk_terminal_prepare(
    fixture, encoding, "2026-10-13T00:00:07.000Z", rows,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_json(cached.record),
    @publication.publication_contract_json(terminal.record),
  )
}

///|
test "SDK terminal observes actual saved receipt after lost ACK without proposing replay" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  encoding.feed(b"[{\"n\":1}]", true).unwrap() |> ignore
  encoding.confirm_chunk().unwrap() |> ignore
  let terminal = sdk_terminal_prepare(
    fixture, encoding, "2026-10-13T00:00:06.000Z", rows,
  ).unwrap()
  sdk_terminal_saved_rows(rows, terminal)
  let reads = Ref(0)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => {
    reads.val += 1
    Ok(rows.get(table + "|" + key))
  }
  assert_true(
    sdk_terminal_observe(fixture, terminal, read, () => Ok(())) is Ok(_),
  )
  assert_true(reads.val > 0)
  assert_true(
    terminal.storage_from_store(read, () => Ok(())) is Err(UnresolvedOriginal),
  )
  assert_true(
    sdk_terminal_prepare(fixture, encoding, "2026-10-13T00:00:07.000Z", rows)
    is Err(Current(ChangedOriginal)),
  )
}

///|
test "SDK terminal refuses absent head partial contracts and query or current failure" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  encoding.feed(b"[{\"n\":1}]", true).unwrap() |> ignore
  encoding.confirm_chunk().unwrap() |> ignore
  let terminal = sdk_terminal_prepare(
    fixture, encoding, "2026-10-13T00:00:06.000Z", rows,
  ).unwrap()
  assert_true(
    terminal.storage_from_store((_, _) => Err("query-failed"), () => Ok(()))
    is Err(Query("query-failed")),
  )
  let absent : (String, String) -> Result[
    @host.ClientJournalPhysicalRow?,
    String,
  ] = (_, _) => Ok(None)
  assert_true(
    terminal.storage_from_store(absent, () => Ok(())) is Err(MissingOriginal),
  )
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  assert_true(
    terminal.storage_from_store(read, () => Err("revoked"))
    is Err(Query("revoked")),
  )
  sdk_terminal_saved_rows(rows, terminal)
  assert_true(
    sdk_terminal_observe(fixture, terminal, (_, _) => Err("lookup-failed"), () => {
      Ok(())
    })
    is Err(Observation(Observation("lookup-failed"))),
  )
  rows.remove(
    "publication_contract|" +
    @publication.publication_contract_identity(terminal.receipt),
  )
  |> ignore
  assert_true(
    sdk_terminal_observe(fixture, terminal, read, () => Ok(()))
    is Err(Observation(MissingOriginal)),
  )
}

///|
test "SDK terminal rejects changed successor generation and retains original expiry" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  let rows = sdk_payload_codec_rows(fixture)
  encoding.feed(b"[{\"n\":1}]", true).unwrap() |> ignore
  encoding.confirm_chunk().unwrap() |> ignore
  assert_true(
    sdk_terminal_prepare(fixture, encoding, "2026-10-15T00:00:00.000Z", rows)
    is Err(Current(Store(Preparation(Expired)))),
  )
  let terminal = sdk_terminal_prepare(
    fixture, encoding, "2026-10-13T00:00:06.000Z", rows,
  ).unwrap()
  sdk_terminal_saved_rows(rows, terminal)
  rows.set("delivery_record_head|" + terminal.head_key, {
    key: terminal.head_key,
    revision: 2L,
    body: @utf8.encode(@publication.publication_contract_json(terminal.record)),
  })
  assert_true(
    sdk_terminal_observe(
      fixture,
      terminal,
      (table, key) => Ok(rows.get(table + "|" + key)),
      () => Ok(()),
    )
    is Err(ChangedOriginal),
  )
}

///|
fn private_retention_test_wire(
  holdings : String,
  tail? : String = "",
) -> String {
  "{\"version\":\"actql-local-continuation-retention/0.1\",\"prepare_attempt_id\":\"original-run\",\"request_cid\":\"sha256:" +
  "1".repeat(64) +
  "\",\"key_id\":\"sha256:" +
  "2".repeat(64) +
  "\",\"holdings\":" +
  holdings +
  tail +
  "}"
}

///|
fn private_retention_test_entry(
  tail? : String = "",
  state? : String = "held",
) -> String {
  "{\"name\":\"captured_input\",\"semantic_cid\":\"sha256:" +
  "3".repeat(64) +
  "\",\"holding_cid\":\"sha256:" +
  "4".repeat(64) +
  "\",\"key_id\":\"sha256:" +
  "2".repeat(64) +
  "\",\"state\":\"" +
  state +
  "\"" +
  tail +
  "}"
}

///|
fn private_retention_test_check(
  wire : String,
  entries : Int,
  bytes? : Int = 16384,
) -> Result[Unit, ClientPrivateContinuationRetentionIssue] {
  check_client_private_continuation_retention(
    @utf8.encode(wire),
    "original-run",
    bytes,
    entries,
  )
}

///|
test "private retention bounded empty exact bytes and original data" {
  let wire = private_retention_test_wire("[]")
  assert_eq(@utf8.encode(wire).length(), 273)
  assert_true(private_retention_test_check(wire, 0, bytes=273) is Ok(_))
  assert_true(
    private_retention_test_check(wire, 0, bytes=272) is Err(InvalidLedger),
  )
  let entry = private_retention_test_entry(
    tail=",\"cleanup_error\":\"e\\u0301\\r\\nclose pending\"",
  )
  assert_true(
    private_retention_test_check(
      private_retention_test_wire("[" + entry + "]", tail=",\"abandoned\":true"),
      1,
    )
    is Ok(_),
  )
}

///|
test "private retention duplicate keys are explicit private invalid ledger" {
  for tail in [",\"holdings\":[]", ",\"\\u0068oldings\":[]"] {
    assert_true(
      private_retention_test_check(private_retention_test_wire("[]", tail~), 1)
      is Err(InvalidLedger),
    )
  }
  let duplicate = private_retention_test_entry(tail=",\"state\":\"retired\"")
  assert_true(
    private_retention_test_check(
      private_retention_test_wire("[" + duplicate + "]"),
      1,
    )
    is Err(InvalidLedger),
  )
}

///|
test "private retention closed fields NULL and parser trees refuse" {
  for
    wire in [
      private_retention_test_wire("[]", tail=",\"abandoned\":null"),
      private_retention_test_wire("[]", tail=",\"unknown\":true"),
      private_retention_test_wire("[null]"),
      private_retention_test_wire(
        "[" + private_retention_test_entry(tail=",\"cleanup_error\":null") + "]",
      ),
      "[".repeat(8192) + "]".repeat(8192),
      "[" + "0,".repeat(8000) + "0]",
    ] {
    assert_true(private_retention_test_check(wire, 40) is Err(InvalidLedger))
  }
  assert_true(
    check_client_private_continuation_retention(
      b"\xff", "original-run", 16384, 40,
    )
    is Err(InvalidLedger),
  )
}

///|
test "private retention exact forty entries and one short include retired rows" {
  let wire = private_retention_test_wire(
    "[" +
    Array::make(40, private_retention_test_entry(state="retired")).join(",") +
    "]",
  )
  assert_true(private_retention_test_check(wire, 40) is Ok(_))
  assert_true(private_retention_test_check(wire, 39) is Err(EntriesLimit))
}

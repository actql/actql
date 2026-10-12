///|
test "local policy row projection preserves original absent-field legacy bytes" {
  let original = journal_encoding_original()
  let body = client_run_journal_row_body(original).unwrap()
  let (restored, packet) = decode_client_run_journal_row_with_local_policy(body).unwrap()
  assert_eq(packet, None)
  assert_eq(client_run_journal_row_body(restored).unwrap(), body)
  assert_true(decode_client_run_journal_row(body) is Ok(_))
}

///|
test "local policy row retains exact nested packet and legacy reader refuses new role" {
  let original = journal_encoding_original()
  let body = client_run_journal_row_body(
    original,
    local_run_policy_originals=Some(local_run_policy_packet_fixture),
  ).unwrap()
  let (restored, packet) = decode_client_run_journal_row_with_local_policy(body).unwrap()
  assert_eq(packet, Some(local_run_policy_packet_fixture))
  assert_eq(
    client_run_journal_row_body(restored, local_run_policy_originals=packet).unwrap(),
    body,
  )
  assert_true(decode_client_run_journal_row(body) is Err(CustodyLost))
  // Raw row encoding is not nested packet admission. The Native Owner must
  // reject this fixture's intentionally foreign Run before accepting custody.
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  assert_true(
    admit_client_local_run_policy_original(
      @utf8.encode(packet.unwrap()),
      profile,
      local_run_policy_packet_reference(),
      local_run_policy_packet_request(),
      original.definition,
      "sha256:" + "a".repeat(64),
      "sha256:" + "f".repeat(64),
    )
    is Err(_),
  )
}

///|
test "local policy raw row enforces existing bounded storage and closed fields" {
  let record = journal_encoding_original()
  assert_true(
    client_run_journal_row_body(
      record,
      local_run_policy_originals=Some("x".repeat(8193)),
    )
    is Err(CapacityExceeded),
  )
  let body = @utf8.decode(client_run_journal_row_body(record).unwrap()) catch {
    _ => abort("invalid UTF-8 original")
  }
  for
    inserted in [
      "\"local_run_policy_originals\":null,",
      "\"local_run_policy_originals\":false,",
      "\"local_run_policy_originals\":\"x\",\"local_run_policy_originals\":\"x\",",
      "\"local_run_policy_originals\":\"" + "x".repeat(8193) + "\",",
      "\"local_run_policy_originals\":\"x\",\"extra\":true,",
    ] {
    assert_true(
      decode_client_run_journal_row_with_local_policy(
        @utf8.encode(body.replace(old="{", new="{" + inserted)),
      )
      is Err(CustodyLost),
    )
  }
}

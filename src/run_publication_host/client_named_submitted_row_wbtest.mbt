///|
test "named physical row preserves exact independent original fields and tag bytes" {
  let row = {
    binding: named_original_binding(),
    authenticator: Bytes::make(32, 0),
  }
  let body = client_submitted_name_row_body(row).unwrap()
  assert_true(
    @utf8.decode(body).unwrap().has_suffix("\",\"" + "0".repeat(64) + "\"]"),
  )
  let decoded = decode_client_submitted_name_row(body).unwrap()
  assert_eq(decoded.binding, row.binding)
  assert_eq(decoded.authenticator, row.authenticator)
  assert_eq(client_submitted_name_row_body(decoded).unwrap(), body)
  assert_eq(
    client_submitted_name_index_input(named_original_key()).unwrap(),
    "[\"workspace\",\"actor\",\"original-name\"]",
  )
}

///|
test "named index does not partition occupied names by scope or intent" {
  let key = named_original_key()
  let original = named_original_binding()
  let different = prepare_client_submitted_name_binding(
    key,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "sha256:" + "e".repeat(64),
  ).unwrap()
  assert_true(
    client_submitted_name_authentication_input(original, 8192).unwrap() !=
    client_submitted_name_authentication_input(different, 8192).unwrap(),
  )
  assert_eq(
    client_submitted_name_index_input(
      client_submitted_name_binding_fields(original).0,
    ),
    client_submitted_name_index_input(
      client_submitted_name_binding_fields(different).0,
    ),
  )
}

///|
test "named physical row refuses noncanonical syntax and malformed original authentication fields" {
  let row = {
    binding: named_original_binding(),
    authenticator: Bytes::make(32, 0),
  }
  let body = client_submitted_name_row_body(row).unwrap()
  assert_true(decode_client_submitted_name_row(b" " + body) is Err(CustodyLost))
  assert_true(decode_client_submitted_name_row(b"[]") is Err(CustodyLost))
  assert_true(
    decode_client_submitted_name_row(b"[\"[]\",\"00\"]") is Err(CustodyLost),
  )
  assert_true(decode_client_submitted_name_row(b"\xff") is Err(CustodyLost))
  assert_true(
    client_submitted_name_row_body({
      binding: row.binding,
      authenticator: b"short",
    })
    is Err(CustodyLost),
  )
}

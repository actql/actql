///|
test "publication Store binding preserves existing Native bytes and full UInt64 fields" {
  assert_eq(
    client_publication_store_binding_body(
      "local",
      "sha256:" + "a".repeat(64),
      7UL,
      18446744073709551615UL,
    ),
    Ok(
      "[\"local\",\"sha256:" +
      "a".repeat(64) +
      "\",\"7\",\"18446744073709551615\"]",
    ),
  )
  assert_eq(
    client_publication_store_binding_body(
      "e\u{301}\r\n/~", "raw\"target", 0UL, 9UL,
    ),
    Ok("[\"e\u{301}\\r\\n/~\",\"raw\\\"target\",\"0\",\"9\"]"),
  )
}

///|
test "publication Store binding retains existing finite encoding limit" {
  assert_eq(
    client_publication_store_binding_body("x".repeat(4096), "target", 7UL, 9UL),
    Err(Encoding),
  )
}

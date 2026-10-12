///|
test "Native original record delegates without changing body or failure classification" {
  let fields = [
    ("device", "18446744073709551615"),
    ("inode", "2"),
    (
      "intent_cid", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    ("size", "17"),
    ("version", "actql-native-local-configuration-custody/0.1"),
  ]
  let original = b"{\"device\":\"18446744073709551615\",\"inode\":\"2\",\"intent_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"size\":\"17\",\"version\":\"actql-native-local-configuration-custody/0.1\"}"
  assert_eq(local_adoption_record(fields).unwrap(), original)
  assert_eq(
    local_adoption_fields(original, fields.map(field => field.0)).unwrap(),
    fields.map(field => field.1),
  )
  assert_true(local_adoption_record([("a", "x".repeat(8193))]) is Err(Encoding))
  assert_true(local_adoption_fields(b"{\"a\":null}", ["a"]) is Err(CustodyLost))
  assert_true(
    local_adoption_fields(b"{\"a\": \"x\"}", ["a"]) is Err(CustodyLost),
  )
}

///|
fn base() -> String {
  (
    #|{"output_carrier":"relation","schema":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"source_ref":"source:local/s/rows","version":"actql-local-input-schema/0.1"}
  )
}

///|
fn caps() -> Limits {
  { max_bytes: 10000, max_nodes: 1000, max_depth: 100, }
}

///|
test "snapshot integrity is bounded and does not invent materialization" {
  let bytes = @utf8.encode(base())
  let expected = "sha256:9f0114feb3b5e8e946c3efc5b89ebe6a44559f13b7ec30809a0e42d173916bec"
  let value = read(bytes, expected, caps()).unwrap()
  assert_eq(cid(value), expected)
  assert_true(materialization(value) is None)
  assert_eq(@schema.field_count(schema(value)), 0)
  assert_eq(
    @reference.stringify(source_reference(value)),
    "source:local/s/rows",
  )
  let (size, nodes) = usage(value)
  assert_eq(size, bytes.length())
  let exact : Limits = { max_bytes: size, max_nodes: nodes, max_depth: 3, }
  assert_true(read(bytes, expected, exact) is Ok(_))
  assert_true(
    read(bytes, expected, { ..exact, max_bytes: size - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    read(bytes, expected, { ..exact, max_nodes: nodes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    read(bytes, expected, { ..exact, max_depth: 2, }) is Err(BudgetExceeded),
  )
  assert_true(
    read(bytes, expected, { ..exact, max_bytes: -1, }) is Err(InvalidLimits),
  )
  assert_true(
    read(bytes, "sha256:" + "0".repeat(64), caps()) is Err(IdentityMismatch),
  )
  assert_true(read(bytes, "bad", caps()) is Err(IdentityMismatch))
}

///|
test "rehashing noncanonical wire bytes does not admit repair" {
  for body in [" " + base(), base() + "\n", "\u{FEFF}" + base()] {
    let bytes = @utf8.encode(body)
    assert_true(
      read(bytes, "sha256:" + @sha.hex(bytes), caps()) is Err(NonCanonicalBytes),
    )
  }
  let reordered = @utf8.encode(
    (
      #|{"version":"actql-local-input-schema/0.1","output_carrier":"relation","schema":{"type":"object","nullable":false,"additional_properties":false,"fields":{}},"source_ref":"source:local/s/rows"}
    ),
  )
  assert_true(
    read(reordered, "sha256:" + @sha.hex(reordered), caps())
    is Err(NonCanonicalBytes),
  )
}

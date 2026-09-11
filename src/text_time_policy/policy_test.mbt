///|
fn fixture() -> String {
  "{\"max_input_codepoints\":1,\"max_input_utf8_bytes\":1,\"max_output_bytes\":1,\"max_pattern_bytes\":1,\"max_replacements\":1,\"version\":\"actql-text-time-host-policy/0.1\"}"
}

///|
fn caps() -> Limits {
  { max_bytes: 4096, max_nodes: 100, max_depth: 4, }
}

///|
fn read(text : String) -> Result[Policy, Issue] {
  let bytes = @utf8.encode(text)
  admit(bytes, "sha256:" + @sha.hex(bytes), caps())
}

///|
test "text-time policy admits independent canonical identity and emits exact wire" {
  let expected = "sha256:5fac567c3a4cc4da2a9494a9fc7b0d2304157c3641100f73e752426e62c8d8c1"
  let policy = admit(@utf8.encode(fixture()), expected, caps()).unwrap()
  assert_eq(cid(policy), expected)
  for
    name in [
      "max_input_codepoints", "max_input_utf8_bytes", "max_output_bytes", "max_pattern_bytes",
      "max_replacements",
    ] {
    let field = ceiling(policy, name).unwrap()
    assert_true(physical_equal(ceiling_policy(field), policy))
    assert_eq(ceiling_field(field), name)
    assert_eq(ceiling_value(field), 1L)
  }
  assert_true(ceiling(policy, "max_rows") is None)
  let writer = @encode.writer(4096, 100, 4)
  emit(policy, writer)
  assert_eq(@encode.finish(writer), fixture())
  let maximum = fixture().replace(
    old="\"max_replacements\":1",
    new="\"max_replacements\":9007199254740991",
  )
  assert_eq(
    ceiling_value(ceiling(read(maximum).unwrap(), "max_replacements").unwrap()),
    9007199254740991L,
  )
}

///|
test "closed positive safe-integer ceilings reject omissions coercion and extras" {
  for
    name in [
      "max_input_codepoints", "max_input_utf8_bytes", "max_output_bytes", "max_pattern_bytes",
      "max_replacements",
    ] {
    for bad in ["0", "-1", "1.5", "9007199254740992", "null", "true", "\"1\""] {
      assert_true(
        read(
          fixture().replace(
            old="\"" + name + "\":1",
            new="\"" + name + "\":" + bad,
          ),
        )
        is Err(_),
      )
    }
    assert_true(
      read(fixture().replace(old="\"" + name + "\":1,", new=""))
      is Err(InvalidBody),
    )
  }
  assert_true(
    read(fixture().replace(old="\"version\"", new="\"extra\":1,\"version\""))
    is Err(InvalidBody),
  )
  assert_true(
    read(fixture().replace(old="/0.1", new="/9.9")) is Err(UnsupportedVersion),
  )
}

///|
test "noncanonical encodings are refused rather than repaired" {
  for
    text in [
      " " + fixture(),
      fixture() + "\n",
      fixture().replace(
        old="\"max_output_bytes\":1",
        new="\"max_output_bytes\":1.0",
      ),
    ] {
    assert_true(read(text) is Err(NoncanonicalArtifact))
  }
  assert_true(
    read(
      fixture().replace(
        old="\"max_output_bytes\":1",
        new="\"max_output_bytes\":1,\"max_output_bytes\":1",
      ),
    )
    is Err(InvalidJson),
  )
  assert_true(
    admit(@utf8.encode(fixture()), "sha256:" + "0".repeat(64), caps())
    is Err(IdentityMismatch),
  )
}

///|
test "policy budgets include exact canonical body and shallow scalar nodes" {
  let bytes = @utf8.encode(fixture())
  let expected = "sha256:" + @sha.hex(bytes)
  let exact : Limits = {
    max_bytes: bytes.length(),
    max_nodes: 7,
    max_depth: 1,
  }
  assert_true(admit(bytes, expected, exact) is Ok(_))
  for
    limits in [
      { ..exact, max_bytes: bytes.length() - 1, },
      { ..exact, max_nodes: 6, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(admit(bytes, expected, limits) is Err(BudgetExceeded))
  }
  assert_true(
    admit(bytes, expected, { ..exact, max_nodes: -1, }) is Err(InvalidLimits),
  )
}

///|
test "missing unknown and duplicate precedence agrees across key-check branches" {
  let cases : Array[
    (Array[String], Array[String], Result[Unit, ObjectKeyIssue]),
  ] = [
    ([], ["b", "a"], Err(MissingKey("b"))),
    ([], ["a", "b"], Err(MissingKey("a"))),
    (["x", "x"], ["a"], Err(MissingKey("a"))),
    (["x", "a", "a"], [], Err(UnknownKey("x"))),
    (["a", "a", "x"], [], Err(DuplicateKey("a"))),
    (["a", "x", "a"], [], Err(UnknownKey("x"))),
    (["x", "x"], [], Err(UnknownKey("x"))),
    (["b", "a"], ["a", "b"], Ok(())),
    ([], [], Ok(())),
  ]
  for (keys, required, expected) in cases {
    for wide in [false, true] {
      let allowed = ["a", "b"]
      if wide {
        for i in 0..<9 {
          allowed.push("unused-" + i.to_string())
        }
      }
      assert_eq(check_object_keys(keys, required, allowed), expected)
    }
  }
  assert_eq(
    check_object_keys(["a", "a", "a", "a", "a", "a", "a", "a", "a"], [], ["a"]),
    Err(DuplicateKey("a")),
  )
  assert_eq(
    check_object_keys(["a"], ["a", "b", "c", "d", "e", "f", "g", "h", "i"], [
      "a",
    ]),
    Err(MissingKey("b")),
  )
}

///|
test "unknown positions are detached and preserve every repeated occurrence" {
  let keys = ["a", "x", "x", "b", "y"]
  let required = ["a"]
  for wide in [false, true] {
    let allowed = ["a", "b"]
    if wide {
      for i in 0..<9 {
        allowed.push("unused-" + i.to_string())
      }
    }
    let allowed_before = allowed.copy()
    let positions = unknown_key_indices(keys, allowed)
    assert_eq(positions, [1, 2, 4])
    assert_eq(check_object_keys(keys, required, allowed), Err(UnknownKey("x")))
    positions[0] = 99
    positions.clear()
    assert_eq(unknown_key_indices(keys, allowed), [1, 2, 4])
    assert_eq(keys, ["a", "x", "x", "b", "y"])
    assert_eq(required, ["a"])
    assert_eq(allowed, allowed_before)
  }
}

///|
test "key checks are exact and do not normalize or validate Unicode" {
  let malformed = String::from_array([(0xd800).unsafe_to_char()])
  let names = ["é", "e\u0301", "x\r", "x\n", "A", "a", "ﬁ", "fi", malformed]
  assert_eq(check_object_keys(names, names, names), Ok(()))
  assert_eq(unknown_key_indices(names, names), [])
  let state = key_admission()
  for name in names {
    assert_true(admit_key(state, name))
    assert_false(admit_key(state, name))
  }
  assert_true(admit_key(state, "after-rejection"))
  let separate = key_admission()
  assert_true(admit_key(separate, "after-rejection"))
}

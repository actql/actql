///|
test "shared topology retains source order and does not canonicalize names" {
  let allowed = ["a", "b", "c", "d", "e", "f", "g", "é", "e\u0301"]
  let keys = ["a", "rogue", "a", "other", "é", "e\u0301"]
  assert_eq(unknown_key_indices(keys, allowed), [1, 3])
  assert_eq(
    check_object_keys(keys, ["missing"], allowed),
    Err(MissingKey("missing")),
  )
  assert_eq(check_object_keys(keys, [], allowed), Err(UnknownKey("rogue")))
  assert_eq(check_object_keys(["é", "e\u0301"], [], allowed), Ok(()))
  assert_eq(check_object_keys(["a", "a"], [], allowed), Err(DuplicateKey("a")))
  assert_eq(keys, ["a", "rogue", "a", "other", "é", "e\u0301"])
}

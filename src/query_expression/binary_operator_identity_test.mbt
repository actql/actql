///|
test "binary operator reuse keeps polarity and installed identities" {
  assert_true(same_binary_operator("!=", "<>"))
  assert_true(same_binary_operator("<>", "!="))
  for op in ["+", "-", "*", "/", "%", "=", "<", "<=", ">", ">=", "AND", "OR", "||", "LIKE", "NOT LIKE"] {
    assert_true(same_binary_operator(op, op))
  }
  for (left, right) in [
    ("!=", "="), ("<", "<="), ("AND", "OR"),
    ("+", "-"), ("LIKE", "NOT LIKE"), ("unknown", "unknown"),
  ] {
    assert_false(same_binary_operator(left, right))
  }
  assert_eq(emit("x != 1"), emit("x <> 1"))
  assert_eq(emit("x NOT LIKE 'a'"), "{\"not\":{\"like\":[{\"field\":\"x\"},{\"literal\":\"a\"}]}}")
}

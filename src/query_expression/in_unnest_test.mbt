///|
test "IN UNNEST retains an array operand rather than a singleton list or expansion" {
  assert_eq(
    emit("amount IN UNNEST((@xs))"),
    "{\"in\":[{\"field\":\"amount\"},{\"$param\":\"xs\"}]}",
  )
  assert_eq(
    emit("amount NOT IN UNNEST((@xs))"),
    "{\"not_in\":[{\"field\":\"amount\"},{\"$param\":\"xs\"}]}",
  )
}

///|
test "general array expression membership retains the common admission boundary" {
  for text in ["amount IN UNNEST(xs)", "amount IN UNNEST(IF(TRUE, @xs, @ys))"] {
    let result = lower(
      fixture(text),
      path => if path.length() == 1 { Some(path[0].value) } else { None },
      limits(),
    )
    // The existing common syntax rejects nonliteral, nonparameter RHS nodes.
    // Keep this gap visible; do not expand expressions into scalar IN lists.
    assert_true(
      result
      is Err(
        { issue: Admission({ kind: @expression.InvalidArguments, .. }), .. }
      ),
    )
  }
}

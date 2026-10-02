///|
test "shared count guards use the existing literal rule with exact work admission" {
  let at = cursor("2")
  let exact : @relation_typing.Limits = {
    max_work: 1,
    max_text_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
    max_tokens: 0,
  }
  let checked = check_count_value(at, 1L, None, exact).unwrap()
  assert_eq(count_value(checked), Literal(2L))
  assert_true(physical_equal(count_value_source(checked), at))
  assert_true(count_value_parameters(checked) is None)
  assert_eq(count_value_usage(checked), (1, 0))
  assert_eq(count_value_pending_count(checked), 0)
  assert_true(count_value_pending_at(checked, 0) is None)
  assert_true(
    check_count_value(at, 1L, None, { ..exact, max_work: 0, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(check_count_value(cursor("0"), 0L, None, exact) is Ok(_))
  assert_true(
    check_count_value(cursor("0"), 1L, None, exact)
    is Err({ kind: InvalidCount, .. }),
  )
  assert_true(
    check_count_value(at, -1L, None, exact) is Err({ kind: InvalidLimits, .. }),
  )
  assert_true(
    check_count_value(at, 9007199254740992L, None, exact)
    is Err({ kind: InvalidLimits, .. }),
  )
  for text in ["-1", "1.5", "9007199254740992", "null", "\"2\""] {
    assert_true(
      check_count_value(cursor(text), 1L, None, { ..exact, max_work: 10, })
      is Err({ kind: InvalidCount | InvalidBody, .. }),
    )
  }
}

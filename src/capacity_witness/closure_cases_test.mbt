///|
test "canonical wire graph resolves forward and repeated operands with exact budgets" {
  let witnesses = graph_fixture()
  let limits : ClosureLimits = {
    max_witnesses: 7,
    max_references: graph_references,
  }
  let claims = check_arithmetic_claims(witnesses, limits).unwrap()
  assert_eq(claim_count(claims), 7)
  assert_eq(claim_reference_count(claims), graph_references)
  for i, expected in [2L, 5L, 12L, 4L, 2L, 8L, 2L] {
    assert_eq(@arithmetic.value_at(claim_arithmetic(claims), i), Some(expected))
    assert_eq(claim_index(claims, cid(witnesses[i])), Some(i))
    assert_eq(cid(claim_at(claims, i).unwrap()), cid(witnesses[i]))
  }
  assert_true(
    check_arithmetic_claims(witnesses, { ..limits, max_witnesses: 6, })
    is Err(ClosureBudgetExceeded),
  )
  assert_true(
    check_arithmetic_claims(witnesses, {
      ..limits,
      max_references: graph_references - 1,
    })
    is Err(ClosureBudgetExceeded),
  )
  assert_true(
    check_arithmetic_claims([witnesses[0]], limits)
    is Err(InvalidArithmetic(MissingReference(_, _))),
  )
  assert_true(
    check_arithmetic_claims([witnesses[6], witnesses[6]], limits)
    is Err(InvalidArithmetic(DuplicateIdentity(1))),
  )
  witnesses.clear()
  assert_eq(claim_count(claims), 7)
  assert_eq(@arithmetic.value_at(claim_arithmetic(claims), 0), Some(2L))
  assert_true(claim_at(claims, -1) is None)
  assert_true(claim_at(claims, 7) is None)
  assert_eq(claim_index(claims, "invalid"), None)
  assert_true(
    check_arithmetic_claims([], { max_witnesses: 0, max_references: -1, })
    is Err(InvalidClosureLimits),
  )
  assert_eq(
    claim_count(
      check_arithmetic_claims([], { max_witnesses: 0, max_references: 0, }).unwrap(),
    ),
    0,
  )
}

///|
test "self CIDs do not hide unused inconsistent arithmetic or enforced ceilings" {
  let variants = bad_graph_fixtures()
  let graph = graph_fixture()
  let limits : ClosureLimits = { max_witnesses: 10, max_references: 100, }
  for i, bad in variants {
    let supplied = graph.copy()
    supplied.push(bad)
    let result = check_arithmetic_claims(supplied, limits)
    match i {
      0 =>
        assert_true(
          result is Err(InvalidArithmetic(ArithmeticFailure(ValueMismatch(7)))),
        )
      1 =>
        assert_true(
          result
          is Err(InvalidArithmetic(ArithmeticFailure(UnitMismatch(7, 6)))),
        )
      2 =>
        assert_true(
          result is Err(InvalidArithmetic(ArithmeticFailure(Overflow(7)))),
        )
      _ => assert_true(result is Err(UnresolvedEnforcement(7, _)))
    }
  }
}

///|
test "issuer serial reservation preserves independent counters and terminal exhaustion" {
  let first : IssuerCounter = { next: 0, }
  let second : IssuerCounter = { next: 0, }
  assert_true(reserve_issuer_number(first) is Some(0))
  assert_true(reserve_issuer_number(first) is Some(1))
  assert_true(reserve_issuer_number(second) is Some(0))
  let last : IssuerCounter = { next: 2147483646, }
  assert_true(reserve_issuer_number(last) is Some(2147483646))
  assert_true(reserve_issuer_number(last) is None)
  assert_true(reserve_issuer_number(last) is None)
  assert_eq(last.next, 2147483647)
  assert_true(reserve_issuer_number(first) is Some(2))
}

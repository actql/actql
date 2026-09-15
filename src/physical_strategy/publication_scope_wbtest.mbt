///|
test "publication scope can be claimed once only while its callback is active" {
  let scope : PublicationScope = { active: true, claimed: false, }
  assert_true(claim_publication_scope(scope))
  assert_false(claim_publication_scope(scope))
  close_publication_scope(scope)
  assert_false(claim_publication_scope(scope))
  close_publication_scope(scope)
  assert_false(claim_publication_scope(scope))
}

///|
test "unclaimed publication scope expires when its callback returns" {
  let scope : PublicationScope = { active: true, claimed: false, }
  close_publication_scope(scope)
  assert_false(claim_publication_scope(scope))
  assert_false(scope.claimed)
}

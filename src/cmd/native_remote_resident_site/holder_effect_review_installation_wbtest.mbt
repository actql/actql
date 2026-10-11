///|
test "Review installation requires two independent operator roots" {
  assert_eq(holder_effect_review_roots(None, None), None)
  assert_eq(holder_effect_review_roots(Some("review"), None), None)
  assert_eq(holder_effect_review_roots(None, Some("catalog")), None)
  assert_eq(holder_effect_review_roots(Some(""), Some("catalog")), None)
  assert_eq(holder_effect_review_roots(Some("review"), Some("")), None)
  assert_eq(
    holder_effect_review_roots(Some("review"), Some("catalog")),
    Some(("review", "catalog")),
  )
}

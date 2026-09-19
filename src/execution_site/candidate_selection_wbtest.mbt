///|
test "Site candidate choice is independent of registration order" {
  assert_eq(select_site_candidate_index([5L, 5L], ["z-site", "a-site"]), 1)
  assert_eq(select_site_candidate_index([5L, 5L], ["a-site", "z-site"]), 0)
  assert_eq(select_site_candidate_index([2L, 1L], ["a-site", "z-site"]), 1)
  assert_eq(select_site_candidate_index([5L, 5L], ["duckdb", "local"]), 0)
}

///|
test "Site candidate choice rejects malformed and duplicate facts" {
  assert_eq(select_site_candidate_index([], []), -1)
  assert_eq(select_site_candidate_index([1L], []), -2)
  assert_eq(select_site_candidate_index([-1L], ["site"]), -2)
  assert_eq(select_site_candidate_index([1L], [""]), -2)
  assert_eq(select_site_candidate_index([1L, 2L], ["site", "site"]), -3)
}

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

///|
test "Site candidate plan owns applicability and distinct Transfer cost" {
  let accepted = plan_site_candidate(
    Some(10L),
    Some(2L),
    true,
    true,
    true,
    Some(3L),
    [false, true, true],
    [false, false, true],
    [false, false, false],
    [false, true, true],
    [0L, 8L, 8L],
    [0L, 16L, 16L],
    [0L, 4L, 4L],
  )
  assert_eq(accepted, SiteCandidateAccepted(15L))
  assert_eq(
    plan_site_candidate(
      Some(10L),
      Some(2L),
      true,
      false,
      true,
      Some(3L),
      [true],
      [false],
      [false],
      [true],
      [8L],
      [16L],
      [4L],
    ),
    SiteCandidateTransferUnsupported,
  )
  assert_eq(
    plan_site_candidate(
      Some(10L),
      Some(2L),
      true,
      true,
      true,
      Some(3L),
      [true],
      [false],
      [true],
      [true],
      [8L],
      [16L],
      [4L],
    ),
    SiteCandidateSourceRevoked,
  )
  assert_eq(
    plan_site_candidate(
      Some(10L),
      Some(2L),
      false,
      true,
      true,
      Some(3L),
      [],
      [],
      [],
      [],
      [],
      [],
      [],
    ),
    SiteCandidateCapacityExceeded,
  )
}

///|
test "Site candidate plan rejects malformed facts and duration overflow" {
  assert_eq(
    plan_site_candidate(
      Some(9223372036854775807L),
      Some(1L),
      true,
      true,
      true,
      Some(1L),
      [],
      [],
      [],
      [],
      [],
      [],
      [],
    ),
    SiteCandidateInvalid,
  )
  assert_eq(
    plan_site_candidate(
      Some(1L),
      Some(1L),
      true,
      true,
      true,
      Some(1L),
      [false],
      [false],
      [false],
      [true],
      [0L],
      [0L],
      [0L],
    ),
    SiteCandidateInvalid,
  )
}

///|
test "managed candidate fallback is owned by portable Site control" {
  assert_eq(
    classify_managed_candidate_fallback(0, [1, 3]),
    ManagedCandidateLegacyAllowed,
  )
  assert_eq(
    classify_managed_candidate_fallback(1, [3, 6]),
    ManagedCandidateEstimateUnavailable,
  )
  assert_eq(
    classify_managed_candidate_fallback(2, [8, 5]),
    ManagedCandidateTransferUnavailable,
  )
  assert_eq(
    classify_managed_candidate_fallback(1, [2, 8]),
    ManagedCandidateNoCompatibleStrategy,
  )
  assert_eq(
    classify_managed_candidate_fallback(1, [0]),
    ManagedCandidateFallbackInvalid,
  )
}

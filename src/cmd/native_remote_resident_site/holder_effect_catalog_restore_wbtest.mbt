///|
/// Compile-only projection boundaries; the query Owner must supply the actual
/// authenticated use. These values are not service or persistence evidence.
test "restored Catalog adoption requires confirmed successful original use" {
  let use_cid = "sha256:" + "a".repeat(64)
  for
    (outcome, status) in [
      ("claimed", None),
      ("unknown", Some(200)),
      ("failed", Some(500)),
      ("succeeded", None),
      ("succeeded", Some(500)),
    ] {
    assert_false(holder_catalog_use_succeeded({ use_cid, outcome, status, }))
  }
  assert_true(
    holder_catalog_use_succeeded({
      use_cid,
      outcome: "succeeded",
      status: Some(200),
    }),
  )
}

///|
/// Compile-only error classification, not a physical journal observation.
test "Catalog first claim requires exact original checkpoint absence" {
  assert_true(
    holder_catalog_checkpoint_missing(@journal.Physical(@sqlite.NotFound)),
  )
  for
    issue in [
      @journal.Closed,
      @journal.MissingDispatch,
      @journal.StaleSiteBinding,
      @journal.StateCollision,
      @journal.Physical(@sqlite.Collision),
    ] {
    assert_false(holder_catalog_checkpoint_missing(issue))
  }
}

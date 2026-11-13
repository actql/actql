///|
test "Run decode quotes outer rows separately from bounded cold identities" {
  let small = journal_run_decode_working(@host.RunJournalParse(65536)).unwrap()
  let large = journal_run_decode_working(@host.RunJournalParse(1900000)).unwrap()
  let canonical = journal_run_decode_working(
    @host.RunJournalCanonical(1900000, 3800000L, 14, 1),
  ).unwrap()
  assert_true(large.0 > small.0)
  assert_true(large.1 > small.1)
  assert_true(large.2 >= small.2)
  assert_true(canonical.1 > large.1)
  assert_true(canonical.1 > canonical.0)
  assert_true(canonical.2 >= large.2)
  let canonical_other_shape = journal_run_decode_working(
    @host.RunJournalCanonical(1900000, 3800000L, 32, 4),
  ).unwrap()
  // The cold identity refusal profile cannot shrink with outer measured nodes.
  assert_eq(canonical, canonical_other_shape)
  let submitted = journal_submitted_decode_working(
    @host.SubmittedJournalParse(1900000),
  ).unwrap()
  // No full65536-node Submitted intent parser is charged against the large row.
  assert_true(large.1 < submitted.1)
}

///|
test "Run decode construction refuses impossible measured geometry" {
  for
    stage in [
      @host.RunJournalParse(0),
      @host.RunJournalParse(2147483519),
      @host.RunJournalCanonical(1024, 2049L, 12, 1),
      @host.RunJournalCanonical(1024, -1L, 12, 1),
      @host.RunJournalCanonical(1024, 1024L, 33, 1),
      @host.RunJournalCanonical(1024, 1024L, 12, 5),
      @host.RunJournalCanonical(1024, 1024L, 0, 1),
    ] {
    assert_true(journal_run_decode_working(stage) is None)
  }
  assert_true(journal_run_request_construction() is Some(_))
  assert_true(journal_run_definition_construction() is Some(_))
}

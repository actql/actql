///|
test "observed submitted codec keeps finite full overlap and exact Native constructor geometry" {
  let bytes = 1300000
  let parse = journal_submitted_decode_working(
    @host.SubmittedJournalParse(bytes),
  ).unwrap()
  let canonical = journal_submitted_decode_working(
    @host.SubmittedJournalCanonical(bytes, 8, 2),
  ).unwrap()
  assert_eq(parse.0, canonical.0)
  assert_true(parse.0 > 5L * bytes.to_int64())
  assert_true(parse.0 < 7L * 1048576L)
  assert_true(parse.1 > canonical.1)
  assert_true(parse.1 < 96L * 1048576L)
  assert_true(canonical.1 > canonical.0)
  assert_true(parse.2 >= canonical.2)
  assert_true(
    journal_submitted_decode_working(@host.SubmittedJournalParse(0)) is None,
  )
  assert_true(
    journal_submitted_decode_working(
      @host.SubmittedJournalCanonical(bytes, 65537, 2),
    )
    is None,
  )
  assert_true(
    journal_submitted_decode_working(
      @host.SubmittedJournalCanonical(bytes, 8, 65),
    )
    is None,
  )
}

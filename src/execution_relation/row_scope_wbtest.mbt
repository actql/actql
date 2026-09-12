///|
test "snapshot map retains expression roots and enforces shared logical value ceilings" {
  let owner = row_owner(",{\"derive\":{\"x\":\"if(true, a + 1, 1 / 0)\"}}")
  let b = ordered_row_budget(10000L, 10000L)
  let output = run_ordered_rows(owner, row_capture(owner), b).unwrap()
  assert_eq(output.rows.length(), 2)
  assert_eq(b.live, 0L)
  assert_false(b.failed)
  let large = row_owner(
    ",{\"derive\":{\"unused\":{\"literal\":\"abcdefghijklmnopqrstuvwxyz\"}}}",
  )
  let limit = ordered_row_budget(10000L, 10000L, bytes=13L)
  assert_true(
    run_ordered_rows(large, row_capture(large), limit)
    is Err(Evaluation(0, 0, _)),
  )
  assert_true(limit.failed)
  assert_eq(limit.live, 0L)
}

///|
test "filter enforces demanded operand ceilings even when no row is published" {
  let owner = row_owner(
    ",{\"filter\":{\"eq\":[{\"literal\":\"abcdefghijklmnopqrstuvwxyz\"},{\"literal\":\"different\"}]}}",
  )
  let b = ordered_row_budget(10000L, 10000L, bytes=13L)
  assert_true(
    run_ordered_rows(owner, row_capture(owner), b) is Err(Evaluation(0, 0, _)),
  )
  assert_eq(b.live, 0L)
  assert_true(b.failed)
  let reject = row_owner(",{\"filter\":{\"literal\":false}}")
  let success = ordered_row_budget(10000L, 10000L)
  assert_eq(
    run_ordered_rows(reject, row_capture(reject), success).unwrap().rows.length(),
    0,
  )
  assert_eq(success.live, 0L)
  assert_false(success.failed)
}

///|
test "lookup estimate arithmetic distinguishes genuine zero from overflow" {
  let zero = lookup_counts(0L, Some(2.0), 3L, 2L, 4096L, 3L).unwrap()
  assert_eq(zero.input_rows, 0L)
  assert_eq(zero.requests, 0L)
  assert_eq(zero.response_rows, 0L)
  assert_eq(zero.decoded_response_bytes, 0L)
  assert_true(lookup_counts(9007199254740991L, None, 2L, 1L, 1L, 1L) is None)
  assert_true(lookup_counts(3L, None, 1L, 9007199254740991L, 1L, 1L) is None)
  assert_true(lookup_counts(3L, None, 1L, 1L, 9007199254740991L, 1L) is None)
  let known = lookup_counts(3L, Some(2.0), 3L, 2L, 4096L, 3L).unwrap()
  assert_eq(known.input_rows, 3L)
  assert_eq(known.batches, 2L)
  assert_eq(known.decoded_response_bytes, 24576L)
}

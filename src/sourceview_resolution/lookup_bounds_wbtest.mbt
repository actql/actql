///|
test "lookup counts separate logical rows pages attempts and decoded bytes" {
  for rows in 1L..<40L {
    for cap in 1L..<12L {
      let result = lookup_counts(rows, Some(cap.to_double()), 3, 2, 4096, 5).unwrap()
      let keys = if cap < rows { cap } else { rows }
      // Small independent repeated-subtraction oracle for ceil division.
      let mut left = rows
      let mut batches = 0L
      while left > 0 {
        left -= keys
        batches += 1
      }
      assert_eq(result.batches, batches)
      assert_eq(result.keys_per_batch, keys)
      assert_eq(result.distinct_keys, rows)
      assert_eq(result.response_rows, rows * 2)
      assert_eq(result.requests, batches * 3)
      assert_eq(result.network_attempts, batches * 15)
      assert_eq(result.decoded_response_bytes, batches * 12288)
    }
  }
  assert_eq(lookup_counts(3, None, 3, 2, 4096, 5).unwrap().batches, 3)
  assert_eq(lookup_counts(3, Some(1.0e100), 3, 2, 4096, 5).unwrap().batches, 1)
  let ceiling = 9007199254740991L
  assert_eq(
    lookup_counts(ceiling, Some(1.0e100), 1, 1, 1, 1).unwrap().response_rows,
    ceiling,
  )
  for
    (pages, per_key, bytes, attempts) in [
      (2L, 1L, 1L, 1L),
      (1L, 2L, 1L, 1L),
      (1L, 1L, 2L, 1L),
      (1L, 1L, 1L, 2L),
    ] {
    assert_true(
      lookup_counts(ceiling, None, pages, per_key, bytes, attempts) is None,
    )
  }
}

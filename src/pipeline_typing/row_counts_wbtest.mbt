///|
test "diagnostic cardinality bounds cover every possible extent and binding" {
  for upper in 0..<10 {
    for threshold in 0..<12 {
      for exact in [false, true] {
        let estimate = extent_violation(
          Some(count(upper.to_int64(), exact)),
          Some(threshold.to_int64()),
        )
        for actual in 0..<(upper + 1) {
          if exact && actual != upper {
            continue
          }
          let emitted = if actual > threshold { 1L } else { 0L }
          assert_true(emitted <= estimate.upper)
          if estimate.exact {
            assert_eq(emitted, estimate.upper)
          }
        }
        let bound = extent_violation(Some(count(upper.to_int64(), exact)), None)
        assert_eq(bound.upper, if upper == 0 { 0L } else { 1L })
        assert_eq(bound.exact, upper == 0)
      }
    }
  }
  assert_eq(count_violation(None, None), count(0L, true))
  assert_eq(extent_violation(None, Some(9007199254740991L)), count(1L, false))
  assert_eq(
    extent_violation(
      Some(count(9007199254740991L, true)),
      Some(9007199254740990L),
    ),
    count(1L, true),
  )
}

///|
test "row count arithmetic distinguishes exact counts from upper bounds" {
  let source = @decode.admit(
    @source.parse_json("null", {
      max_input_bytes: 4,
      max_nodes: 1,
      max_depth: 0,
    }).unwrap(),
    {
      max_nodes: 1,
      max_depth: 0,
      max_string_bytes: 0,
      max_total_string_bytes: 0,
    },
  ).unwrap()
  for a in 0..<10 {
    for z in 0..<10 {
      for exact in [false, true] {
        let left = Some(count(a.to_int64(), exact))
        let right = Some(count(z.to_int64(), exact))
        let sum = sum_counts(source, left, right).unwrap()
        assert_eq(sum.upper, (a + z).to_int64())
        assert_eq(sum.exact, exact || a + z == 0)
        let product = product_counts(source, left, right).unwrap()
        assert_eq(product.upper, (a * z).to_int64())
        assert_eq(product.exact, exact || a * z == 0)
        for skip in 0..<10 {
          let sliced = slice_count(
            left,
            Some(z.to_int64()),
            Some(skip.to_int64()),
          ).unwrap()
          let remaining = if a > skip { a - skip } else { 0 }
          let expected = if remaining < z { remaining } else { z }
          assert_eq(sliced.upper, expected.to_int64())
          assert_eq(sliced.exact, exact || expected == 0)
        }
      }
    }
  }
  assert_true(sum_counts(source, None, Some(count(0L, true))) is None)
  assert_true(
    product_counts(source, None, Some(count(0L, true)))
    is Some({ upper: 0L, exact: true, }),
  )
  assert_true(
    slice_count(Some(count(4L, true)), None, Some(0L))
    is Some({ upper: 4L, exact: false, }),
  )
  assert_true(
    slice_count(Some(count(4L, true)), Some(1L), None)
    is Some({ upper: 1L, exact: false, }),
  )
}

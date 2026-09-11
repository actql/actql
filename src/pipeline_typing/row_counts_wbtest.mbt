///|
test "empty-schema set bounds cover all admitted multiplicities" {
  for operation in [@set.Operation::Except, @set.Operation::Intersect] {
    for policy in [@set.Duplicates::All, @set.Duplicates::Distinct] {
      for a in 0..<5 {
        for z in 0..<5 {
          for exact_left in [false, true] {
            for exact_right in [false, true] {
              let result = set_count(
                Some(count(a.to_int64(), exact_left)),
                Some(count(z.to_int64(), exact_right)),
                operation,
                policy,
                true,
              ).unwrap()
              for m in 0..<(a + 1) {
                if exact_left && m != a {
                  continue
                }
                for n in 0..<(z + 1) {
                  if exact_right && n != z {
                    continue
                  }
                  let actual = if policy == @set.Distinct {
                    if m > 0 &&
                      (if operation == @set.Except { n == 0 } else { n > 0 }) {
                      1
                    } else {
                      0
                    }
                  } else if operation == @set.Except {
                    if m > n {
                      m - n
                    } else {
                      0
                    }
                  } else if m < n {
                    m
                  } else {
                    n
                  }
                  assert_true(actual.to_int64() <= result.upper)
                  if result.exact {
                    assert_eq(actual.to_int64(), result.upper)
                  }
                }
              }
            }
          }
        }
      }
      assert_eq(
        set_count(None, None, operation, policy, true),
        if policy == @set.Distinct {
          Some(count(1L, false))
        } else {
          None
        },
      )
      assert_eq(set_count(None, None, operation, policy, false), None)
    }
  }
  assert_eq(
    set_count(
      Some(count(8L, true)),
      Some(count(0L, true)),
      @set.Except,
      @set.All,
      false,
    ),
    Some(count(8L, true)),
  )
  assert_eq(
    set_count(None, Some(count(0L, true)), @set.Intersect, @set.All, false),
    Some(count(0L, true)),
  )
}

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

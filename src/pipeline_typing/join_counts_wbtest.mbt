///|
test "join bounds cover every small matching graph including isolated rows" {
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
  for a in 0..<4 {
    for z in 0..<4 {
      for mask in 0..<(1 << (a * z)) {
        let left = Array::make(a, false)
        let right = Array::make(z, false)
        let mut pairs = 0
        for i in 0..<a {
          for j in 0..<z {
            if (mask & (1 << (i * z + j))) != 0 {
              left[i] = true
              right[j] = true
              pairs += 1
            }
          }
        }
        let mut unmatched_left = 0
        let mut unmatched_right = 0
        for matched in left {
          if !matched {
            unmatched_left += 1
          }
        }
        for matched in right {
          if !matched {
            unmatched_right += 1
          }
        }
        for
          (kind, actual) in [
            (@join.Inner, pairs),
            (Left, pairs + unmatched_left),
            (Full, pairs + unmatched_left + unmatched_right),
            (Semi, a - unmatched_left),
            (Anti, unmatched_left),
          ] {
          let bound = join_count(
            source,
            Some(count(a.to_int64(), true)),
            Some(count(z.to_int64(), true)),
            kind,
          ).unwrap()
          assert_true(actual.to_int64() <= bound.upper)
          if bound.exact {
            assert_eq(actual.to_int64(), bound.upper)
          }
        }
      }
    }
  }
  for kind in [@join.Inner, Left, Semi, Anti] {
    assert_eq(
      join_count(source, Some(count(0L, true)), None, kind),
      Some(count(0L, true)),
    )
  }
  assert_true(join_count(source, Some(count(0L, true)), None, Full) is None)
  assert_eq(
    join_count(source, None, Some(count(0L, true)), Semi),
    Some(count(0L, true)),
  )
  assert_true(join_count(source, None, Some(count(0L, true)), Anti) is None)
}

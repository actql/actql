///|
test "tuple comparison yields within long prefixes and many equal components" {
  let prefix = "x".repeat(1024)
  for many in [false, true] {
    let keys = if many {
      [Array::make(128, "a"), Array::make(128, "a")]
    } else {
      [[prefix, "\u{E000}"], [prefix, "😀"]]
    }
    // Two initialization visits, one run setup, one fragment per comparison
    // component, one unopposed tail move and one buffer swap. Long keys
    // use 16 prefix fragments plus one deciding UTF-16 component.
    let exact = if many { 133 } else { 22 }
    for quantum in [1, 7, 256] {
      let sort = prepare_deferred(keys, 4).unwrap()
      let mut total = 0L
      let mut complete = false
      for _ in 0..<200 {
        match advance(sort, quantum).unwrap() {
          Continue(work~, ..) => {
            assert_true(work >= 0 && work <= quantum.to_int64())
            total += work
          }
          Complete(work~, ..) => {
            assert_true(work >= 0 && work <= quantum.to_int64())
            total += work
            complete = true
            break
          }
        }
      }
      assert_true(complete)
      assert_eq(total, exact.to_int64())
      assert_eq(index_at(sort, 0), Some(if many { 0 } else { 1 }))
      assert_eq(index_at(sort, 1), Some(if many { 1 } else { 0 }))
      assert_true(cleanup(sort))
    }
    assert_true(prepare_deferred(keys, 3) is Err(WorkspaceLimit))
    let stopped = prepare_deferred(keys, 4).unwrap()
    for _ in 0..<8 {
      assert_true(advance(stopped, 1) is Ok(Continue(..)))
    }
    assert_eq(count(stopped), 0)
    assert_eq(index_at(stopped, 0), None)
    assert_true(cleanup(stopped))
    assert_true(stopped.source.is_empty())
    assert_true(stopped.target.is_empty())
  }
}

///|
test "tuple sort initializes and merges within the supplied quantum" {
  let sort = prepare([["b", "a"], ["a", "z"], ["a", "a"], ["b", "a"]], 8).unwrap()
  let mut polls = 0
  let mut complete = false
  while !complete {
    match advance(sort, 1) {
      Ok(Continue(_)) => {
        polls += 1
        assert_true(polls < 100)
      }
      Ok(Complete(_)) => complete = true
      Err(_) => fail("sort failed")
    }
  }
  assert_eq(count(sort), 4)
  assert_eq(index_at(sort, 0), Some(2))
  assert_eq(index_at(sort, 1), Some(1))
  assert_eq(index_at(sort, 2), Some(0))
  assert_eq(index_at(sort, 3), Some(3))
  assert_eq(key_component_at(sort, 0, 0), Some("a"))
  assert_eq(key_component_at(sort, 0, 1), Some("a"))
  assert_eq(key_component_at(sort, 4, 0), None)
}

///|
test "tuple sort admits workspace before initialization" {
  assert_true(prepare([["a"], ["b"]], 3) is Err(WorkspaceLimit))
}

///|
test "eager tuple sort still rejects key shapes during preparation" {
  assert_true(prepare([["a"], ["b", "c"]], 4) is Err(InvalidKey))
  assert_true(prepare([[]], 2) is Err(InvalidKey))
}

///|
test "deferred tuple sort preserves ordering and validates all key shapes" {
  let sort = prepare_deferred([["z"], ["a"], ["b"]], 6).unwrap()
  for _ in 0..<100 {
    match advance(sort, 1).unwrap() {
      Continue(work~, ..) => assert_true(work >= 0 && work <= 1)
      Complete(work~, ..) => {
        assert_true(work >= 0 && work <= 1)
        break
      }
    }
  }
  assert_eq([index_at(sort, 0), index_at(sort, 1), index_at(sort, 2)], [
    Some(1),
    Some(2),
    Some(0),
  ])
  assert_true(cleanup(sort))
  let bad = prepare_deferred([["a"], ["b", "c"]], 4).unwrap()
  assert_true(advance(bad, 1) is Ok(Continue(..)))
  assert_true(advance(bad, 1) is Err(InvalidKey))
  assert_eq(index_at(bad, 0), None)
  assert_true(cleanup(bad))
}

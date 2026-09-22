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
}

///|
test "tuple sort admits workspace before initialization" {
  assert_true(prepare([["a"], ["b"]], 3) is Err(WorkspaceLimit))
}

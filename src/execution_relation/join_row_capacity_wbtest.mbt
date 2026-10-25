///|
test "checked Join guards bound total output independently of literal source rows" {
  let owner_inner = bound_pipeline(
    "[{\"as\":\"l\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":1}]}},{\"as\":\"r\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":2}]}},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"k\",\"right\":\"k\"}],\"max_output_rows\":2000,\"select\":{\"k\":\"left.k\"}}}]",
  )
  let prepared_inner = @lower.bound_preparation(owner_inner)
  let node_inner = @lower.node_at(prepared_inner, 2).unwrap()
  assert_eq(@lower.node_row_count_bound(node_inner, [1, 1]), Some(1))
  assert_eq(@lower.node_row_count_bound(node_inner, [1]), None)
  assert_eq(@lower.prepared_closed_row_bound(prepared_inner, 100).unwrap().0, 1)
  let owner_left = bound_pipeline(
    "[{\"as\":\"l\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":1}]}},{\"as\":\"r\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":2}]}},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"left\",\"on\":[{\"left\":\"k\",\"right\":\"k\"}],\"max_output_rows\":2000,\"select\":{\"k\":\"left.k\"}}}]",
  )
  let prepared_left = @lower.bound_preparation(owner_left)
  let node_left = @lower.node_at(prepared_left, 2).unwrap()
  assert_eq(@lower.node_row_count_bound(node_left, [1, 1]), Some(1))
  assert_eq(@lower.node_row_count_bound(node_left, [1]), None)
  assert_eq(@lower.prepared_closed_row_bound(prepared_left, 100).unwrap().0, 1)
  let owner_right = bound_pipeline(
    "[{\"as\":\"l\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":1}]}},{\"as\":\"r\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":2}]}},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"right\",\"on\":[{\"left\":\"k\",\"right\":\"k\"}],\"max_output_rows\":2000,\"select\":{\"k\":\"left.k\"}}}]",
  )
  let prepared_right = @lower.bound_preparation(owner_right)
  let node_right = @lower.node_at(prepared_right, 2).unwrap()
  assert_eq(@lower.node_row_count_bound(node_right, [1, 1]), Some(1))
  assert_eq(@lower.node_row_count_bound(node_right, [1]), None)
  assert_eq(@lower.prepared_closed_row_bound(prepared_right, 100).unwrap().0, 1)
}

///|
test "unguarded checked joins use intrinsic bound without changing syntax" {
  let owner_inner = bound_pipeline(
    "[{\"as\":\"l\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]}},{\"as\":\"r\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":1},{\"k\":2},{\"k\":3}]}},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"k\",\"right\":\"k\"}],\"select\":{\"k\":\"right.k\"}}}]",
  )
  let prepared_inner = @lower.bound_preparation(owner_inner)
  assert_eq(
    @lower.node_row_count_bound(@lower.node_at(prepared_inner, 2).unwrap(), [
      0, 3,
    ]),
    Some(0),
  )
  assert_eq(@lower.prepared_closed_row_bound(prepared_inner, 100).unwrap().0, 3)
  let owner_left = bound_pipeline(
    "[{\"as\":\"l\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]}},{\"as\":\"r\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":1},{\"k\":2},{\"k\":3}]}},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"left\",\"on\":[{\"left\":\"k\",\"right\":\"k\"}],\"select\":{\"k\":\"right.k\"}}}]",
  )
  let prepared_left = @lower.bound_preparation(owner_left)
  assert_eq(
    @lower.node_row_count_bound(@lower.node_at(prepared_left, 2).unwrap(), [
      0, 3,
    ]),
    Some(0),
  )
  assert_eq(@lower.prepared_closed_row_bound(prepared_left, 100).unwrap().0, 3)
  let owner_right = bound_pipeline(
    "[{\"as\":\"l\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]}},{\"as\":\"r\",\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":1},{\"k\":2},{\"k\":3}]}},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"right\",\"on\":[{\"left\":\"k\",\"right\":\"k\"}],\"select\":{\"k\":\"right.k\"}}}]",
  )
  let prepared_right = @lower.bound_preparation(owner_right)
  assert_eq(
    @lower.node_row_count_bound(@lower.node_at(prepared_right, 2).unwrap(), [
      0, 3,
    ]),
    Some(3),
  )
  assert_eq(@lower.prepared_closed_row_bound(prepared_right, 100).unwrap().0, 3)
}

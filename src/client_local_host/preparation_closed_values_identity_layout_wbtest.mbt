///|
test "identity component keeps seven distinct CID owners and borrowed source text" {
  let value = closed_values_identity_layout(40, 4, 8).unwrap()
  assert_eq(value.cid_strings.record_headers, 7L)
  assert_eq(value.cid_strings.owned_utf16_units, 497L)
  assert_eq(
    @execution.preparation_representation_cost(value.cid_strings),
    Some(1106L),
  )
  assert_eq(value.fixed.owned_utf16_units, 0L)
  assert_eq(value.preparation.owned_utf16_units, 0L)
  assert_eq(value.emission.owned_wire_bytes, 0L)
}

///|
test "identity source traversal and simultaneous emitter frames grow with original extents" {
  let small = closed_values_identity_layout(40, 4, 8).unwrap()
  let large = closed_values_identity_layout(11000, 100, 8).unwrap()
  assert_true(small.fixed == large.fixed)
  assert_true(
    @execution.preparation_representation_cost(large.preparation).unwrap() >
    @execution.preparation_representation_cost(small.preparation).unwrap(),
  )
  assert_true(
    @execution.preparation_representation_cost(large.emission).unwrap() >
    @execution.preparation_representation_cost(small.emission).unwrap(),
  )
  let deep = closed_values_identity_layout(40, 4, 9).unwrap()
  assert_true(
    @execution.preparation_representation_cost(deep.emission).unwrap() >
    @execution.preparation_representation_cost(small.emission).unwrap(),
  )
  let total = @execution.compose_preparation_representation([
    small.fixed,
    small.preparation,
    small.emission,
    small.cid_strings,
  ]).unwrap()
  let cost = @execution.preparation_representation_cost(total).unwrap()
  assert_eq(
    cost,
    @execution.preparation_representation_cost(small.fixed).unwrap() +
    @execution.preparation_representation_cost(small.preparation).unwrap() +
    @execution.preparation_representation_cost(small.emission).unwrap() +
    @execution.preparation_representation_cost(small.cid_strings).unwrap(),
  )
}

///|
test "identity component refuses contradictory source extents" {
  for
    (nodes, fields, depth) in [
      (0, 0, 0),
      (-1, 0, 0),
      (2, 3, 1),
      (2, 1, 3),
      (2, -1, 1),
      (2, 1, -1),
    ] {
    assert_true(closed_values_identity_layout(nodes, fields, depth) is None)
  }
  let edge = closed_values_identity_layout(2147483647, 2147483647, 2147483647).unwrap()
  assert_true(
    @execution.preparation_representation_cost(edge.emission) is Some(_),
  )
}

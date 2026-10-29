///|
test "retained validation inventory derives occurrence storage and metadata only" {
  let small = program_retained_validation_layout(6, 6, 100).unwrap()
  let more = program_retained_validation_layout(600, 6, 10000).unwrap()
  assert_true(
    @execution.preparation_representation_cost(more.retained).unwrap() >
    @execution.preparation_representation_cost(small.retained).unwrap(),
  )
  assert_true(
    @execution.preparation_representation_cost(more.temporary).unwrap() >
    @execution.preparation_representation_cost(small.temporary).unwrap(),
  )
  let chain = program_validation_inventory_layout(2L, 2).unwrap()
  let commit = program_validation_inventory_layout(2L, 6).unwrap()
  assert_true(
    @execution.preparation_representation_cost(commit).unwrap() >
    @execution.preparation_representation_cost(chain).unwrap(),
  )
  assert_true(program_validation_inventory_layout(-1L, 2) is None)
  assert_true(program_validation_inventory_layout(1L, 3) is None)
  assert_true(program_retained_validation_layout(2, 2, 0) is None)
}

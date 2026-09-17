///|
test "independent managed copy outlives its exact scoped source" {
  let owner = capture_fixture()
  let generated = compute_test_sequence(owner)
  let completed = test_typed_completion(generated, 1)
  let permission = Ref(true)
  let source = restrict_completed_output(
    completed_output(completed, Step(1)).unwrap(),
    fn() { permission.val },
  )
  let copy = copy_completed_output_independent(source, 2, 2).unwrap()
  permission.val = false
  assert_false(completed_output_available(source))
  assert_true(completed_output_available(copy))
  assert_eq(completed_row_count(copy), 2)
  assert_true(completed_cell(copy, 1, 0) is Some(_))
  assert_true(copy_completed_output_independent(copy, 1, 2) is Err(Limit))
}

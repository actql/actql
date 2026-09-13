///|
test "public serial cost helper needs no host or source I/O" {
  let duration = @physical_cost.assess_serial(
    3,
    [
      { work_slots: [0], milliseconds: Some(3L), },
      { work_slots: [1, 2], milliseconds: Some(7L), },
    ],
    8,
  ).unwrap()
  assert_eq(duration, @physical_cost.Complete(10L))
  assert_true(
    @physical_cost.choose_serial([duration], None, 1).unwrap()
    is @physical_cost.EstimatedFastest(0, 10L),
  )
}

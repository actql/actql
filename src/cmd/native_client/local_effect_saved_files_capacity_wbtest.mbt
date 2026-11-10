///|
test "saved file application holds completed ACK bytes not future page maxima" {
  let physical = @execution.execution_capacity(1024L, 2048L).unwrap()
  let first = saved_effect_file_application_capacity(2, physical, 0L).unwrap()
  let next = saved_effect_file_application_capacity(2, physical, 37L).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(next) -
    @execution.execution_capacity_retained_bytes(first),
    37L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(next) -
    @execution.execution_capacity_execution_bytes(first),
    37L,
  )
  let slots = saved_effect_file_application_capacity(100, physical, 37L).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(slots) -
    @execution.execution_capacity_retained_bytes(next) <
    100000L,
  )
  assert_true(saved_effect_file_application_capacity(-1, physical, 0L) is None)
  assert_true(saved_effect_file_application_capacity(1, physical, -1L) is None)
}

///|
test "saved application preserves restoration and scratch before entered backing" {
  let original = @execution.execution_capacity(249862830L, 337566898L).unwrap()
  let phase = @execution.execution_capacity(4956488L, 4956488L).unwrap()
  let next = saved_effect_file_next_phase_capacity(original, phase).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(next), 254819318L)
  assert_eq(@execution.execution_capacity_execution_bytes(next), 337566898L)
  let larger = saved_effect_file_next_phase_capacity(
    original,
    @execution.execution_capacity(5000000L, 100000000L).unwrap(),
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(larger), 254862830L)
  assert_eq(@execution.execution_capacity_execution_bytes(larger), 349862830L)
}

///|
test "Effect response buffer backing composes pinned Array growth and retains failed receive window" {
  assert_true(installed_effect_response_buffer_construction_capacity(0) is None)
  assert_true(
    installed_effect_response_buffer_construction_capacity(-1) is None,
  )
  let small = installed_effect_response_buffer_representation(1).unwrap()
  let larger = installed_effect_response_buffer_representation(64).unwrap()
  // Independent receiver lifetimes: copied bytes + concat body + current
  // B+1 read. The failed receive cannot erase its already copied prefix.
  assert_eq(small.owned_wire_bytes, 1L + 1L + 2L)
  assert_eq(larger.owned_wire_bytes, 64L + 64L + 65L)
  assert_true(larger.record_headers > small.record_headers)
  assert_true(larger.reference_slots > small.reference_slots)
  assert_eq(larger.owned_utf16_units, 0L)
  // All arithmetic is logical Int64 quantity DATA, not an allocation of this
  // body or a claim that Node/Native can physically supply it.
  assert_true(
    installed_effect_response_buffer_construction_capacity(2147483647)
    is Some(_),
  )
}

///|
test "Effect response buffer backing checks exact original extent before an occurrence can use it" {
  let capacity = installed_effect_response_buffer_construction_capacity(64).unwrap()
  let selected = prepare_installed_effect_operation_extent(
    "read", capacity, 65L, true,
  ).unwrap()
  assert_true(installed_effect_operation_response_backing_fits(selected, 64))
  assert_false(installed_effect_operation_response_backing_fits(selected, 65))
  assert_false(installed_effect_operation_response_backing_fits(selected, 0))
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity)
  let short = @execution.execution_capacity(retained - 1L, execution).unwrap()
  let short_extent = prepare_installed_effect_operation_extent(
    "read", short, 65L, true,
  ).unwrap()
  assert_false(
    installed_effect_operation_response_backing_fits(short_extent, 64),
  )
  let pure = prepare_installed_effect_operation_extent(
    "read", capacity, 0L, false,
  ).unwrap()
  assert_false(installed_effect_operation_response_backing_fits(pure, 64))
  // There is no borrow, binding, request, transfer debit or permission here.
  // Native capacity correspondence is a necessary component, not a full Plan.
}

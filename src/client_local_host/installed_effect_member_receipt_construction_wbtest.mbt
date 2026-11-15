///|
test "member scratch uses actual rows without widening provider row policy" {
  let (one, one_bytes, _, _) = installed_effect_member_receipt_construction(
    1, 1510, 512, 16,
  ).unwrap()
  let (eight, eight_bytes, eight_nodes, eight_depth) = installed_effect_member_receipt_construction(
    8, 1510, 512, 16,
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(eight), 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(eight) >
    @execution.execution_capacity_execution_bytes(one),
  )
  assert_true(eight_bytes > 1510)
  assert_true(eight_bytes <= 8 * 1510)
  assert_true(eight_nodes <= 8 * 512)
  assert_true(eight_depth <= 16)
  assert_true(
    installed_effect_member_receipt_construction(1, one_bytes - 1, 512, 16)
    is None,
  )
  assert_true(
    installed_effect_member_receipt_construction(8, 1510, 1, 16) is None,
  )
  assert_true(
    installed_effect_member_receipt_construction(8, 1510, 512, 1) is None,
  )
  assert_true(
    installed_effect_member_receipt_construction(0, 1510, 512, 16) is None,
  )
  assert_true(
    installed_effect_member_receipt_construction(
      2147483647, 2147483647, 2147483647, 2147483647,
    )
    is None,
  )
}

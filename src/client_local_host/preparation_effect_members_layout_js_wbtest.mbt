///|
test "Effect member selection quotes actual 17 definitions independently of row policy" {
  assert_true(installed_effect_member_selection_layout(-1) is None)
  let single = installed_effect_member_selection_layout(1).unwrap()
  let sixteen = installed_effect_member_selection_layout(16).unwrap()
  let seventeen = installed_effect_member_selection_layout(17).unwrap()
  assert_true(single.0 > 0L && single.1 >= single.0)
  assert_true(seventeen.0 > sixteen.0 && seventeen.1 > sixteen.1)
  // Definition wrappers are finite DATA, not credit for 17 sends or 101 rows.
  // Existing original Plan and captured-row reservation tests exercise those
  // separate numerical boundaries on the same Run ledger.
  assert_true(seventeen.0 < 17L * single.0)
}

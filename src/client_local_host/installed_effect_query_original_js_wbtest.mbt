///|
#cfg(target="js")
test "Effect publication borrows Query originals from Row and native slots but never Whole" {
  let row = effect_operation_source_plan_fixture()
  let row_original = prepared_installed_effect_managed_query_requirement(row, 0).unwrap()
  assert_true(physical_equal(row_original, row.captures[0].requirement))
  let native = effect_native_source_plan_fixture(row).unwrap()
  assert_true(prepared_installed_effect_managed_source(native, 0) is Err(_))
  let native_original = prepared_installed_effect_managed_query_requirement(
    native, 0,
  ).unwrap()
  assert_true(physical_equal(native_original, native.captures[0].requirement))
  assert_true(
    prepared_installed_effect_managed_query_requirement(native, -1) is Err(_),
  )
  assert_true(
    prepared_installed_effect_managed_query_requirement(native, 1) is Err(_),
  )
  let whole = effect_operation_source_plan_fixture(whole_inputs=true)
  for slot in 0..<whole.whole_sources.length() {
    assert_true(
      prepared_installed_effect_managed_query_requirement(whole, slot) is Err(_),
    )
  }
  assert_eq(row.captures.length(), 1)
  assert_eq(native.declarations.length(), 0)
}

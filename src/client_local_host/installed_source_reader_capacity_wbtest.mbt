///|
test "JSON Source reader inventory uses shared tariff and separate retained workspace" {
  // Independent authored inventory vector; no returned quote supplies any
  // expected amount, Ledger limit, admission or physical cleanup receipt.
  assert_eq(installed_source_reader_policy(), [65536, 100000, 100])
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  // One additional reader-frame reference is eight bytes in the SAME tariff.
  let capacity = installed_json_source_reader_capacity(limits, 2, 3).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), 3400L)
  assert_eq(@execution.execution_capacity_execution_bytes(capacity), 30784L)
  assert_true(installed_json_source_reader_capacity([], 2, 3) is None)
  assert_true(installed_json_source_reader_capacity(limits, 0, 3) is None)
  assert_true(installed_json_source_reader_capacity(limits, 2, 0) is None)
  let invalid = limits.copy()
  invalid[3] = 0
  assert_true(installed_json_source_reader_capacity(invalid, 2, 3) is None)
  let overflow = Array::make(16, 2147483647)
  assert_true(
    installed_json_source_reader_capacity(overflow, 2147483647, 2147483647)
    is None,
  )
}

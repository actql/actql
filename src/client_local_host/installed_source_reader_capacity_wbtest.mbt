///|
test "JSON Source reader inventory uses shared tariff and separate retained workspace" {
  // Independent authored inventory vector; no returned quote supplies any
  // expected amount, Ledger limit, admission or physical cleanup receipt.
  assert_eq(installed_source_reader_policy(), [65536, 100000, 100])
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  // The reader also retains its original sequence retirement method/state.
  let capacity = installed_json_source_reader_capacity(limits, 2, 3).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), 3416L)
  assert_eq(@execution.execution_capacity_execution_bytes(capacity), 30800L)
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

///|
test "Slack original prefix composes retained scalar composite and protocol inventories" {
  let limits = [4, 6, 3, 4, 2, 3, 3, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let capacity = installed_slack_source_reader_capacity(limits, 11, 3, 2).unwrap()
  let json = installed_json_source_reader_capacity(limits, 11, 3).unwrap()
  // Independent vector: 183 headers, 700 refs, 258 words, 1122 UTF16 units,
  // 45 checked nodes. Workspace: 21 headers, 163 refs, 28 words, 370 UTF16.
  assert_eq(
    @execution.execution_capacity_retained_bytes(capacity) -
    @execution.execution_capacity_retained_bytes(json),
    24356L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(capacity) -
    @execution.execution_capacity_execution_bytes(json),
    26962L,
  )
  assert_true(installed_slack_source_reader_capacity(limits, 8, 3, 2) is None)
  assert_true(installed_slack_source_reader_capacity(limits, 11, 3, 1) is None)
  assert_true(installed_slack_source_reader_capacity(limits, 11, 0, 2) is None)
  assert_true(
    installed_slack_source_reader_capacity(
      Array::make(16, 2147483647),
      11,
      2147483647,
      2147483646,
    )
    is None,
  )
}

///|
test "Gmail sequence retains the complete original list get prefix alongside JSON workspace" {
  let limits = [4, 6, 3, 4, 1, 3, 5, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let capacity = installed_gmail_thread_reader_capacity(limits, 5, 3, 2, 12).unwrap()
  // Independently authored tariff totals for this fixed inventory, including
  // all six retained checked-value nodes and the one original request DTO.
  let json = installed_json_source_reader_capacity(limits, 5, 3).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(capacity) -
    @execution.execution_capacity_retained_bytes(json),
    4468L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(capacity) -
    @execution.execution_capacity_execution_bytes(json),
    5556L,
  )
  assert_true(
    installed_gmail_thread_reader_capacity(limits, 4, 3, 2, 12) is None,
  )
  assert_true(
    installed_gmail_thread_reader_capacity(limits, 5, 3, 3, 12) is None,
  )
  assert_true(
    installed_gmail_thread_reader_capacity(limits, 5, 3, 2, 0) is None,
  )
  assert_true(
    installed_gmail_thread_reader_capacity(
      Array::make(16, 2147483647),
      5,
      3,
      2,
      12,
    )
    is None,
  )
}

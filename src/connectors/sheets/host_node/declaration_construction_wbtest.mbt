///|
test "range and clear native constructor quote composes onto original Source without issuing a declaration" {
  let original = @execution.execution_capacity(11L, 13L).unwrap()
  let native = sheets_range_declaration_construction_capacity(
    100, 1, 90, 6, 2000,
  ).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(native) > 0L)
  let combined = @client_host.compose_installed_source_construction_capacity(
    original,
    [native],
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(native)
  assert_eq(@execution.execution_capacity_retained_bytes(combined), 11L + peak)
  assert_eq(@execution.execution_capacity_execution_bytes(combined), 13L + peak)
  assert_true(
    sheets_range_declaration_construction_capacity(100, 0, 90, 6, 2000) is None,
  )
  assert_true(
    sheets_range_declaration_construction_capacity(100, 1, 90, 6, 0) is None,
  )
}

///|
test "range Source Reference constructor keeps a distinct Source lifetime from its Reader alternatives" {
  let source = sheets_range_reference_construction_capacity(32, 4).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(source) > 0L)
  let grid = sheets_grid_read_construction_capacity(100, 1, 0, 0, 1, 0, 1).unwrap()
  let reader = sheets_range_read_construction_capacity(100, 1, 0, 0, 1, 0, 1, 200000, 32).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(reader) >= @execution.execution_capacity_execution_bytes(grid))
  assert_true(@execution.execution_capacity_retained_bytes(reader) >= @execution.execution_capacity_retained_bytes(grid))
  let original = @execution.execution_capacity(11L, 13L).unwrap()
  let joined = @client_host.compose_installed_source_construction_capacity(original, [source]).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(joined), 11L + @execution.execution_capacity_execution_bytes(source))
  assert_true(sheets_range_reference_construction_capacity(0, 4) is None)
  assert_true(sheets_range_read_construction_capacity(100, 1, 0, 0, 1, 0, 1, 0, 32) is None)
}

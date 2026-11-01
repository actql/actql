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
  let reader = sheets_range_read_construction_capacity(
    100, 1, 0, 0, 1, 0, 1, 200000, 32,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(reader) >=
    @execution.execution_capacity_execution_bytes(grid),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(reader) >=
    @execution.execution_capacity_retained_bytes(grid),
  )
  let original = @execution.execution_capacity(11L, 13L).unwrap()
  let joined = @client_host.compose_installed_source_construction_capacity(
    original,
    [source],
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(joined),
    11L + @execution.execution_capacity_execution_bytes(source),
  )
  assert_true(sheets_range_reference_construction_capacity(0, 4) is None)
  assert_true(
    sheets_range_read_construction_capacity(100, 1, 0, 0, 1, 0, 1, 0, 32)
    is None,
  )
}

///|
test "range and clear driver profiles retain original binding constructor and independent capture peaks" {
  let configuration = "{\"origin\":\"https://sheets.example.test\",\"spreadsheetId\":\"book\",\"range\":{\"sheetId\":7,\"startRow\":2,\"endRow\":4,\"startColumn\":1,\"endColumn\":3},\"columns\":[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false},{\"name\":\"flag\",\"type\":\"boolean\",\"nullable\":true}]}"
  let cid = "sha256:" + "b".repeat(64)
  let limits : @catalog.Limits = {
    max_bytes: 300000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  let target = @catalog.range_reference(
      "https://sheets.example.test",
      "book",
      { sheet_id: 7, start_row: 2, end_row: 4, start_column: 1, end_column: 3, },
      "sha256:" + "a".repeat(64),
      cid,
      limits,
    )
    .unwrap()
    .stringify()
  let binding = @catalog.admit_range_binding(
    configuration, "sha256:e3b7d39898d2037cffd055b1c51f24c66e616d2bb8ae3d4a34529515c26196ab",
    cid, target, limits,
  ).unwrap()
  let clear = @catalog.admit_clear_range_binding(
    configuration, "sha256:e3b7d39898d2037cffd055b1c51f24c66e616d2bb8ae3d4a34529515c26196ab",
    cid, target, limits,
  ).unwrap()
  let profiles = [
    sheets_range_construction_profile(
      binding, 100000, 10000, 16, 1000000, 200000, 32,
    ).unwrap(),
    sheets_clear_construction_profile(
      clear, 100000, 10000, 16, 1000000, 200000, 32,
    ).unwrap(),
  ]
  let captures = [
    sheets_range_capture_construction_profile(
      binding, 1000000, 100000, 64, 100000, 10000, 16,
    ).unwrap(),
    sheets_clear_capture_construction_profile(
      clear, 1000000, 100000, 64, 100000, 10000, 16,
    ).unwrap(),
  ]
  for index in 0..<2 {
    assert_eq(profiles[index].length(), 2)
    assert_eq(captures[index].length(), 2)
    assert_true(profiles[index][0].1 is None)
    assert_true(profiles[index][0].2 is Some(_))
    assert_true(
      @execution.execution_capacity_execution_bytes(profiles[index][0].0) > 0L,
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(captures[index][0]) > 0L,
    )
    // SAME request constructor is also needed by stored-response recovery;
    // it is a per-row capture holding, never an aliased physical send grant.
    assert_eq(
      @execution.execution_capacity_execution_bytes(captures[index][1]),
      @execution.execution_capacity_execution_bytes(profiles[index][0].0),
    )
  }
  assert_true(
    sheets_range_construction_profile(
      binding, 0, 10000, 16, 1000000, 200000, 32,
    )
    is None,
  )
  assert_true(
    sheets_clear_capture_construction_profile(
      clear, 0, 100000, 64, 100000, 10000, 16,
    )
    is None,
  )
  assert_true(
    sheets_range_installation_construction_capacity(
      configuration.length(),
      2,
      27,
      4,
    )
    is Some(_),
  )
  assert_true(
    sheets_range_installation_construction_capacity(
      configuration.length(),
      0,
      27,
      4,
    )
    is None,
  )
}

///|
fn target_update_quote_work() -> Unit raise {
  let declaration = @rows.generate_row_declaration(
    "native-file-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "string", nullable: false, },
          { name: "value", value_type: "string", nullable: false, },
        ],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 2,
    },
  ).unwrap()
  let provider = prepare_native_relation_file_provider(
    declaration,
    {
      directory: "/tmp",
      name: "staged.json",
      resource: "records",
      items_path: ["items"],
      key_path: None,
      primary_identity: "id",
    },
    {
      page: {
        max_bytes: 1048576,
        max_nodes: 4096,
        max_depth: 32,
        max_rows: 100,
      },
      max_work: 16777216,
      chunk_bytes: 8192,
      diagnostic_ceiling: 4096,
    },
  ).unwrap()
  let changes = "{\"value\":\"new text\"}"
  let (initial, _) = native_relation_file_target_update_construction(
    provider, 1, 0, changes,
  ).unwrap()
  let (actual, raw) = native_relation_file_target_update_construction(
    provider, 1, 1024, changes,
  ).unwrap()
  let maximum = native_relation_file_target_io_capacity(provider, 1).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(initial) <=
    @execution.execution_capacity_retained_bytes(actual),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(actual) <
    @execution.execution_capacity_retained_bytes(maximum),
  )
  // Independent coholding fixture: a retained 250MB reconstruction and its
  // old 340MB peak under the existing 512MiB facility, not a new allowance.
  assert_true(
    250000000L + @execution.execution_capacity_retained_bytes(actual) <
    536870912L,
  )
  assert_true(
    Int64::max(
      340000000L,
      250000000L + @execution.execution_capacity_execution_bytes(actual),
    ) <
    536870912L,
  )
  assert_true(raw > 0L)
  assert_eq(provider.limits.page.max_bytes, 1048576)
  assert_eq(provider.limits.page.max_nodes, 4096)
  for size in [-1, 1048577] {
    assert_true(
      native_relation_file_target_update_construction(
        provider, 1, size, changes,
      )
      is None,
    )
  }
}

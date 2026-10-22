///|
// Existing checked Source originals. These are common limit/correspondence
// cases, not an operational admission, physical Node read or permission.
fn installed_single_row_source_limits(
  prepared : @publication_host.PreparedClientProgram,
  capacities : Array[ClientInstalledCaptureCapacity],
  transfer : Array[Int64],
  workspace : Array[Int64],
) -> @resources.LedgerLimits? {
  multi_captured_installed_limits_owned(
    Pure(prepared),
    capacities,
    transfer,
    workspace,
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  )
}

///|
test "single RowSource managed parent includes its original capture and Compute suffix" {
  let prepared = installed_source_read_prepared_fixture()
  assert_true(installed_managed_run_purpose_supported(prepared))
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(prepared)),
  ).unwrap()
  let limits = installed_single_row_source_limits(
    prepared,
    [capacity],
    [4096L],
    [2048L],
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(limits.attempts, @strategy.graph_task_count(graph))
  assert_eq(limits.holdings, @strategy.graph_task_count(graph))
  assert_true(limits.retained_bytes >= capacity.retained_bytes + 200000000L)
  assert_true(limits.transfer_bytes >= 4096L)
  assert_true(limits.execution_bytes >= capacity.execution_bytes + 2048L)
  assert_true(limits.execution_bytes >= 536870912L)
}

///|
test "single RowSource managed parent refuses missing extra foreign and overflowing acquisition bounds" {
  let prepared = installed_source_read_prepared_fixture()
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(prepared)),
  ).unwrap()
  assert_true(
    installed_single_row_source_limits(prepared, [capacity], [4096L], [2048L])
    is Some(_),
  )
  for
    (captures, transfer, workspace) in [
      ([], [], []),
      ([capacity, capacity], [4096L, 4096L], [2048L, 2048L]),
      ([capacity], [], [2048L]),
      ([capacity], [4096L], []),
      ([capacity], [-1L], [2048L]),
      ([capacity], [4096L], [-1L]),
      ([capacity], [9223372036854775807L], [2048L]),
      ([capacity], [4096L], [9223372036854775807L]),
    ] {
    assert_true(
      installed_single_row_source_limits(
        prepared, captures, transfer, workspace,
      )
      is None,
    )
  }
  let other = source_free_managed_prepared_fixture(
    document=source_query_original_document.replace(old="id > 0", new="id > 1"),
  )
  let foreign = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(other)),
  ).unwrap()
  assert_true(
    installed_single_row_source_limits(prepared, [foreign], [4096L], [2048L])
    is None,
  )
}

///|
test "installed capture demand uses its actual checked Source and the original Local suffix limits" {
  let prepared = installed_source_read_prepared_fixture()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(prepared)),
  ).unwrap()
  let quoted = installed_managed_capture_run_requirements(
    prepared,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let expected = installed_single_row_source_limits(
    prepared,
    [capacity],
    [4096L],
    [2048L],
  ).unwrap()
  assert_eq(quoted, [
    expected.planning_work.to_int64(),
    expected.attempts.to_int64(),
    expected.holdings.to_int64(),
    expected.transfer_bytes,
    expected.retained_bytes,
    expected.execution_bytes,
  ])
  assert_true(quoted[3] >= 4096L)
  assert_true(quoted[4] >= capacity.retained_bytes)
  assert_true(quoted[5] >= capacity.execution_bytes + 2048L)
}

///|
test "installed capture demand refuses foreign missing extra negative and overflowing bounds" {
  let prepared = installed_source_read_prepared_fixture()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(prepared)),
  ).unwrap()
  for
    (captures, transfer, workspace) in [
      ([], [], []),
      ([capacity, capacity], [1L, 1L], [1L, 1L]),
      ([capacity], [], [1L]),
      ([capacity], [1L], []),
      ([capacity], [-1L], [1L]),
      ([capacity], [1L], [-1L]),
      ([capacity], [9223372036854775807L], [1L]),
      ([capacity], [1L], [9223372036854775807L]),
    ] {
    assert_true(
      installed_managed_capture_run_requirements(
        prepared,
        captures,
        transfer,
        workspace,
        contracts,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
      )
      is Err(Unsupported),
    )
  }
  let changed = source_free_managed_prepared_fixture(
    document=source_query_original_document.replace(old="id > 0", new="id > 1"),
  )
  assert_true(
    installed_managed_capture_run_requirements(
      changed,
      [capacity],
      [1L],
      [1L],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Unsupported),
  )
}

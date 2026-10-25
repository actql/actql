///|
// Existing independently authored Source/Compute fixture. No Provider I/O or
// installed Host ceiling is established by this portable owner test.
fn single_installed_prepared(
  document? : String = source_query_original_document,
) -> @publication_host.PreparedClientProgram {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
fn single_installed_ledger(
  prepared : @publication_host.PreparedClientProgram,
  capacity : ClientInstalledCaptureCapacity,
  transfer? : Int64 = 4096L,
  execution? : Int64 = 4096L,
) -> @resources.Ledger? {
  let source_contracts = prepare_installed_sequence_contracts(source_query_original_registry, source_query_original_values, Some(source_query_original_fragment), None).unwrap()
  prepare_single_captured_local_installed_ledger(
    prepared,
    capacity,
    transfer,
    execution,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  )
}

///|
test "single installed capture preserves its accounted holding on the original planned ledger" {
  let source_contracts = prepare_installed_sequence_contracts(source_query_original_registry, source_query_original_values, Some(source_query_original_fragment), None).unwrap()
  let prepared = single_installed_prepared()
  let acquisition = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  let capacity = installed_row_capture_capacity(acquisition).unwrap()
  let ledger = single_installed_ledger(prepared, capacity).unwrap()
  let compute = single_captured_compute_limits(
    prepared,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let limits = @resources.ledger_admission_limits(ledger)
  assert_eq(
    limits.retained_bytes,
    compute.retained_bytes + capacity.retained_bytes,
  )
  assert_eq(limits.execution_bytes, compute.execution_bytes)
  assert_eq(limits.transfer_bytes, compute.transfer_bytes + 4096L)
  assert_eq(limits.attempts, compute.attempts)
  let run = @row_source_host.start_accounted_row_acquisition(
    acquisition,
    "single-installed-original",
    _ => true,
    ledger,
    4096L,
    4096L,
  ).unwrap()
  // This fixture has only registered the read; no physical request was made.
  // Closing the unused original returns its pending slot, not spent work.
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    capacity.retained_bytes,
  )
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "single installed capture refuses a different checked requirement and multi capture graph" {
  let prepared = single_installed_prepared()
  let other = single_installed_prepared(
    document=source_query_original_document.replace(old="id > 0", new="id > 1"),
  )
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(other)),
  ).unwrap()
  assert_true(single_installed_ledger(prepared, capacity) is None)
  assert_true(
    single_installed_ledger(nearest_failed_prepared(), capacity) is None,
  )
}

///|
test "single installed capture rejects transport overflow and preserves the existing execution ceiling" {
  let prepared = single_installed_prepared()
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(prepared)),
  ).unwrap()
  for bytes in [-1L, 9223372036854775807L] {
    assert_true(
      single_installed_ledger(prepared, capacity, transfer=bytes) is None,
    )
    assert_true(
      single_installed_ledger(prepared, capacity, execution=bytes) is None,
    )
  }
  let ceiling = 536870912L - capacity.execution_bytes
  assert_true(
    single_installed_ledger(prepared, capacity, execution=ceiling) is Some(_),
  )
  assert_true(
    single_installed_ledger(prepared, capacity, execution=ceiling + 1L) is None,
  )
}

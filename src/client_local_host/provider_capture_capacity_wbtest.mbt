///|
test "provider capture planner seals the exact original acquisition and declaration" {
  let prepared = single_installed_prepared()
  let acquisition = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  let original = installed_row_capture_capacity(acquisition).unwrap()
  let declaration = @execution.execution_capacity(7L, 9L).unwrap()
  let capacity = installed_provider_row_capture_capacity(
    acquisition,
    Some(declaration),
  ).unwrap()
  assert_eq(capacity.retained_bytes, original.retained_bytes + 7L)
  assert_eq(capacity.execution_bytes, original.execution_bytes + 9L)
  assert_true(physical_equal(capacity.requirement, original.requirement))
  assert_true(
    installed_provider_row_capture_capacity_matches(
      capacity, acquisition, declaration,
    ),
  )
  assert_false(
    installed_provider_row_capture_capacity_matches(
      capacity,
      acquisition,
      @execution.execution_capacity(7L, 9L).unwrap(),
    ),
  )
  let foreign = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  assert_false(
    installed_provider_row_capture_capacity_matches(
      capacity, foreign, declaration,
    ),
  )
  assert_false(
    installed_provider_row_capture_capacity_matches(
      original, acquisition, declaration,
    ),
  )
}

///|
test "provider capture planner refuses missing overflow and listing profile substitution" {
  let prepared = single_installed_prepared()
  let acquisition = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  assert_true(
    installed_provider_row_capture_capacity(acquisition, None) is None,
  )
  assert_true(
    installed_provider_row_capture_capacity(
      acquisition,
      @execution.execution_capacity(9223372036854775807L, 9223372036854775807L),
    )
    is None,
  )
  assert_true(
    installed_provider_row_capture_capacity(
      listing_report_acquisition_fixture(),
      @execution.execution_capacity(7L, 9L),
    )
    is None,
  )
  assert_true(installed_row_capture_capacity(acquisition) is Some(_))
}

///|
test "provider capture planner carries its overlap into the same prepared Run ledger" {
  let source_contracts = prepare_installed_sequence_contracts(source_query_original_registry, source_query_original_values, Some(source_query_original_fragment), None).unwrap()
  let prepared = single_installed_prepared()
  let acquisition = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  let declaration = @execution.execution_capacity(7L, 9L).unwrap()
  let capacity = installed_provider_row_capture_capacity(
    acquisition,
    Some(declaration),
  ).unwrap()
  let ledger = single_installed_ledger(prepared, capacity).unwrap()
  let compute = single_captured_compute_limits(
    prepared,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_eq(
    @resources.ledger_admission_limits(ledger).retained_bytes,
    compute.retained_bytes + capacity.retained_bytes,
  )
  let run = @row_source_host.start_accounted_provider_row_acquisition(
    acquisition,
    Some(declaration),
    "provider-prepared-ledger",
    _ => true,
    ledger,
    4096L,
    4096L,
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    capacity.retained_bytes,
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    capacity.execution_bytes + 4096L,
  )
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  let foreign = single_installed_prepared(
    document=source_query_original_document.replace(old="id > 0", new="id > 1"),
  )
  assert_true(single_installed_ledger(foreign, capacity) is None)
}

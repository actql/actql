///|
// Actual checked Catalog/Query/listing and the existing Compute constructor.
// No physical Source, Effect permission or normal artifact is issued here.
test "captured Source row bounds survive into the same Compute configuration" {
  let (declaration, prepared, _, _, _, _, requirement) = original_keyed_run_fixture(
    selector_free=true,
    listing_maximum=1000L,
    listing_bytes=1000000L,
  )
  let acquisition = @row_source_host.prepare_row_acquisition(
    declaration, requirement, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
  ).unwrap()
  let capture = installed_row_capture_capacity(acquisition).unwrap()
  assert_true(physical_equal(capture.requirement, requirement))
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let sequences = prepare_client_local_sequences_owned(
    Pure(prepared),
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let compute = prepare_installed_compute_preparation(
    Pure(prepared),
    None,
    sequences,
    [capture],
    [0L],
    [0L],
    true,
    _ => [],
    runtime_admission=true,
  ).unwrap()
  let rows = Int64::min(
    @planning.query_requirement_guards(requirement).max_rows.to_int64(),
    @row_source_host.row_acquisition_listing_report_bounds(acquisition).unwrap().0,
  ).to_int()
  assert_true(rows > 100)
  assert_eq(compute.configuration.capacity.max_rows, rows)
  assert_eq(compute.capacity_plan.execution.rows.max_rows, rows)
  // A Source envelope does not change the unrelated Values default.
  assert_eq(
    @publication_host.client_standard_values_sequence_limits().max_rows,
    100,
  )
}

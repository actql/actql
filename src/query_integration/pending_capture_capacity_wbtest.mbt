///|
fn pending_capture_capacity(
  requirement : @planning.QueryRequirement,
) -> @client_local_host.ClientDuckDBCaptureCapacity raise {
  let (query, evidence) = query_evidence_test_bodies()
  @client_local_host.prepare_client_duckdb_capture_capacity(
    requirement,
    "main",
    "records",
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
    @identity.stringify_value(query_two_receipt_test_body(), 100000, 10000, 100),
  ).unwrap()
}

///|
fn pending_capture_requirement(
  id? : String = "pending-capacity",
) -> @planning.QueryRequirement raise {
  let (program, sequence) = query_program_fixture(id~)
  @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    program,
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
}

///|
test "pending Source capacity needs no acquisition choice and keeps nonzero immutable bounds" {
  let requirement = pending_capture_requirement()
  // No registry comparison, AcquisitionChoice, Host configuration or read
  // approval exists in this path. The pending envelope alone is sufficient.
  let envelope = pending_capture_capacity(requirement)
  let values = @client_local_host.client_duckdb_capture_capacity_values(
    envelope,
  )
  assert_eq(values.length(), 2)
  // Independently summed installed Native limits: 414400 structural retained
  // allowances, 4230000 text bytes, 40920 scratch nodes and 500000 scratch bytes.
  assert_true(values[0] >= 139926400L)
  assert_true(values[1] >= 14475520L)
  values[0] = 0L
  values[1] = 0L
  let retained = @client_local_host.client_duckdb_capture_capacity_values(
    envelope,
  )
  assert_true(retained[0] >= 139926400L)
  assert_true(retained[1] >= 14475520L)
  assert_true(
    @client_local_host.client_duckdb_capture_capacity_matches_requirement(
      envelope,
      pending_capture_requirement(),
    ),
  )
  assert_false(
    @client_local_host.client_duckdb_capture_capacity_matches_requirement(
      envelope,
      pending_capture_requirement(id="another-program"),
    ),
  )
}

///|
test "pending envelope admits real Native capacity but rejects growth and foreign requirement" {
  let limits = native_runtime_limits()
  let configuration = @acquisition_host.native_capture_configuration(
    native_runtime_setup(limits),
  )
  let requirement = @acquisition_host.configured_capture_requirement(
    configuration,
  )
  let envelope = pending_capture_capacity(requirement)
  let selected = @acquisition_host.configured_capture_capacity(configuration).unwrap()
  let unselected = @acquisition_host.prepared_native_capacity(limits).unwrap()
  assert_eq(selected.retained_bytes, unselected.retained_bytes)
  assert_eq(selected.execution_bytes, unselected.execution_bytes)
  assert_true(
    @client_local_host.client_duckdb_capture_capacity_accepts(
      envelope, configuration,
    ),
  )
  let enlarged = @acquisition_host.native_capture_configuration(
    native_runtime_setup({
      ..limits,
      physical: { ..limits.physical, max_rows: 2147483647, },
    }),
  )
  assert_false(
    @client_local_host.client_duckdb_capture_capacity_accepts(
      envelope, enlarged,
    ),
  )
  assert_false(
    @client_local_host.client_duckdb_capture_capacity_accepts(
      pending_capture_capacity(pending_capture_requirement(id="foreign")),
      configuration,
    ),
  )
}

///|
test "pending envelope admits Broad residual capacity and refuses oversized residual policy" {
  let fixture = broad_issuer_fixture()
  let (query, evidence) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query,
    evidence,
    query_capture_limits(),
  ).unwrap()
  let limits : @acquisition_host.BroadHostLimits = {
    physical: { max_rows: 3, max_cells: 3, max_nodes: 3, max_text_bytes: 0, },
    metadata_work: 100,
    retention: run_limits().input_values,
    completion: broad_host_completion_limits(),
    transport: {
      max_bytes: 10000,
      max_nodes: 100,
      max_columns: 10,
      max_rows: 3,
      max_text_bytes: 1000,
    },
  }
  let configuration = @acquisition_host.broad_capture_configuration(
    @acquisition_host.configure_broad_host(
      contracts,
      fixture.requirement,
      fixture.choice,
      fixture.prepared,
      limits,
    ),
  )
  let envelope = pending_capture_capacity(fixture.requirement)
  let selected = @acquisition_host.configured_capture_capacity(configuration).unwrap()
  let unselected = @acquisition_host.prepared_broad_capacity(
    fixture.requirement,
    limits,
  ).unwrap()
  assert_eq(selected.retained_bytes, unselected.retained_bytes)
  assert_eq(selected.execution_bytes, unselected.execution_bytes)
  assert_true(
    @client_local_host.client_duckdb_capture_capacity_accepts(
      envelope, configuration,
    ),
  )
  let enlarged = @acquisition_host.broad_capture_configuration(
    @acquisition_host.configure_broad_host(
      contracts,
      fixture.requirement,
      fixture.choice,
      fixture.prepared,
      { ..limits, physical: { ..limits.physical, max_nodes: 2147483647, }, },
    ),
  )
  assert_false(
    @client_local_host.client_duckdb_capture_capacity_accepts(
      envelope, enlarged,
    ),
  )
  @duckdb_query.close_duckdb_query_issuer(fixture.issuer)
}

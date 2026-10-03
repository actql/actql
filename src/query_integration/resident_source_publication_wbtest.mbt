///|
fn resident_source_captured_fixture() -> (
  @strategy.CapturedDAG,
  @mock.MockQueryIssuer,
) raise {
  let program = query_checked_program_fixture()
  let sequence = query_checked_sequence(program)
  let owners = physical_graph_owners(program)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(program, owners, 10, 1000).unwrap()
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(program),
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "resident-source", 100,
  ).unwrap()
  let attempt = query_issuer_attempt(issuer, sequence, @mock.NativeQuery)
  query_issuer_run(attempt)
  let observation = @mock.capture_mock_query(
    issuer,
    attempt,
    @mock.issue_mock_query_records(attempt, query_material_limits()).unwrap(),
    query_capture_limits(),
  ).unwrap()
  let source = @mock.mock_captured_source(issuer, attempt, observation).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 32000000L,
    execution_bytes: 134217728L,
  }).unwrap()
  (@strategy.open_captured_dag(graph, source, ledger).unwrap(), issuer)
}

///|
test "resident Source publication exports the retained acquisition without Compute" {
  let (run, issuer) = resident_source_captured_fixture()
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_result_task(graph, 0), Some(0))
  assert_eq(@strategy.graph_task_count(graph), 1)
  assert_eq(@strategy.next_captured_task(run), None)
  let output = @publication_host.prepare_captured_result_publication_export(
    run,
    0,
    native_publication_export_limits(),
  ).unwrap()
  let body = StringBuilder()
  // Closing the ordinary task port must not revoke the publication pin.
  @strategy.close_captured_task_output(run, 0)
  while output.next().unwrap() is Some(chunk) {
    body.write_string(chunk)
  }
  body.write_string(output.finish().unwrap())
  // Without authored or inherited order, the checked Result orders its
  // projected numeric field ascending. Physical acquisition arrival [3, 1, 2]
  // does not supply publication order; the filter excludes 1.
  assert_eq(body.to_string(), "[{\"id\":2},{\"id\":3}]")
  assert_eq(output.result_fields().unwrap(), ["id"])
  // Export reads the existing acquisition; it cannot advance the next
  // checked Compute task or turn that task into the acquired producer.
  assert_eq(@strategy.next_captured_task(run), None)
  output.cancel()
  output.cancel()
  @strategy.stop_captured_dag(run)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
  @mock.close_mock_query_issuer(issuer)
}

///|
test "resident Source publication bounds release failed export pins" {
  let (run, issuer) = resident_source_captured_fixture()
  assert_true(
    @publication_host.prepare_captured_result_publication_export(
      run,
      0,
      { ..native_publication_export_limits(), max_rows: 1, },
      max_pins=1,
    )
    is Err(_),
  )
  // The failed preparation must release its only pin so another exact
  // consumer can acquire it without rerunning acquisition.
  let output = @publication_host.prepare_captured_result_publication_export(
    run,
    0,
    native_publication_export_limits(),
    max_pins=1,
  ).unwrap()
  output.cancel()
  let retry = @publication_host.prepare_captured_result_publication_export(
    run,
    0,
    native_publication_export_limits(),
    max_pins=1,
  ).unwrap()
  retry.cancel()
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}

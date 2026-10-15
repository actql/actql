///|
// The original independent composite JSON control is legal before any Source
// read. Its two installed budgets must retain the same checked requirements.
test "original composite Vector Sources prepare the installed multi-capture ledger" {
  let (environment, context) = composite_vector_source_preparation_context()
  let original = @local_input.prepare_local_submitted_input(
    composite_vector_source_preparation_normal_inputs()[0],
    environment,
    Some(context),
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let prepared = @local_input.local_prepared_program(
    @local_input.local_submitted_preparation_input(original),
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_captured_prefix(graph), 2)
  let (registry, values, fragment, ordered) = acquired_serialization_contracts()
  let owner = @strategy.graph_task_owner(graph, 2).unwrap()
  let sequence = @lower.prepare_sequence(
    owner,
    @publication_host.prepared_client_values_sequence_limits(prepared),
  ).unwrap()
  let mut found_sort = false
  for step in 0..<@lower.sequence_count(sequence) {
    if @lower.sequence_step(sequence, step) is Some(@lower.RowStep(kernel)) &&
      @lower.kernel_body(kernel) is @lower.StableSort(_) {
      found_sort = true
      // Authored scalar terms stay scalar. Only the original two checked
      // composite identities supply the compiler-appended canonical terms.
      assert_eq(@lower.kernel_sort_term_count(kernel), 4)
      assert_eq(@lower.kernel_sort_term_positional_count(kernel, 0), 0)
      assert_eq(@lower.kernel_sort_term_positional_count(kernel, 1), 0)
      assert_eq(@lower.kernel_sort_term_positional_count(kernel, 2), 2)
      assert_eq(@lower.kernel_sort_term_positional_count(kernel, 3), 2)
      assert_eq(@lower.kernel_sort_term_positional_count(kernel, -1), 0)
      assert_eq(@lower.kernel_sort_term_positional_count(kernel, 4), 0)
    }
  }
  assert_true(found_sort)
  let sequences = @client_local_host.prepare_client_local_sequences(
    prepared, registry, values, fragment, ordered,
  )
  assert_true(
    sequences is Some(_),
    msg="original composite generated sequences",
  )
  let declaration = composite_vector_source_test_declaration(true).unwrap()
  let (query, evidence) = query_evidence_test_bodies()
  let capacities = Array::makei(2, task => {
    let requirement = @client_local_host.prepare_local_query_requirement(
      prepared, task, 0, registry, values, fragment, ordered,
    ).unwrap()
    let acquisition = @row_host.prepare_row_acquisition(
      declaration,
      requirement,
      @identity.stringify_value(query, 100000, 10000, 100),
      @identity.stringify_value(evidence, 100000, 10000, 100),
    ).unwrap()
    @client_local_host.installed_row_capture_capacity(acquisition).unwrap()
  })
  let ledger = @client_local_host.prepare_multi_captured_local_installed_ledger(
    prepared,
    capacities,
    [4096L, 4096L],
    [4096L, 4096L],
    registry,
    values,
    fragment,
    ordered,
  )
  assert_true(ledger is Some(_), msg="original composite installed ledger")
  let usage = @resources.ledger_usage(ledger.unwrap())
  assert_eq(usage.attempts, 0)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

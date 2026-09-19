///|
fn local_carrier_vectors_program(variant? : String = "normalize") -> String {
  let pooled = variant == "pool" || variant == "pool_normalize"
  let source_fields = "[\"id\",\"group\",\"embedding\"]"
  let result_fields = if pooled {
    "[\"group\",\"embedding\",\"member_count\"]"
  } else {
    "[\"id\",\"embedding\"]"
  }
  let second_fields = if pooled {
    "[\"member_count\",\"embedding\",\"group\"]"
  } else {
    "[\"embedding\",\"id\"]"
  }
  let kernel = if variant == "score" {
    "{\"score_vectors\":{\"query\":[1,0],\"metric\":\"dot\"}}"
  } else if variant == "pool" {
    "{\"pool_vectors\":{\"by\":[\"group\"],\"method\":\"sum\"}}"
  } else if variant == "pool_normalize" {
    "{\"pool_vectors\":{\"by\":[\"group\"],\"method\":\"sum\"}}," +
    "{\"normalize_vectors\":true}"
  } else {
    "{\"normalize_vectors\":true}"
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
  "\"group\":{\"type\":\"number\",\"nullable\":false}," +
  "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
  "\"nullable\":false}},\"rows\":[{\"id\":1,\"group\":1," +
  "\"embedding\":[3,4]},{\"id\":2,\"group\":1," +
  "\"embedding\":[0,5]}]}," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  source_fields +
  "}}},{\"id\":\"vectors\",\"inputs\":{" +
  "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}}," +
  "\"steps\":[{\"from\":\"rows\",\"to_vectors\":{" +
  "\"id\":\"id\",\"vector\":\"embedding\"}}," +
  kernel +
  ",{\"vectors\":true,\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  result_fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"vectors\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  result_fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":" +
  result_fields +
  "}}},{" +
  "\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"vectors\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  second_fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  second_fields +
  "}}}],\"results\":{\"source\":{\"from\":{" +
  "\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn local_vector_expression_program() -> String {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"left\":{\"type\":\"vector\",\"dimensions\":2," +
    "\"nullable\":false},\"right\":{\"type\":\"vector\"," +
    "\"dimensions\":2,\"nullable\":false}}"
  let fields = "[\"id\",\"score\",\"joined\"]"
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{" +
  "\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"vectors\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{" +
  "\"id\":2,\"left\":[2,1],\"right\":[4,3]}]},\"as\":\"seed\"},{" +
  "\"from\":\"seed\",\"derive\":{\"score\":{" +
  "\"vector_score\":{\"left\":{\"field\":\"left\"}," +
  "\"right\":{\"field\":\"right\"},\"metric\":\"dot\"}}}," +
  "\"as\":\"scored\"},{\"from\":\"scored\",\"derive\":{" +
  "\"joined\":{\"vector_concat\":[{\"field\":\"right\"},{" +
  "\"field\":\"left\"}]}},\"as\":\"out\"}],\"results\":{" +
  "\"r\":{\"from\":\"out\",\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"vectors\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"vectors\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"joined\",\"score\",\"id\"],\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[" +
  "\"joined\",\"score\",\"id\"]}}}],\"results\":{\"source\":{" +
  "\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn carrier_vectors_storage_limits() -> @record_storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn run_standard_vectors_provider(variant : String) -> Unit raise {
  let pooled = variant == "pool" || variant == "pool_normalize"
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let cleanup_attempts = Ref(0)
  let provider = delayed_cleanup_provider(
    @local_veca_provider.provider(
      carrier_vectors_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        sequences[1],
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    ),
    cleanup_attempts,
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()

  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
  )
  let values_rows = local_managed_test_rows(values_ops)
  let vectors_live = Ref(true)
  let (vectors_ops, vectors) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [values_rows],
    2,
    vectors_live,
  )
  let vector_rows = local_managed_test_rows(vectors_ops)
  let expected_rows = if pooled { 1 } else { 2 }
  assert_eq(vector_rows.length(), expected_rows)
  if variant == "pool_normalize" {
    assert_true(
      vector_rows[0].contains(
        "\"embedding\":[0.3162277638912201,0.9486833214759827]",
      ),
    )
  }
  assert_true(
    vector_rows[0].contains(if pooled { "\"group\":1" } else { "\"id\":1" }),
  )
  assert_true(vector_rows[0].contains("\"embedding\""))

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [vectors],
    [vector_rows],
    3,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [vectors],
    [vector_rows],
    4,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops).length(), expected_rows)
  assert_eq(local_managed_test_rows(second_ops).length(), expected_rows)

  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(vectors))

  second_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  vectors_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (vectors_ops.close)()
  assert_false((vectors_ops.cleanup_refresh)())
  assert_true((vectors_ops.cleanup_refresh)())
  assert_eq(cleanup_attempts.val, 2)
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "standard Host runs bounded vector normalization provider" {
  run_standard_vectors_provider("normalize")
}

///|
test "standard Host runs bounded vector scoring provider" {
  run_standard_vectors_provider("score")
}

///|
test "standard Host runs bounded vector pooling provider" {
  run_standard_vectors_provider("pool")
}

///|
test "standard Host composes pooling and normalization" {
  run_standard_vectors_provider("pool_normalize")
}

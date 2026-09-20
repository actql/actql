///|
fn local_carrier_vectors_program(variant? : String = "normalize") -> String {
  if variant == "ranking_max" ||
    variant == "ranking_weighted" ||
    variant == "ranking_rrf" ||
    variant == "ranking_rrf_repeated" {
    return local_vector_ranking_program(variant)
  }
  if variant == "nearest" ||
    variant == "nearest_cosine" ||
    variant == "nearest_l2" ||
    variant == "nearest_inferred" ||
    variant == "nearest_k1" ||
    variant == "nearest_klarge" ||
    variant == "nearest_empty" ||
    variant == "nearest_empty_queries" {
    return local_vector_nearest_program(variant)
  }
  let relation_pool = variant == "relation_pool" ||
    variant == "relation_pool_composite"
  let pooled = variant == "pool" || variant == "pool_normalize" || relation_pool
  let source_fields = "[\"id\",\"code\",\"group\",\"embedding\"]"
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
  let source_tail = if relation_pool {
    let keys = if variant == "relation_pool_composite" {
      "[\"id\",\"code\"]"
    } else {
      "[\"id\"]"
    }
    ", {\"from\":\"out\",\"assert_rows\":{\"unique_by\":" +
    keys +
    "}," +
    "\"as\":\"keyed\"}"
  } else {
    ""
  }
  let source_result = if relation_pool { "keyed" } else { "out" }
  let vector_prefix = if relation_pool {
    ""
  } else {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}},"
  }
  let relation_vector = if relation_pool {
    "{\"pool_vectors\":{\"vector\":\"embedding\"," +
    "\"by\":[\"group\"],\"method\":\"sum\"}}"
  } else {
    kernel
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
  "\"code\":{\"type\":\"string\",\"nullable\":false}," +
  "\"group\":{\"type\":\"number\",\"nullable\":false}," +
  "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
  "\"nullable\":false}},\"rows\":[{\"id\":1,\"code\":\"😀\"," +
  "\"group\":1,\"embedding\":[3,4]},{\"id\":2,\"code\":\"é\"," +
  "\"group\":1," +
  "\"embedding\":[0,5]}]}," +
  "\"as\":\"out\"}" +
  source_tail +
  "],\"results\":{\"r\":{\"from\":\"" +
  source_result +
  "\"," +
  "\"fields\":" +
  source_fields +
  "}}},{\"id\":\"vectors\",\"inputs\":{" +
  "\"rows\":{\"result\":{\"stage\":\"values\",\"result\":\"r\"}}}," +
  "\"steps\":[" +
  (if variant == "normalize_shared" {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"source\"},{\"from\":\"source\"," +
    "\"normalize_vectors\":true,\"as\":\"normalized\"}," +
    "{\"from\":\"normalized\",\"score_vectors\":{" +
    "\"query\":[1,0],\"metric\":\"dot\"}," +
    "\"as\":\"same_carrier\"},{\"from\":\"normalized\"," +
    "\"vectors\":true,\"as\":\"out\"}"
  } else {
    vector_prefix + relation_vector + ",{\"vectors\":true,\"as\":\"out\"}"
  }) +
  "]," +
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
fn local_vector_ranking_program(variant : String) -> String {
  let rrf = variant == "ranking_rrf" || variant == "ranking_rrf_repeated"
  let repeated = variant == "ranking_rrf_repeated"
  let schema = if rrf {
    "{\"q\":{\"type\":\"number\",\"nullable\":false}," +
    "\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"rank\":{\"type\":\"number\",\"nullable\":false}}"
  } else {
    "{\"q\":{\"type\":\"number\",\"nullable\":false}," +
    "\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"score\":{\"type\":\"number\",\"nullable\":false}}"
  }
  let left_rows = if rrf {
    "[{\"q\":1,\"id\":1,\"rank\":1},{\"q\":1,\"id\":2," +
    "\"rank\":2},{\"q\":2,\"id\":1,\"rank\":1}]"
  } else {
    "[{\"q\":1,\"id\":1,\"score\":0.75},{\"q\":1," +
    "\"id\":2,\"score\":0.5},{\"q\":2,\"id\":1," +
    "\"score\":0.25}]"
  }
  let right_rows = if rrf {
    "[{\"q\":1,\"id\":3,\"rank\":1},{\"q\":1,\"id\":1," +
    "\"rank\":2},{\"q\":2,\"id\":1,\"rank\":1}]"
  } else {
    "[{\"q\":1,\"id\":1,\"score\":0.5},{\"q\":1," +
    "\"id\":3,\"score\":0.25},{\"q\":2,\"id\":1," +
    "\"score\":0.75}]"
  }
  let options = if rrf {
    "\"rank\":\"rank\",\"score_policy\":{\"rrf\":{" +
    "\"rank_constant\":1,\"weights\":" +
    (if repeated { "[1,1,2]" } else { "[1,1]" }) +
    ",\"rank_window\":2}}"
  } else {
    let policy = if variant == "ranking_weighted" {
      "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"
    } else {
      "\"max\""
    }
    "\"score\":\"score\",\"score_policy\":" +
    policy +
    ",\"score_contract\":{\"domain\":\"unit.v1\"," +
    "\"range\":[0,1],\"normalization\":\"unit.v1\"}"
  }
  let fields = "[\"q\",\"id\",\"score\",\"rank\"]"
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{" +
  "\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{\"r\":{" +
  "\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"left\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":" +
  left_rows +
  "},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  (if rrf { "[\"q\",\"id\",\"rank\"]" } else { "[\"q\",\"id\",\"score\"]" }) +
  "}}},{\"id\":\"right\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":" +
  right_rows +
  "},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  (if rrf { "[\"q\",\"id\",\"rank\"]" } else { "[\"q\",\"id\",\"score\"]" }) +
  "}}},{\"id\":\"fusion\",\"inputs\":{\"left\":{\"result\":{" +
  "\"stage\":\"left\",\"result\":\"r\"}},\"right\":{\"result\":{" +
  "\"stage\":\"right\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"from\":\"left\",\"merge_rankings\":{\"with\":" +
  (if repeated {
    "[\"right\",\"right\"]"
  } else if rrf {
    "[\"right\"]"
  } else {
    "\"right\""
  }) +
  ",\"by\":[\"q\"],\"candidate\":\"id\"," +
  options +
  ",\"k\":2},\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"fusion\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"fusion\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"rank\",\"score\",\"id\",\"q\"]," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"rank\",\"score\",\"id\",\"q\"]}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\"," +
  "\"result\":\"r\"}}}}"
}

///|
fn local_vector_nearest_program(variant : String) -> String {
  let inferred = variant == "nearest_inferred"
  let identity_type = if inferred { "string" } else { "number" }
  let vector_schema = "{\"id\":{\"type\":\"" +
    identity_type +
    "\",\"nullable\":false}," +
    "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
    "\"nullable\":false}}"
  let ranking_fields = "[\"query_id\",\"candidate_id\",\"score\",\"rank\"]"
  let candidate_rows = if variant == "nearest_empty" {
    "[]"
  } else if inferred {
    "[{\"id\":\"b\",\"embedding\":[1,0]},{\"id\":\"a\"," +
    "\"embedding\":[1,0]},{\"id\":\"c\",\"embedding\":[0,1]}]"
  } else {
    "[{\"id\":2,\"embedding\":[1,0]},{\"id\":1," +
    "\"embedding\":[1,0]},{\"id\":3,\"embedding\":[0,1]}]"
  }
  let query_rows = if variant == "nearest_empty_queries" {
    "[]"
  } else if inferred {
    "[{\"id\":\"t\",\"embedding\":[1,0]},{\"id\":\"q\"," +
    "\"embedding\":[0,1]}]"
  } else {
    "[{\"id\":20,\"embedding\":[1,0]},{\"id\":10," + "\"embedding\":[0,1]}]"
  }
  let roles = if inferred {
    ""
  } else {
    "\"candidate_id\":\"id\",\"candidate_vector\":\"embedding\"," +
    "\"query_id\":\"id\",\"query_vector\":\"embedding\","
  }
  let identity_tail = if inferred {
    ",{\"from\":\"out\",\"assert_rows\":{\"unique_by\":[\"id\"]}," +
    "\"as\":\"keyed\"}"
  } else {
    ""
  }
  let source_result = if inferred { "keyed" } else { "out" }
  let metric = if variant == "nearest_cosine" {
    "cosine"
  } else if variant == "nearest_l2" {
    "l2"
  } else {
    "dot"
  }
  let k = if variant == "nearest_k1" {
    "1"
  } else if variant == "nearest_klarge" {
    "5"
  } else {
    "2"
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{" +
  "\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"candidates\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  vector_schema +
  ",\"rows\":" +
  candidate_rows +
  "},\"as\":\"out\"}" +
  identity_tail +
  "],\"results\":{\"r\":{\"from\":\"" +
  source_result +
  "\",\"fields\":[\"id\",\"embedding\"]}}},{" +
  "\"id\":\"queries\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  vector_schema +
  ",\"rows\":" +
  query_rows +
  "},\"as\":\"out\"}" +
  identity_tail +
  "],\"results\":{\"r\":{\"from\":\"" +
  source_result +
  "\",\"fields\":[\"id\"," +
  "\"embedding\"]}}},{\"id\":\"nearest\",\"inputs\":{" +
  "\"candidates\":{\"result\":{\"stage\":\"candidates\"," +
  "\"result\":\"r\"}},\"queries\":{\"result\":{\"stage\":\"queries\"," +
  "\"result\":\"r\"}}},\"steps\":[{\"from\":\"candidates\"," +
  "\"nearest\":{\"queries\":\"queries\"," +
  roles +
  "\"metric\":\"" +
  metric +
  "\",\"k\":" +
  k +
  "}," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  ranking_fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"nearest\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  ranking_fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  ranking_fields +
  "}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"nearest\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"rank\",\"score\",\"candidate_id\",\"query_id\"]," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"rank\",\"score\",\"candidate_id\",\"query_id\"]}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\"," +
  "\"result\":\"r\"}}}}"
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
  let relation_pool = variant == "relation_pool" ||
    variant == "relation_pool_composite"
  let pooled = variant == "pool" || variant == "pool_normalize" || relation_pool
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
    managed_publication=variant == "normalize_shared",
  )
  if variant == "normalize_shared" {
    assert_true(
      @strategy.configure_captured_managed_identity_policy(
        run, true, false, false, false,
      ),
    )
  }
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
  let vector_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (vectors_ops, vectors) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [values_rows],
    2,
    vectors_live,
    obligations=vector_obligations,
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
  if relation_pool {
    assert_true(vector_rows[0].contains("\"embedding\":[3,9]"))
    assert_true(vector_rows[0].contains("\"member_count\":2"))
  }
  assert_true(
    vector_rows[0].contains(if pooled { "\"group\":1" } else { "\"id\":1" }),
  )
  assert_true(vector_rows[0].contains("\"embedding\""))
  if variant == "normalize_shared" {
    assert_eq(vector_rows, [
      "{\"code\":\"😀\",\"embedding\":[0.6000000238418579,0.800000011920929],\"group\":1,\"id\":1}",
      "{\"code\":\"é\",\"embedding\":[0,1],\"group\":1,\"id\":2}",
    ])
    let published = @execution.managed_obligations_identities(
      vector_obligations,
    ).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(published.length(), 1)
    assert_eq(
      @execution.managed_completed_identity_requirement_status(
        vectors,
        published[0],
      ),
      Some(
        @execution.EstablishedSourceRetained(
          @execution.logical_relation_canonical_contract_cid(),
          "sha256:4dcae0e6f3da74f61a0e6c3177bae62ac85ed202e6af740c4f672ffc61c2623a",
        ),
      ),
    )
  }

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
fn run_standard_nearest_provider(variant : String) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 134217728L,
    }),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[3],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
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

  let candidates_live = Ref(true)
  let (candidates_ops, candidates) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    candidates_live,
  )
  let candidate_rows = local_managed_test_rows(candidates_ops)
  let queries_live = Ref(true)
  let (queries_ops, queries) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    queries_live,
  )
  let query_rows = local_managed_test_rows(queries_ops)
  let nearest_live = Ref(true)
  let (nearest_ops, nearest) = run_local_managed_test_task(
    installed,
    run,
    3,
    [candidates, queries],
    [candidate_rows, query_rows],
    3,
    nearest_live,
  )
  let nearest_rows = local_managed_test_rows(nearest_ops)
  let expected = if variant == "nearest_empty" ||
    variant == "nearest_empty_queries" {
    []
  } else if variant == "nearest_k1" {
    [
      "{\"candidate_id\":3,\"query_id\":10,\"rank\":1,\"score\":1}", "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":1}",
    ]
  } else if variant == "nearest_klarge" {
    [
      "{\"candidate_id\":3,\"query_id\":10,\"rank\":1,\"score\":1}", "{\"candidate_id\":1,\"query_id\":10,\"rank\":2,\"score\":0}",
      "{\"candidate_id\":2,\"query_id\":10,\"rank\":3,\"score\":0}", "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":1}",
      "{\"candidate_id\":2,\"query_id\":20,\"rank\":2,\"score\":1}", "{\"candidate_id\":3,\"query_id\":20,\"rank\":3,\"score\":0}",
    ]
  } else if variant == "nearest_inferred" {
    [
      "{\"candidate_id\":\"c\",\"query_id\":\"q\"," + "\"rank\":1,\"score\":1}",
      "{\"candidate_id\":\"a\",\"query_id\":\"q\"," + "\"rank\":2,\"score\":0}",
      "{\"candidate_id\":\"a\",\"query_id\":\"t\"," + "\"rank\":1,\"score\":1}",
      "{\"candidate_id\":\"b\",\"query_id\":\"t\"," + "\"rank\":2,\"score\":1}",
    ]
  } else if variant == "nearest_l2" {
    [
      "{\"candidate_id\":3,\"query_id\":10,\"rank\":1,\"score\":0}",
      "{\"candidate_id\":1,\"query_id\":10,\"rank\":2," +
      "\"score\":-1.4142135623730951}",
      "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":0}",
      "{\"candidate_id\":2,\"query_id\":20,\"rank\":2,\"score\":0}",
    ]
  } else {
    [
      "{\"candidate_id\":3,\"query_id\":10,\"rank\":1,\"score\":1}", "{\"candidate_id\":1,\"query_id\":10,\"rank\":2,\"score\":0}",
      "{\"candidate_id\":1,\"query_id\":20,\"rank\":1,\"score\":1}", "{\"candidate_id\":2,\"query_id\":20,\"rank\":2,\"score\":1}",
    ]
  }
  assert_eq(nearest_rows, expected)

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [nearest],
    [nearest_rows],
    4,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [nearest],
    [nearest_rows],
    5,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops).length(), expected.length())
  assert_eq(local_managed_test_rows(second_ops).length(), expected.length())

  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(nearest))

  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  nearest_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (nearest_ops.close)()
  (nearest_ops.cleanup_refresh)() |> ignore
  queries_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (queries_ops.close)()
  (queries_ops.cleanup_refresh)() |> ignore
  candidates_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (candidates_ops.close)()
  (candidates_ops.cleanup_refresh)() |> ignore
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
fn run_standard_ranking_provider(variant : String) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 134217728L,
    }),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[3],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
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

  let left_live = Ref(true)
  let (left_ops, left) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    left_live,
  )
  let left_rows = local_managed_test_rows(left_ops)
  let right_live = Ref(true)
  let (right_ops, right) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    right_live,
  )
  let right_rows = local_managed_test_rows(right_ops)
  let fusion_live = Ref(true)
  let (fusion_ops, fusion) = run_local_managed_test_task(
    installed,
    run,
    3,
    [left, right],
    [left_rows, right_rows],
    3,
    fusion_live,
  )
  let fused_rows = local_managed_test_rows(fusion_ops)
  assert_eq(fused_rows.length(), 3)
  assert_true(fused_rows[0].contains("\"id\":1"))
  assert_true(fused_rows[0].contains("\"q\":1"))
  assert_true(fused_rows[0].contains("\"rank\":1"))
  if variant == "ranking_rrf" || variant == "ranking_rrf_repeated" {
    assert_true(fused_rows[1].contains("\"id\":3"))
  } else {
    assert_true(fused_rows[1].contains("\"id\":2"))
  }
  assert_true(fused_rows[2].contains("\"q\":2"))

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [fusion],
    [fused_rows],
    4,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [fusion],
    [fused_rows],
    5,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops).length(), fused_rows.length())
  assert_eq(local_managed_test_rows(second_ops).length(), 3)

  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(fusion))

  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  fusion_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (fusion_ops.close)()
  (fusion_ops.cleanup_refresh)() |> ignore
  right_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (right_ops.close)()
  (right_ops.cleanup_refresh)() |> ignore
  left_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (left_ops.close)()
  (left_ops.cleanup_refresh)() |> ignore
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
test "standard Host shares normalized Vectors with a Carrier consumer" {
  run_standard_vectors_provider("normalize_shared")
}

///|
test "standard Host runs RRF ranking fusion with two consumers" {
  run_standard_ranking_provider("ranking_rrf")
}

///|
test "standard Host preserves repeated RRF input occurrences" {
  run_standard_ranking_provider("ranking_rrf_repeated")
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

///|
test "standard Host pools author-visible Relation input" {
  run_standard_vectors_provider("relation_pool")
}

///|
test "standard Host encodes composite Relation pool identity" {
  run_standard_vectors_provider("relation_pool_composite")
}

///|
test "standard Host runs exact nearest with two consumers" {
  run_standard_nearest_provider("nearest")
}

///|
test "standard Host runs exact cosine nearest" {
  run_standard_nearest_provider("nearest_cosine")
}

///|
test "standard Host runs exact negative-L2 nearest" {
  run_standard_nearest_provider("nearest_l2")
}

///|
test "standard Host completes nearest Relation roles" {
  run_standard_nearest_provider("nearest_inferred")
}

///|
test "standard Host enforces nearest k prefix" {
  run_standard_nearest_provider("nearest_k1")
}

///|
test "standard Host caps nearest k at candidate count" {
  run_standard_nearest_provider("nearest_klarge")
}

///|
test "standard Host validates empty nearest corpus" {
  run_standard_nearest_provider("nearest_empty")
}

///|
test "standard Host validates empty nearest queries" {
  run_standard_nearest_provider("nearest_empty_queries")
}

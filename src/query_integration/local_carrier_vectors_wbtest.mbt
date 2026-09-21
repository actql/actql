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
  let pooled = variant == "pool" ||
    variant == "pool_normalize" ||
    variant == "pool_shared" ||
    relation_pool
  let scored = variant == "score_shared" || variant == "score_parameter"
  let source_fields = "[\"id\",\"code\",\"group\",\"embedding\"]"
  let result_fields = if pooled {
    "[\"group\",\"embedding\",\"member_count\"]"
  } else if scored {
    "[\"id\",\"embedding\",\"score\"]"
  } else {
    "[\"id\",\"embedding\"]"
  }
  let second_fields = if pooled {
    "[\"member_count\",\"embedding\",\"group\"]"
  } else if scored {
    "[\"score\",\"embedding\",\"id\"]"
  } else {
    "[\"embedding\",\"id\"]"
  }
  let kernel = if variant == "score" {
    "{\"score_vectors\":{\"query\":[1,0],\"metric\":\"dot\"}}"
  } else if variant == "score_parameter" {
    "{\"score_vectors\":{\"query\":{\"$param\":\"q\"}," + "\"metric\":\"dot\"}}"
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
  let parameters = if variant == "score_parameter" {
    "{\"minimum\":{\"type\":\"number\",\"nullable\":false}," +
    "\"q\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}," +
    "\"length\":2}}"
  } else {
    "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}"
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  parameters +
  "," +
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
  } else if variant == "score_shared" {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"source\"},{\"from\":\"source\"," +
    "\"score_vectors\":{\"query\":[0,1],\"metric\":\"dot\"}," +
    "\"as\":\"scored\"},{\"from\":\"scored\"," +
    "\"normalize_vectors\":true,\"as\":\"same_carrier\"}," +
    "{\"from\":\"scored\",\"vectors\":true,\"as\":\"out\"}"
  } else if variant == "pool_shared" {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"source\"},{\"from\":\"source\"," +
    "\"pool_vectors\":{\"by\":[\"group\"],\"method\":\"sum\"}," +
    "\"as\":\"pooled\"},{\"from\":\"pooled\"," +
    "\"normalize_vectors\":true,\"as\":\"same_carrier\"}," +
    "{\"from\":\"pooled\",\"vectors\":true,\"as\":\"out\"}"
  } else if variant == "bridge_only" {
    "{\"from\":\"rows\",\"to_vectors\":{" +
    "\"id\":\"id\",\"vector\":\"embedding\"}," +
    "\"as\":\"source\"},{\"from\":\"source\"," +
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
fn nearest_publication_cid(variant : String) -> String {
  if variant == "nearest_l2" {
    "sha256:6fd5e80b9824a60178c6d632a29a3ade2037dd531c4ab3a7731511da70341685"
  } else if variant == "nearest_inferred" {
    "sha256:9fceff97e3f1c2985ffcdb1e8167ad34c6b592525de45530dd84f7ef740aec89"
  } else if variant == "nearest_k1" {
    "sha256:cd5ca17c629007382b00c09734661c5827adfcd3c9f5e2e2efcd688ff5648d0c"
  } else if variant == "nearest_klarge" {
    "sha256:5634ee66e92ec13e0d328d95045fd9706fe46b3c879e19f5a33a18b8ec7bad46"
  } else if variant == "nearest_empty" || variant == "nearest_empty_queries" {
    "sha256:d2889f6d3b43fe20f75149d13eb0585918c94cf3a5b0520f5f9e1525b0846f3d"
  } else {
    "sha256:6d303cfa8e4881cd9d7066c505a353c00e1509ccc247bc03332331fa09e8aaff"
  }
}

///|
fn ranking_publication_cid(variant : String) -> String {
  if variant == "ranking_rrf_repeated" {
    "sha256:c899349a78ca0ef0bfea1d49f419358d615bd190ec9509e5f95d50d48514a14c"
  } else {
    "sha256:1cc59701e6c8d10ddf972c511d5f8f643bac488916a95f656f2d0c6f9f7c925a"
  }
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
  let pooled = variant == "pool" ||
    variant == "pool_normalize" ||
    variant == "pool_shared" ||
    relation_pool
  let scored = variant == "score_shared" || variant == "score_parameter"
  let (run, issuer) = captured_graph_fixture(
    local_carrier_vectors_chain=true,
    local_carrier_vectors_variant=variant,
    managed_publication=variant == "bridge_only" ||
      variant == "normalize_shared" ||
      variant == "score_shared" ||
      variant == "pool_shared",
    parameter_json=if variant == "score_parameter" {
      "{\"minimum\":1,\"q\":[0,1]}"
    } else {
      "{\"minimum\":1}"
    },
  )
  if variant == "bridge_only" ||
    variant == "normalize_shared" ||
    variant == "score_shared" ||
    variant == "pool_shared" {
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
    vector_rows[0].contains(
      if pooled {
        "\"group\":1"
      } else if scored {
        "\"id\":2"
      } else {
        "\"id\":1"
      },
    ),
  )
  assert_true(vector_rows[0].contains("\"embedding\""))
  if variant == "bridge_only" {
    assert_eq(vector_rows, [
      "{\"code\":\"😀\",\"embedding\":[3,4],\"group\":1,\"id\":1}", "{\"code\":\"é\",\"embedding\":[0,5],\"group\":1,\"id\":2}",
    ])
    let published = @execution.managed_obligations_identities(
      vector_obligations,
    ).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(published.length(), 1)
    match
      @execution.managed_completed_identity_requirement_status(
        vectors,
        published[0],
      ) {
      Some(@execution.EstablishedSourceRetained(contract, _)) =>
        assert_eq(
          contract,
          @execution.logical_relation_canonical_contract_cid(),
        )
      _ => fail("bridge output did not establish publication identity")
    }
  } else if variant == "normalize_shared" {
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
  } else if variant == "score_shared" {
    assert_eq(vector_rows, [
      "{\"code\":\"é\",\"embedding\":[0,5],\"group\":1,\"id\":2,\"score\":5}", "{\"code\":\"😀\",\"embedding\":[3,4],\"group\":1,\"id\":1,\"score\":4}",
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
          "sha256:aeb34ab94d8916124de5af23a6bf39b6eff947099c6c6fbf486763662fd794e5",
        ),
      ),
    )
  } else if variant == "pool_shared" {
    assert_eq(vector_rows, [
      "{\"embedding\":[3,9],\"group\":1,\"member_count\":2}",
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
          "sha256:b986e2eec797d867269e0bf0abbf453d05eb90d845fc5b402fc1beb50464b05f",
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
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 134217728L,
    }),
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
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
  let candidates_obligations = @strategy.captured_next_managed_obligations(
    run, 10,
  ).unwrap()
  let (candidates_ops, candidates) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    candidates_live,
    obligations=candidates_obligations,
  )
  let candidate_rows = local_managed_test_rows(candidates_ops)
  let queries_live = Ref(true)
  let queries_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (queries_ops, queries) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    queries_live,
    obligations=queries_obligations,
  )
  let query_rows = local_managed_test_rows(queries_ops)
  let nearest_live = Ref(true)
  let nearest_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (nearest_ops, nearest) = run_local_managed_test_task(
    installed,
    run,
    3,
    [candidates, queries],
    [candidate_rows, query_rows],
    3,
    nearest_live,
    obligations=nearest_obligations,
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
  let published = @execution.managed_obligations_identities(nearest_obligations).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    },
  )
  assert_eq(published.length(), 1)
  match
    @execution.managed_completed_identity_requirement_status(
      nearest,
      published[0],
    ) {
    Some(@execution.EstablishedSourceRetained(contract, cid)) => {
      assert_eq(contract, @execution.logical_relation_canonical_contract_cid())
      assert_eq(cid, nearest_publication_cid(variant))
    }
    _ => fail("nearest output did not establish publication identity")
  }

  let first_live = Ref(true)
  let first_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [nearest],
    [nearest_rows],
    4,
    first_live,
    obligations=first_obligations,
  )
  let second_live = Ref(true)
  let second_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [nearest],
    [nearest_rows],
    5,
    second_live,
    obligations=second_obligations,
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
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 134217728L,
    }),
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
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
  let left_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (left_ops, left) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    left_live,
    obligations=left_obligations,
  )
  let left_rows = local_managed_test_rows(left_ops)
  let right_live = Ref(true)
  let right_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (right_ops, right) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    right_live,
    obligations=right_obligations,
  )
  let right_rows = local_managed_test_rows(right_ops)
  let fusion_live = Ref(true)
  let fusion_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (fusion_ops, fusion) = run_local_managed_test_task(
    installed,
    run,
    3,
    [left, right],
    [left_rows, right_rows],
    3,
    fusion_live,
    obligations=fusion_obligations,
  )
  let fused_rows = local_managed_test_rows(fusion_ops)
  let expected = if variant == "ranking_rrf_repeated" {
    [
      "{\"id\":1,\"q\":1,\"rank\":1,\"score\":1.5}", "{\"id\":3,\"q\":1,\"rank\":2,\"score\":1.5}",
      "{\"id\":1,\"q\":2,\"rank\":1,\"score\":2}",
    ]
  } else {
    [
      "{\"id\":1,\"q\":1,\"rank\":1,\"score\":0.8333333333333333}", "{\"id\":3,\"q\":1,\"rank\":2,\"score\":0.5}",
      "{\"id\":1,\"q\":2,\"rank\":1,\"score\":1}",
    ]
  }
  assert_eq(fused_rows, expected)
  let published = @execution.managed_obligations_identities(fusion_obligations).filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    },
  )
  assert_eq(published.length(), 1)
  match
    @execution.managed_completed_identity_requirement_status(
      fusion,
      published[0],
    ) {
    Some(@execution.EstablishedSourceRetained(contract, cid)) => {
      assert_eq(contract, @execution.logical_relation_canonical_contract_cid())
      assert_eq(cid, ranking_publication_cid(variant))
    }
    _ => fail("ranking output did not establish publication identity")
  }

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
test "standard Host runs the vector bridge through two consumers" {
  run_standard_vectors_provider("bridge_only")
}

///|
test "standard Host shares normalized Vectors with a Carrier consumer" {
  run_standard_vectors_provider("normalize_shared")
}

///|
test "standard Host shares scored Vectors with a Carrier consumer" {
  run_standard_vectors_provider("score_shared")
}

///|
test "standard Host resolves a parameterized vector score query" {
  run_standard_vectors_provider("score_parameter")
}

///|
test "standard Host runs RRF ranking fusion with two consumers" {
  run_standard_ranking_provider("ranking_rrf")
}

///|
test "scored ranking fusion rejects undeclared value columns" {
  for variant in ["ranking_max", "ranking_weighted"] {
    let rejected = try {
      ignore(
        query_checked_program_fixture(
          local_carrier_vectors_chain=true,
          local_carrier_vectors_variant=variant,
          managed_publication=true,
        ),
      )
      false
    } catch {
      @program_check.LocalConstructionFailure::Source(_) => true
      _ => false
    }
    assert_true(rejected)
  }
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
test "standard Host shares pooled Vectors with a Carrier consumer" {
  run_standard_vectors_provider("pool_shared")
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

///|
fn direct_nearest_vector_carrier() -> @carrier_contract.Carrier {
  @carrier_contract.vectors(
    @carrier_contract.rows(
      [
        (
          @schema.Unqualified("id"),
          Some(
            @value_contract.primitive(
              @value_contract.NumberType,
              nullable=false,
            ),
          ),
        ),
        (
          @schema.Unqualified("embedding"),
          Some(@value_contract.vector_contract(2.0, nullable=false).unwrap()),
        ),
      ],
      field_set=@carrier_contract.Closed,
      max_fields=2,
      max_name_bytes=11,
    ).unwrap(),
    ids=[@schema.Unqualified("id")],
    components=@schema.Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
}

///|
fn direct_nearest_relation_carrier() -> @carrier_contract.Carrier {
  guard direct_nearest_vector_carrier()
    is @carrier_contract.VectorValue(vectors) else {
    abort("vectors")
  }
  @carrier_contract.relation(@carrier_contract.vector_records(vectors))
}

///|
fn direct_nearest_bind(
  checked : @pipeline.CheckedPipeline,
) -> @lower.BoundPrepared {
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn direct_nearest_vector_owner() -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_carriers(
      input_cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{" +
        "\"id\":\"id\",\"vector\":\"embedding\"}}]",
      ),
      [("rows", direct_nearest_relation_carrier())],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_nearest_owner(
  candidates : @lower.BoundPrepared,
  queries : @lower.BoundPrepared,
  candidate_relation? : Bool = false,
  query_relation? : Bool = false,
) -> @lower.BoundPrepared {
  let candidate_roles = if candidate_relation {
    ",\"candidate_id\":\"id\",\"candidate_vector\":\"embedding\""
  } else {
    ""
  }
  let query_roles = if query_relation {
    ",\"query_id\":\"id\",\"query_vector\":\"embedding\""
  } else {
    ""
  }
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"candidates\",\"nearest\":{" +
        "\"queries\":\"queries\",\"metric\":\"dot\",\"k\":2" +
        candidate_roles +
        query_roles +
        "}}]",
      ),
      [
        (
          "candidates",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(candidates)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "queries",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(queries)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"candidates\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_nearest_relation_owner(rows : String) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{" +
        "\"id\":{\"type\":\"number\",\"nullable\":false}," +
        "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
        "\"nullable\":false}},\"rows\":" +
        rows +
        "},\"as\":\"rows\"}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_nearest_relation_output(
  owner : @lower.BoundPrepared,
) -> @execution.CompletedOutput raise {
  let completed = @execution.execute_generated_sequence(
    task_test_generated(owner),
    [],
    compute_test_limits(),
  ).unwrap()
  @execution.completed_output(completed, @pipeline.Step(0)).unwrap()
}

///|
fn direct_ranking_carrier() -> @carrier_contract.Carrier {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  @carrier_contract.relation(
    @carrier_contract.rows(
      [
        (@schema.Unqualified("q"), Some(number)),
        (@schema.Unqualified("id"), Some(number)),
        (@schema.Unqualified("score"), Some(number)),
      ],
      field_set=@carrier_contract.Closed,
      max_fields=3,
      max_name_bytes=8,
    ).unwrap(),
  )
}

///|
fn direct_ranking_owner() -> @lower.BoundPrepared {
  let contract = "{\"domain\":\"unit.v1\",\"range\":[0,1]," +
    "\"normalization\":\"unit.v1\"}"
  let ranking = @vector.declare_ranking_score(
    input_cursor(contract),
    direct_ranking_carrier(),
    @schema.Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor("[{\"select\":[\"q\",\"id\",\"score\"]}]"),
      [("rows", @pipeline.RankingInput(ranking))],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_ranking_fusion_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
  policy : String,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"merge_rankings\":{\"with\":\"right\"," +
        "\"by\":[\"q\"],\"candidate\":\"id\"," +
        "\"score\":\"score\",\"k\":2,\"score_policy\":" +
        policy +
        ",\"score_contract\":{\"domain\":\"unit.v1\"," +
        "\"range\":[0,1],\"normalization\":\"unit.v1\"}}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"left\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_ranking_number(
  owner : @lower.BoundPrepared,
  column : Int,
  value : Double,
) -> @admitted.CheckedValue {
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let contract = @schema.field_at(schema, column).unwrap().contract
  @admitted.admit(contract, input_cursor(value.to_string()), {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 0,
  }).unwrap()
}

///|
fn direct_ranking_output(
  owner : @lower.BoundPrepared,
  rows : Array[(Double, Double, Double)],
) -> @execution.CompletedOutput raise {
  let values = @execution.prepare_admitted_output(
    owner,
    @pipeline.Step(0),
    100,
    { max_nodes: 10000, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
  ).unwrap()
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  for row in rows {
    let cells = Array::makei(@schema.field_count(schema), column => {
      let name = @schema.reference_name(
        @schema.field_at(schema, column).unwrap().name,
      )
      let value = if name == "q" {
        row.0
      } else if name == "id" {
        row.1
      } else {
        row.2
      }
      direct_ranking_number(owner, column, value)
    })
    @execution.append_admitted_output(values, cells).unwrap()
  }
  let rows = @execution.finish_admitted_output(values).unwrap()
  let completion = @execution.prepare_trusted_output_port(
    task_test_completion(owner),
    @pipeline.Step(0),
    1000,
    10000,
    (proof : @execution.AdmittedOutputRows) => {
      if physical_equal(proof, rows) {
        Some(rows)
      } else {
        None
      }
    },
  ).unwrap()
  @execution.complete_trusted_output(completion, rows).unwrap()
}

///|
fn run_direct_ranking_provider(
  policy : String,
  expected : Array[(Double, Double, Double, Double)],
) -> Unit raise {
  let left = direct_ranking_owner()
  let right = direct_ranking_owner()
  let owner = direct_ranking_fusion_owner(left, right, policy)
  let left_output = direct_ranking_output(left, [
    (1.0, 1.0, 0.75),
    (1.0, 2.0, 0.5),
    (2.0, 1.0, 0.25),
  ])
  let right_output = direct_ranking_output(right, [
    (1.0, 1.0, 0.5),
    (1.0, 3.0, 0.5),
    (2.0, 1.0, 0.75),
  ])
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("ranking fusion returned a Carrier")
      @local_connector.Failed(_, ..) => fail("ranking provider failed")
      @local_connector.Stopped(..) => fail("ranking provider stopped")
    }
  }
  let result = output.unwrap()
  let output_schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let columns = Array::make(4, -1)
  for column in 0..<@schema.field_count(output_schema) {
    let name = @schema.reference_name(
      @schema.field_at(output_schema, column).unwrap().name,
    )
    let index = if name == "q" {
      0
    } else if name == "id" {
      1
    } else if name == "rank" {
      2
    } else {
      3
    }
    columns[index] = column
  }
  assert_eq(@execution.completed_row_count(result), expected.length())
  for row, values in expected {
    for index, value in [values.0, values.1, values.2, values.3] {
      assert_true(
        @execution.completed_cell(result, row, columns[index])
        is Some(Number(actual)) &&
        actual == value,
      )
    }
  }
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
test "registered VecA provider authenticates maximum ranking scores" {
  run_direct_ranking_provider("\"max\"", [
    (1.0, 1.0, 1.0, 0.75),
    (1.0, 2.0, 2.0, 0.5),
    (2.0, 1.0, 1.0, 0.75),
  ])
}

///|
test "registered VecA provider authenticates weighted ranking scores" {
  run_direct_ranking_provider(
    "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}",
    [(1.0, 1.0, 1.0, 0.625), (1.0, 2.0, 2.0, 0.25), (2.0, 1.0, 1.0, 0.5)],
  )
}

///|
fn direct_rrf_carrier() -> @carrier_contract.Carrier {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  @carrier_contract.relation(
    @carrier_contract.rows(
      [
        (@schema.Unqualified("q"), Some(number)),
        (@schema.Unqualified("id"), Some(number)),
        (@schema.Unqualified("rank"), Some(number)),
      ],
      field_set=@carrier_contract.Closed,
      max_fields=3,
      max_name_bytes=7,
    ).unwrap(),
  )
}

///|
fn direct_rrf_owner() -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor("[{\"select\":[\"q\",\"id\",\"rank\"]}]"),
      [
        (
          "rows",
          @pipeline.RankingInput(@vector.ranking_relation(direct_rrf_carrier())),
        ),
      ],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn direct_rrf_fusion_owner(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"merge_rankings\":{\"with\":\"right\"," +
        "\"by\":[\"q\"],\"candidate\":\"id\",\"rank\":\"rank\"," +
        "\"k\":2,\"score_policy\":{\"rrf\":{" +
        "\"rank_constant\":1,\"weights\":[1,1]," +
        "\"rank_window\":2}}}}]",
      ),
      [
        (
          "left",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(left)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "right",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(right)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"left\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn run_direct_invalid_rrf(
  left_rows : Array[(Double, Double, Double)],
) -> Unit raise {
  let left = direct_rrf_owner()
  let right = direct_rrf_owner()
  let owner = direct_rrf_fusion_owner(left, right)
  let left_output = direct_ranking_output(left, left_rows)
  let right_output = direct_ranking_output(right, [
    (1.0, 3.0, 1.0),
    (1.0, 1.0, 2.0),
  ])
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, left, left_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 1, right, right_output).unwrap(),
      1000,
      10000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut failed = false
  while !failed {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Failed(_, ..) => failed = true
      @local_connector.Complete(_, ..) => fail("invalid RRF completed")
      @local_connector.CarrierComplete(_, ..) =>
        fail("invalid RRF returned a Carrier")
      @local_connector.Stopped(..) => fail("invalid RRF stopped")
    }
  }
  assert_true(@execution.completed_output_available(left_output))
  assert_true(@execution.completed_output_available(right_output))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
test "registered VecA provider rejects duplicate RRF candidates" {
  run_direct_invalid_rrf([(1.0, 1.0, 1.0), (1.0, 1.0, 2.0)])
}

///|
test "registered VecA provider rejects noncontiguous RRF ranks" {
  run_direct_invalid_rrf([(1.0, 1.0, 1.0), (1.0, 2.0, 3.0)])
}

///|
fn run_direct_nearest_provider(
  owner : @lower.BoundPrepared,
  inputs : Array[@local_connector.ManagedProviderInput],
) -> Unit raise {
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider, generated, inputs, 10, 1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("nearest returned a Carrier")
      @local_connector.Failed(_, ..) => fail("nearest provider failed")
      @local_connector.Stopped(..) => fail("nearest provider stopped")
    }
  }
  let result = output.unwrap()
  assert_eq(@execution.completed_row_count(result), 4)
  assert_true(@execution.completed_cell(result, 0, 0) is Some(Number(3.0)))
  assert_true(@execution.completed_cell(result, 0, 1) is Some(Number(10.0)))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
}

///|
fn direct_nearest_number(value : Double) -> @admitted.CheckedValue {
  @admitted.admit(
    @value_contract.primitive(@value_contract.NumberType, nullable=false),
    input_cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn direct_nearest_vector(text : String) -> @admitted.CheckedValue {
  @admitted.admit(
    @value_contract.vector_contract(2.0, nullable=false).unwrap(),
    input_cursor(text),
    { max_nodes: 3, max_depth: 2, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn direct_nearest_material(
  owner : @lower.BoundPrepared,
  records : Array[(Double, String)],
) -> @carrier_runtime.Material {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    carrier_vectors_storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  for record in records {
    @records.append_record(output, [
      (@schema.Unqualified("id"), direct_nearest_number(record.0)),
      (@schema.Unqualified("embedding"), direct_nearest_vector(record.1)),
    ]).unwrap()
  }
  @records.completed_material(@records.finish_output(output).unwrap()).unwrap()
}

///|
test "registered VecA provider consumes exact Vectors inputs" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = direct_nearest_material(candidates, [
    (2.0, "[1,0]"),
    (1.0, "[1,0]"),
    (3.0, "[0,1]"),
  ])
  let query_material = direct_nearest_material(queries, [
    (20.0, "[1,0]"),
    (10.0, "[0,1]"),
  ])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  run_direct_nearest_provider(owner, [
    @local_connector.managed_provider_carrier_input(candidate_view),
    @local_connector.managed_provider_carrier_input(query_view),
  ])
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "registered VecA provider rejects reversed Vectors bindings" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = direct_nearest_material(candidates, [(1.0, "[1,0]")])
  let query_material = direct_nearest_material(queries, [(10.0, "[1,0]")])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  let generated = task_test_generated(owner)
  let limits = dispatch_test_limits()
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(query_view),
      @local_connector.managed_provider_carrier_input(candidate_view),
    ],
    10,
    1000,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(execution, 1).unwrap()
    is @local_connector.Failed(_),
  )
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "registered VecA provider consumes Relation and Vectors inputs" {
  let candidates = direct_nearest_relation_owner(
    "[{\"id\":2,\"embedding\":[1,0]}," +
    "{\"id\":1,\"embedding\":[1,0]}," +
    "{\"id\":3,\"embedding\":[0,1]}]",
  )
  let queries = direct_nearest_vector_owner()
  let owner = direct_nearest_owner(candidates, queries, candidate_relation=true)
  let candidate_output = direct_nearest_relation_output(candidates)
  let candidate_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, candidates, candidate_output).unwrap(),
    10,
    1000,
  ).unwrap()
  let query_material = direct_nearest_material(queries, [
    (20.0, "[1,0]"),
    (10.0, "[0,1]"),
  ])
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  run_direct_nearest_provider(owner, [
    @local_connector.managed_provider_relation_input(candidate_read),
    @local_connector.managed_provider_carrier_input(query_view),
  ])
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "registered VecA provider consumes Vectors and Relation inputs" {
  let candidates = direct_nearest_vector_owner()
  let queries = direct_nearest_relation_owner(
    "[{\"id\":20,\"embedding\":[1,0]}," + "{\"id\":10,\"embedding\":[0,1]}]",
  )
  let owner = direct_nearest_owner(candidates, queries, query_relation=true)
  let candidate_material = direct_nearest_material(candidates, [
    (2.0, "[1,0]"),
    (1.0, "[1,0]"),
    (3.0, "[0,1]"),
  ])
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_output = direct_nearest_relation_output(queries)
  let query_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, queries, query_output).unwrap(),
    10,
    1000,
  ).unwrap()
  run_direct_nearest_provider(owner, [
    @local_connector.managed_provider_carrier_input(candidate_view),
    @local_connector.managed_provider_relation_input(query_read),
  ])
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
}

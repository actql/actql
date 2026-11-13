///|
fn runtime_requirements_union_prepared(
  sql? : String? = None,
) -> @publication_host.PreparedClientProgram raise {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("packaged Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  ).unwrap()
  if sql is Some(text) {
    let context = @frontend.bind_query_context([], cid).unwrap()
    let original = @frontend.lower(text, @frontend.Sql, Some(context)).unwrap()
    return @publication_host.prepare_parsed_effect_free_client_program(
      original.program.unwrap(),
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
  }
  @publication_host.prepare_effect_free_client_program(
    "{\"version\":\"actql/0.1\",\"id\":\"source-free-requirements\",\"stages\":[{\"id\":\"source\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1},{\"id\":2}]},\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}}}}",
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "managed runtime UNION requirements follow checked demand beyond fixed slots" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let policy = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  for branches in [7, 8, 9, 17] {
    let selects : Array[String] = []
    for index in 0..<branches {
      selects.push("SELECT \{index} AS v")
    }
    let prepared = runtime_requirements_union_prepared(
      sql=Some(
        "WITH t AS (" +
        selects.join(" UNION ALL ") +
        ") SELECT SUM(v) AS n FROM t",
      ),
    )
    let original = prepare_source_free_runtime_requirements(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    let needed = original.maximum_limits()
    assert_eq(needed.attempts, 4 * branches + 1)
    assert_eq(needed.holdings, needed.attempts)
    assert_true(needed.attempts <= policy.attempts)
    assert_true(needed.transfer_bytes <= policy.transfer_bytes)
    assert_eq(needed.retained_bytes, policy.retained_bytes)
    assert_eq(needed.execution_bytes, policy.execution_bytes)
    assert_true(original.simultaneous_limits() is None)
    assert_true(
      original.matches(
        prepared,
        contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ),
    )
    // Preparing demand neither issues nor enlarges a Ledger.
    let small = @resources.create_ledger({
      ..needed,
      attempts: 1,
      holdings: 1,
      retained_bytes: 1L,
      execution_bytes: 1L,
    }).unwrap()
    assert_eq(@resources.ledger_usage(small).attempts, 0)
    assert_eq(@resources.ledger_usage(small).held_bytes, 0L)
    assert_true(
      @resources.reserve_attempt(small, 0L, 2L, 0L) is Err(RetentionLimit),
    )
    assert_eq(@resources.ledger_usage(small).attempts, 0)
    let attempt = @resources.reserve_attempt(small, 0L, 1L, 1L).unwrap()
    @resources.consume_reserved_attempt(small, attempt).unwrap()
    @resources.settle_reservation(small, attempt).unwrap()
    assert_eq(@resources.ledger_usage(small).attempts, 1)
    assert_true(
      @resources.reserve_attempt(small, 0L, 0L, 0L) is Err(AttemptLimit),
    )
  }
}

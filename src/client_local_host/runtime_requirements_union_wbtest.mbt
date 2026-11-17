///|
fn runtime_requirements_union_prepared(
  sql? : String? = None,
  source_json? : String? = None,
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
  if source_json is Some(source) {
    return @publication_host.prepare_effect_free_client_program(
      source,
      Json,
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

///|
// The failing ordinary CLI SQL, with the same installed requirements and
// finite Ledger. This does not stand in for Native service/Run admission.
fn runtime_number_group_execute(
  prepared : @publication_host.PreparedClientProgram,
  expected : Array[Json],
  description : String,
) -> Unit raise {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let requirements = prepare_source_free_runtime_requirements_result(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let limits = requirements.maximum_limits()
  assert_eq(limits.execution_bytes, 536870912L)
  let ledger = @resources.create_ledger(limits).unwrap()
  let setup = open_source_free_local_retained_host_on_ledger(
    prepared,
    ledger,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    requirements=Some(requirements),
  ).unwrap()
  let output = match
    execute_source_free_local_tasks_guarded(
      setup,
      16,
      requirements.finalization_round_limit(prepared).unwrap(),
      () => true,
    ) {
    Ok(value) => value
    Err(failure) => {
      let issue = match local_values_execution_failure_issue(failure) {
        Driver(ExecutionCapacityRefusal(original, needed, available, policy)) =>
          "Driver/ExecutionCapacityRefusal/" +
          @debug.to_string((original, needed, available, policy))
        Driver(Execution(@strategy.Physical(original))) =>
          "Driver/Execution/Physical/" + @debug.to_string(original)
        Driver(
          Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.LogicalRows(original))
            )
          )
        ) =>
          "Driver/Configuration/Execution/LogicalRows/" +
          @debug.to_string((step, original))
        Driver(
          Configuration(
            @connector.Execution(@execution.Capture(step, original))
          )
        ) =>
          "Driver/Configuration/Execution/Capture/" +
          @debug.to_string((step, original))
        Driver(Configuration(_)) => "Driver/Configuration/other"
        Driver(Preparation(_)) => "Driver/Preparation"
        Driver(Execution(_)) => "Driver/Execution/other"
        Driver(ManagedValues(_)) => "Driver/ManagedValues"
        Driver(ManagedCopy(original)) =>
          "Driver/ManagedCopy/" + @debug.to_string(original)
        Driver(ManagedRetention(original)) =>
          "Driver/ManagedRetention/" + @debug.to_string(original)
        Driver(_) => "Driver/other"
        _ => "non-Driver"
      }
      if !retry_local_values_execution_failure_cleanup(failure) {
        fail("ordinary grouped cleanup pending; original refusal: " + issue)
      }
      fail(
        "ordinary grouped original refused: " +
        issue +
        "; original input: " +
        description,
      )
    }
  }
  let rows = output.rows().unwrap().map(row => @json.parse(row))
  assert_eq(rows, expected)
  assert_true(output.close())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
fn runtime_number_group_case(
  query : String,
  expected : Array[Json],
) -> Unit raise {
  runtime_number_group_execute(
    runtime_requirements_union_prepared(sql=Some(query)),
    expected,
    query,
  )
}

///|
test "ordinary grouped numeric SQL executes its original retained task chain" {
  runtime_number_group_case(
    "WITH x AS (SELECT 'a' AS bucket, 1 AS n UNION ALL SELECT 'a' AS bucket, 2 AS n UNION ALL SELECT 'b' AS bucket, 4 AS n) SELECT bucket, SUM(n) AS total, AVG(n) AS average FROM x GROUP BY bucket ORDER BY bucket",
    [
      @json.parse("{\"bucket\":\"a\",\"total\":3,\"average\":1.5}"),
      @json.parse("{\"bucket\":\"b\",\"total\":4,\"average\":4}"),
    ],
  )
}

///|
test "ordinary direct Number groups retain empty and NULL aggregate semantics" {
  for
    query in [
      "WITH x AS (SELECT 1 AS n WHERE FALSE) SELECT SUM(n) AS total, AVG(n) AS average FROM x",
      "WITH x AS (SELECT CAST(NULL AS NUMBER) AS n UNION ALL SELECT CAST(NULL AS NUMBER) AS n) SELECT SUM(n) AS total, AVG(n) AS average FROM x",
    ] {
    runtime_number_group_case(query, [
      @json.parse("{\"total\":null,\"average\":null}"),
    ])
  }
}

///|
test "ordinary COUNT identities retain anonymous UNION and PIVOT rows within the original budget" {
  runtime_number_group_case(
    "(SELECT COUNT(*) AS sales, COUNT(CAST(NULL AS FLOAT64)) AS other, 'Q1' AS quarter UNION ALL SELECT COUNT(*), COUNT(CAST(NULL AS FLOAT64)), 'Q2') |> PIVOT(MAX(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))",
    [@json.parse("{\"other\":0,\"second\":1,\"first\":1}")],
  )
}

///|
test "ordinary PIVOT preserves unbounded-schema text keys duplicates and NULL values" {
  let source =
    #|{"version":"actql/0.1","id":"fixture.pipe_pivot","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"product":{"type":"string","nullable":false},"sales":{"type":"number","nullable":true},"quarter":{"type":"string","nullable":false}},"rows":[{"product":"kale","sales":51,"quarter":"Q1"},{"product":"kale","sales":51,"quarter":"Q1"},{"product":"kale","sales":null,"quarter":"Q2"}]},"as":"sales"},{"from":"sales","pivot":{"index":["product"],"column":"quarter","value":"sales","values":["Q2","Q1"],"aggregate":"count"}},{"select":["product",{"second":"Q2"},{"first":"Q1"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["product","second","first"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  runtime_number_group_execute(
    runtime_requirements_union_prepared(source_json=Some(source)),
    [@json.parse("{\"product\":\"kale\",\"second\":0,\"first\":2}")],
    "original duplicate-null JSON PIVOT",
  )
}

///|
test "ordinary filtered subquery LEFT JOIN preserves missing-side NULL under the original budget" {
  let source =
    #|{"id":"fixture.filtered_subquery_join","results":{"answer":{"from":{"result":"rows","stage":"main"}}},"stages":[{"id":"main","inputs":{},"results":{"rows":{"fields":["a","d"],"from":"aql_join_output_7"}},"steps":[{"as":"aql_script_seed_3","values":{"rows":[{"a":1,"b":"x"},{"a":1,"b":"x"},{"a":2,"b":"y"},{"a":null,"b":"n"}],"schema":{"a":{"nullable":true,"type":"number"},"b":{"nullable":false,"type":"string"}}}},{"as":"aql_script_cte_2","from":"aql_script_seed_3","select":["a","b"]},{"as":"aql_script_seed_5","values":{"rows":[{"c":1,"d":"x"},{"c":3,"d":"z"},{"c":null,"d":"n"}],"schema":{"c":{"nullable":true,"type":"number"},"d":{"nullable":false,"type":"string"}}}},{"as":"aql_script_cte_4","from":"aql_script_seed_5","select":["c","d"]},{"as":"aql_join_prefiltered_6","filter":{"gt":[{"field":"a"},{"literal":1}]},"from":"aql_script_cte_2"},{"as":"aql_join_output_7","from":"aql_join_prefiltered_6","join":{"kind":"left","max_output_rows":1000,"on":[{"left":"a","right":"c"}],"select":{"a":"left.a","d":"right.d"},"with":"aql_script_cte_4"}}]}],"version":"actql/0.1"}
  runtime_number_group_execute(
    runtime_requirements_union_prepared(source_json=Some(source)),
    [@json.parse("{\"a\":2,\"d\":null}")],
    "original filtered subquery LEFT JOIN",
  )
}

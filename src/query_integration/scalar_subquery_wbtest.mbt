///|
fn scalar_subquery_retained_fixture(
  text : String,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("original product Environment evidence")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = @publication_host.client_standard_program_preparation_limits()
  let lexical : @snowflake_query_syntax.LexicalLimits = {
    max_source_bytes: 10000,
    max_tokens: 1000,
    max_literal_bytes: 10000,
    max_work: 20000,
  }
  let query = @snowflake_query_syntax.parse_query(text, {
    lexical,
    expression: { lexical, max_nodes: 1000, max_depth: 100, max_work: 10000, },
    max_syntax_nodes: 1000,
    max_cte_count: 20,
    max_work: 20000,
  }).unwrap()
  let input = limits.checking.input
  let program = @snowflake_query_program.compile(
    query,
    {
      program_id: "scalar-subquery",
      stage_id: "main",
      stage_result: "rows",
      result_name: "main",
      captured_stage: Some("capture"),
      parameter_declarations: None,
      inputs: [],
      input_schemas: [],
      source_catalog: None,
      model_tasks: None,
      calendar_profile: None,
    },
    {
      source: {
        source: input.source,
        tree: input.tree,
        max_origin_entries: 20000,
        max_output_bytes: 100000,
      },
      program: input,
      max_expression_work: 10000,
      max_join_output_rows: 1000L,
      max_collection_items: 1000L,
      max_collection_bytes: 10000L,
    },
  ).unwrap()
  let prepared = match
    @publication_host.prepare_parsed_effect_free_client_program(
      program,
      environment,
      None,
      limits,
    ) {
    Ok(value) => value
    Err(Check(diagnostic)) => raise @program_check.diagnostic_cause(diagnostic)
    Err(_) => fail("scalar Program preparation failed")
  }
  let installed = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = match
    @client_local_host.prepare_source_free_runtime_requirements_result(
      prepared,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ) {
    Ok(value) => value
    Err(CapacityQuoteUnavailable) =>
      fail("scalar runtime capacity quote unavailable: " + text)
    Err(SequencePreparation(RuntimeFragmentWorkLimit(step, limit))) =>
      fail("scalar fragment work limit \{limit} at step \{step}: " + text)
    Err(SequencePreparation(Sequence(SequenceLimit))) =>
      fail("scalar local sequence reached its step limit: " + text)
    Err(SequencePreparation(Sequence(KernelFailure(step, _)))) =>
      fail("scalar local sequence kernel failed at step \{step}: " + text)
    Err(SequencePreparation(Sequence(_))) =>
      fail("scalar local sequence lowering failed: " + text)
    Err(SequencePreparation(Unsupported)) =>
      fail("scalar sequence shape unsupported: " + text)
    Err(GraphShape) => fail("scalar graph not source-free: " + text)
    Err(_) => fail("scalar Local requirements failed: " + text)
  }
  let ledger = @resources.create_ledger(original.maximum_limits()).unwrap()
  @client_local_host.open_source_free_local_retained_host_on_ledger(
    prepared,
    ledger,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    requirements=Some(original),
  ).unwrap()
}

///|
test "scalar subquery retains zero and one child rows through the Common factory" {
  for
    (text, expected) in [
      ("SELECT (SELECT 1) AS x", "{\"x\":1}"),
      ("SELECT (SELECT 'value' WHERE FALSE) AS x", "{\"x\":null}"),
      ("SELECT (SELECT CAST(NULL AS STRING)) AS x", "{\"x\":null}"),
    ] {
    let setup = scalar_subquery_retained_fixture(text)
    let execution = match
      @client_local_host.execute_source_free_local_tasks_guarded(
        setup,
        16,
        10000,
        () => true,
      ) {
      Ok(value) => value
      Err(failure) =>
        match @client_local_host.local_values_execution_failure_issue(failure) {
          Driver(
            ExecutionCapacityRefusal(ExecutionLimit, needed, available, policy)
          ) =>
            fail(
              text +
              ": execution reservation needed \{needed}, available \{available}, policy \{policy}",
            )
          Driver(Execution(Physical(ExecutionLimit))) =>
            fail(text + ": physical execution reservation refused")
          Driver(issue) =>
            fail(
              text +
              ": " +
              @local_driver.local_managed_failure_cause(issue).unwrap_or(
                "unknown driver failure",
              ),
            )
          UnsupportedGraph => fail(text + ": unsupported original graph")
          MissingOutput => fail(text + ": missing final output")
          FinalizationLimit => fail(text + ": finalization limit")
          Estimate(_) => fail(text + ": execution estimate")
          _ => fail(text + ": original execution failed")
        }
    }
    assert_eq(execution.rows().unwrap(), [expected], msg=text)
    assert_true(execution.close())
  }
}

///|
test "scalar subquery refuses multiple original rows even when values repeat" {
  let setup = scalar_subquery_retained_fixture(
    "SELECT (SELECT n AS v FROM UNNEST([1, 1]) AS n) AS x",
  )
  let result = @client_local_host.execute_source_free_local_tasks_guarded(
    setup,
    16,
    10000,
    () => true,
  )
  guard result is Err(failure) else {
    fail("scalar subquery published multiple rows")
  }
  match @client_local_host.local_values_execution_failure_issue(failure) {
    Driver(issue) =>
      assert_eq(
        @local_driver.local_managed_failure_cause(issue),
        Some("assertion.predicate_failed"),
      )
    _ =>
      fail(
        "the scalar subquery must refuse at its original cardinality assertion",
      )
  }
  assert_false(
    @client_local_host.local_values_execution_failure_cleanup_pending(failure),
  )
}

///|
test "scalar subquery runs the original CTE aggregate with a nullable Number result" {
  let setup = scalar_subquery_retained_fixture(
    "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) SELECT (SELECT MAX(v) FROM t) AS x",
  )
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  assert_true(@strategy.graph_task_count(graph) > 1)
  let checked = @strategy.graph_program(graph)
  let results = @stage_results.stage_at(
    @program_check.checked_stage_results(checked),
    0,
  ).unwrap()
  let result = @relation_results.lookup(results, "rows").unwrap()
  let schema = @relation_results.output_schema(result)
  let contract = @schema.lookup(schema, Unqualified("x")).unwrap()
  assert_eq(@relation_results.fields(result), ["x"])
  assert_eq(@schema.field_count(schema), 1)
  assert_true(contract.nullable && contract.shape is Number)

  let execution = @client_local_host.execute_source_free_local_tasks_guarded(
    setup,
    16,
    10000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"x\":30}"])
  assert_true(execution.close())
}

///|
// The actual checked SQL, installed Local Plan and managed task dispatcher.
// No HostJournal/public Run or installed-package acceptance is claimed here.
fn resource_lifecycle_execute_sql(
  sql : String,
  format? : String = "sql",
) -> Array[String] raise {
  let environment = collection_capacity_selected_environment(
    client_local_materialized_row_ceiling(client_local_resource_policy()).unwrap(),
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  )
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, input) = native_driver_parent(sql)
  defer (if parent.phase != Selected && parent.phase != Selecting {
    abort_request_preparation_after_cleanup(parent).unwrap()
  })
  let checked = prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(sql, format),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  )
  if checked is Err(issue) {
    fail(
      "OriginalRequestCheck:" + sql + ":" + direct_union_terminal_detail(issue),
    )
  }
  finish_request_checked_computation(parent, input, environment, publication).unwrap()
  |> ignore
  let prepared = parent.compiled_program.unwrap()
  let contracts = request_program_module_contracts()
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests=request_program_module_manifests(),
    compilation_limits=request_program_compilation_limits(parent, input).unwrap(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-lifecycle-regression",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  defer retire_installed_managed_run(run).unwrap()
  let ledger = run.ledger.unwrap()
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  let output = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(original) => {
      let issue = local_values_execution_failure_issue(original)
      assert_true(retry_local_values_execution_failure_cleanup(original))
      retire_installed_managed_run(run).unwrap()
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
      let diagnostic = match issue {
        Driver(ExecutionCapacityRefusal(cause, needed, available, policy)) =>
          @debug.to_string(cause) +
          ":needed=\{needed}:available=\{available}:policy=\{policy}"
        Driver(Execution(Physical(cause))) =>
          "Physical:" + @debug.to_string(cause)
        Driver(Configuration(Execution(Rows(step, RowLimit)))) =>
          "Configuration.Execution.Rows.RowLimit:\{step}"
        _ => "OriginalLocalFailure"
      }
      fail("OriginalLocalExecution:" + diagnostic)
    }
  }
  let rows = output.rows().unwrap().copy()
  assert_true(output.close())
  retire_installed_managed_run(run).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.live_reservations, 0)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  rows
}

///|
test "text grouped and Pipe aggregates retain the same scalar input backing" {
  let prefix = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL " +
    "SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL " +
    "SELECT 3 AS n, 'a' AS s, 30 AS v) "
  for
    (query, expected, format) in [
      ("SELECT MIN(s) AS x FROM t", ["{\"x\":\"a\"}"], "sql"),
      (
        "SELECT MIN(v) AS lo, MAX(v) AS hi FROM t",
        ["{\"hi\":30,\"lo\":10}"],
        "sql",
      ),
      (
        "SELECT s, MIN(v) AS lo, MAX(v) AS hi FROM t GROUP BY s ORDER BY s",
        [
          "{\"hi\":30,\"lo\":10,\"s\":\"a\"}", "{\"hi\":20,\"lo\":20,\"s\":\"b\"}",
        ],
        "sql",
      ),
      (
        "SELECT s, COUNTIF(v > 10) AS n FROM t GROUP BY s ORDER BY s",
        ["{\"n\":1,\"s\":\"a\"}", "{\"n\":1,\"s\":\"b\"}"],
        "sql",
      ),
      ("FROM t |> AGGREGATE MIN(v) AS x", ["{\"x\":10}"], "aql-text"),
      ("FROM t |> AGGREGATE COUNTIF(v > 10) AS x", ["{\"x\":2}"], "aql-text"),
    ] {
    assert_eq(
      resource_lifecycle_execute_sql(prefix + query, format~).map(value => {
        @json.parse(value)
      }),
      expected.map(value => @json.parse(value)),
    )
  }
}

///|
test "original aggregate result retains actual construction through managed completion" {
  let prefix = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL " +
    "SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL " +
    "SELECT 3 AS n, 'a' AS s, 30 AS v) "
  for
    (query, expected) in [
      ("SELECT MIN(v) AS x FROM t", ["{\"x\":10}"]),
      ("SELECT MAX(v) AS x FROM t", ["{\"x\":30}"]),
      ("SELECT COUNTIF(v > 10) AS x FROM t", ["{\"x\":2}"]),
      ("SELECT COUNT(DISTINCT s) AS x FROM t", ["{\"x\":2}"]),
      ("SELECT SUM(v) AS x FROM t", ["{\"x\":60}"]),
    ] {
    assert_eq(resource_lifecycle_execute_sql(prefix + query), expected)
  }
}

///|
test "unfiltered and all-pass filtered ten-thousand rows share original resource lifecycle" {
  let digits = Array::makei(10, n => "SELECT " + n.to_string() + " AS n").join(
    " UNION ALL ",
  )
  let prefix = "WITH d AS (" +
    digits +
    ") SELECT a.n*1000+b.n*100+c.n*10+e.n AS id " +
    "FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e"
  for
    suffix in ["", " ORDER BY id", " WHERE a.n*1000+b.n*100+c.n*10+e.n < 10000"] {
    let rows = resource_lifecycle_execute_sql(prefix + suffix)
    assert_eq(rows.length(), 10000)
    let expected = Array::makei(10000, index => {
      "{\"id\":" + index.to_string() + "}"
    })
    if suffix == " ORDER BY id" {
      assert_eq(rows, expected)
    } else {
      rows.sort()
      expected.sort()
      assert_eq(rows, expected)
    }
  }
}

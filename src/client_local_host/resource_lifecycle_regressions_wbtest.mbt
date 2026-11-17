///|
// The actual checked SQL, installed Local Plan and managed task dispatcher.
// No HostJournal/public Run or installed-package acceptance is claimed here.
fn resource_lifecycle_execute_sql(
  sql : String,
  format? : String = "sql",
  memory? : Int64? = None,
  source_free_max_work? : Int? = None,
  observe_limits? : Bool = false,
) -> Array[String] raise {
  let policy = client_local_resource_policy()
  let environment = collection_capacity_selected_environment(
    client_local_materialized_row_ceiling(
      policy,
      retained_bytes=memory,
      execution_bytes=memory,
    ).unwrap(),
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
  let (parent, input) = match memory {
    None => native_driver_parent(sql)
    Some(_) =>
      native_driver_parent(
        sql,
        initial_limits=Some(
          client_local_preparation_initial_limits(
            policy,
            retained_bytes=memory,
            execution_bytes=memory,
          ).unwrap(),
        ),
      )
  }
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
    source_free_max_work~,
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  if observe_limits {
    let selected = plan.capacity_plan
    println(
      "OriginalSelectedLimits:admitted_rows=\{selected.admitted_rows}" +
      ":max_rows=\{selected.execution.rows.max_rows}" +
      ":operation_entries=\{selected.execution.rows.operation_entries}" +
      ":max_work=\{selected.execution.max_work}",
    )
  }
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-lifecycle-regression",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  defer (match retire_installed_managed_run(run) {
    Ok(_) => ()
    Err(_) =>
      // The explicit success path below still requires retirement. A failed
      // cleanup must not replace the original raised test failure on unwind.
      println("OriginalLifecycleCleanupPending:retirement_refused")
  })
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
      let cleanup_complete = retry_local_values_execution_failure_cleanup(
        original,
      )
      let retirement = retire_installed_managed_run(run)
      let diagnostic = match issue {
        Driver(ExecutionCapacityRefusal(cause, needed, available, policy)) =>
          @debug.to_string(cause) +
          ":needed=\{needed}:available=\{available}:policy=\{policy}"
        Driver(Execution(Physical(cause))) =>
          "Physical:" + @debug.to_string(cause)
        Driver(Configuration(Execution(Rows(step, RowLimit)))) =>
          "Configuration.Execution.Rows.RowLimit:\{step}"
        Driver(original) =>
          @local_driver.local_managed_failure_cause(original).unwrap_or(
            "OriginalLocalFailure",
          )
        _ => "OriginalLocalFailure"
      }
      fail(
        "OriginalLocalExecution:" +
        sql +
        ":" +
        diagnostic +
        ":cleanup_complete=\{cleanup_complete}:retired=\{retirement is Ok(_)}",
      )
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
test "original raised policy returns all hundred-thousand rows for unfiltered ordered and filtered shapes" {
  let digits = Array::makei(10, n => "SELECT " + n.to_string() + " AS n").join(
    " UNION ALL ",
  )
  let expression = "a.n*10000+b.n*1000+c.n*100+d.n*10+e.n"
  let prefix = "WITH d AS (" +
    digits +
    ") SELECT " +
    expression +
    " AS id FROM d AS a CROSS JOIN d AS b CROSS JOIN d AS c CROSS JOIN d AS d CROSS JOIN d AS e"
  for suffix in ["", " ORDER BY id", " WHERE " + expression + " < 100000"] {
    // Exact previously reported explicit installation, selected before the
    // original Request/Ledger; these are not new production policy defaults.
    let rows = resource_lifecycle_execute_sql(
      prefix + suffix,
      memory=Some(1073741824L),
      source_free_max_work=Some(30000000),
    )
    let expected = Array::makei(100000, index => {
      "{\"id\":" + index.to_string() + "}"
    })
    assert_eq(rows.length(), 100000)
    if suffix == " ORDER BY id" {
      assert_eq(rows, expected)
    } else {
      rows.sort()
      expected.sort()
      assert_eq(rows, expected)
    }
  }
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

///|
fn resource_lifecycle_boundary_rows(count : Int) -> Unit raise {
  let digits = Array::makei(10, n => "SELECT " + n.to_string() + " AS n").join(
    " UNION ALL ",
  )
  let expression = "a.n*1000+b.n*100+c.n*10+e.n"
  let prefix = "WITH d AS (" +
    digits +
    ") SELECT " +
    expression +
    " AS id FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e"
  let suffix = if count == 9999 {
    " WHERE " + expression + " < 9999"
  } else {
    " UNION ALL SELECT 10000 AS id"
  }
  let rows = resource_lifecycle_execute_sql(
    prefix + suffix,
    observe_limits=true,
  )
  let expected = Array::makei(count, index => {
    "{\"id\":" + index.to_string() + "}"
  })
  assert_eq(rows.length(), count)
  // Neither query declares ORDER BY: preserve independent multiplicity.
  rows.sort()
  expected.sort()
  assert_eq(rows, expected)
}

///|
test "boundary preceding ten thousand retains every original row" {
  resource_lifecycle_boundary_rows(9999)
}

///|
test "boundary following ten thousand retains every original row" {
  resource_lifecycle_boundary_rows(10001)
}

///|
test "boundary nullable and empty aggregates retain their original typed results" {
  let prefix = "WITH t AS (SELECT 10 AS v UNION ALL SELECT CAST(NULL AS FLOAT64) AS v " +
    "UNION ALL SELECT 30 AS v) "
  let query = "SELECT MIN(v) AS lo, MAX(v) AS hi, COUNTIF(v > 10) AS n, " +
    "COUNT(DISTINCT v) AS d FROM t"
  for
    (suffix, expected) in [
      ("", "{\"lo\":10,\"hi\":30,\"n\":1,\"d\":2}"),
      (" WHERE FALSE", "{\"lo\":null,\"hi\":null,\"n\":0,\"d\":0}"),
    ] {
    let actual = resource_lifecycle_execute_sql(prefix + query + suffix)
    assert_eq(actual.map(value => @json.parse(value)), [@json.parse(expected)])
  }
}

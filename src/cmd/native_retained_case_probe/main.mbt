///|
/// Native registered-case product path. The wrapper supplies the checked
/// application files and compares this result with its independent oracle.
fn required(matches : @argparse.Matches, name : String) -> String {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => abort("missing or repeated option --" + name)
  }
}

///|
fn int_option(matches : @argparse.Matches, name : String) -> Int {
  let parsed : Int = @string.from_str(required(matches, name)) catch {
    _ => abort("invalid integer option --" + name)
  }
  if parsed < 1 {
    abort("nonpositive option --" + name)
  }
  parsed
}

///|
fn int64_option(matches : @argparse.Matches, name : String) -> Int64 {
  let parsed : Int64 = @string.from_str(required(matches, name)) catch {
    _ => abort("invalid integer option --" + name)
  }
  if parsed < 1L {
    abort("nonpositive option --" + name)
  }
  parsed
}

///|
fn task_rates_option(
  matches : @argparse.Matches,
  name : String,
  task_count : Int,
) -> Array[Int64] {
  let raw = required(matches, name)
  if raw == "-" {
    return []
  }
  let parts = raw.split(",").to_array()
  if parts.length() != task_count {
    abort("incorrect task estimate count --" + name)
  }
  let rates : Array[Int64] = []
  for part in parts {
    let rate : Int64 = @string.from_str(part) catch {
      _ => abort("invalid task estimate --" + name)
    }
    if rate < 1L || rate > 2147483647L {
      abort("out-of-range task estimate --" + name)
    }
    rates.push(rate)
  }
  rates
}

///|
fn rejection_name(issue : @resources.LedgerIssue?) -> String {
  match issue {
    None => "feasible"
    Some(@resources.PlanningLimit) => "planning"
    Some(@resources.AttemptLimit) => "attempt"
    Some(@resources.HoldingLimit) => "holding"
    Some(@resources.TransferLimit) => "transfer"
    Some(@resources.RetentionLimit) => "retention"
    Some(@resources.ExecutionLimit) => "execution"
    Some(@resources.InvalidLimits) => "invalid-limits"
    Some(@resources.ForeignOwner) => "foreign-owner"
    Some(@resources.ClosedReservation) => "closed-reservation"
    Some(@resources.ClosedHolding) => "closed-holding"
    Some(@resources.InvalidCharge) => "invalid-charge"
  }
}

///|
fn native_strategy_issue_name(
  issue : @host.NativeStrategyComputeRunIssue,
) -> String {
  match issue {
    @host.Closed => "closed"
    @host.Start(start) =>
      match start {
        @host.Physical(@host.InvalidLimits) => "start-physical-limits"
        @host.Physical(@host.ImportCount) => "start-import-count"
        @host.Physical(@host.ImportRows) => "start-import-rows"
        @host.Physical(@host.ImportColumns) => "start-import-columns"
        @host.Physical(@host.ImportCells) => "start-import-cells"
        @host.Physical(_) => "start-physical"
        @host.Strategy(run) =>
          match run {
            @strategy.UnsupportedGraph => "start-strategy-graph"
            @strategy.ForeignCapture => "start-strategy-capture"
            @strategy.NotReady => "start-strategy-not-ready"
            @strategy.Stopped => "start-strategy-stopped"
            @strategy.ForeignCandidate => "start-strategy-candidate"
            @strategy.MissingOutput => "start-strategy-output"
            @strategy.Capture(_) => "start-strategy-source"
            @strategy.Binding(_) => "start-strategy-binding"
            @strategy.Read(_) => "start-strategy-read"
            @strategy.Compute(_) => "start-strategy-compute"
            @strategy.Implementation(_) => "start-strategy-implementation"
            @strategy.Physical(issue) =>
              "start-strategy-physical-" + rejection_name(Some(issue))
          }
        @host.Settlement(_) => "start-settlement"
        @host.MissingOutput => "start-missing-output"
      }
    @host.Execution(failure) =>
      match failure.primary {
        @host.Physical(physical) =>
          match physical {
            @host.RuntimeState => "physical-runtime-state"
            @host.InvalidLimits => "physical-limits"
            @host.ImportCount => "physical-import-count"
            @host.ImportRows => "physical-import-rows"
            @host.ImportColumns => "physical-import-columns"
            @host.ImportCells => "physical-import-cells"
            @host.ParameterCount => "physical-parameters"
            @host.Runtime(_) => "physical-duckdb"
            @host.Parameter(_) => "physical-parameter-binding"
            @host.Query(_) => "physical-query"
            @host.Fields(_) => "physical-fields"
            @host.Columns(_) => "physical-columns"
            @host.Compute(_) => "physical-compute"
            @host.RetainedFile(_) => "physical-retained-file"
            @host.RowFrames(_) => "physical-row-frames"
            @host.RetainedImport(_) => "physical-retained-import"
          }
        @host.Strategy(_) => "strategy"
        @host.Settlement(_) => "settlement"
        @host.MissingOutput => "missing-output"
      }
  }
}

///|
/// Measure the same one-task product boundary used by the full Run helper.
/// These monotonic intervals are calibration inputs, never acceptance
/// timings. The clock observation grants no execution authority.
fn execute_timed_native_strategy_run(
  run : @host.NativeStandardStrategyRun,
) -> Result[Unit, @host.NativeStandardStrategyRunIssue] {
  while true {
    let before = @bench.monotonic_clock_start()
    match @host.execute_next_native_standard_strategy_task(run) {
      Ok(Some(completion)) => {
        let elapsed = @bench.monotonic_clock_end(before).to_int64()
        if elapsed < 0L {
          abort("invalid monotonic interval")
        }
        println(
          "task-elapsed-us:" +
          completion.task.to_string() +
          ":" +
          elapsed.to_string(),
        )
      }
      Ok(None) => return Ok(())
      Err(issue) => return Err(issue)
    }
  } nobreak {
    Err(@host.InvalidSelection)
  }
}

///|
fn main {
  let execution_start = @bench.monotonic_clock_start()
  let command = @argparse.Command("actql-native-retained-case-probe", options=[
    @argparse.OptionArg("application-root", required=true),
    @argparse.OptionArg("database", required=true),
    @argparse.OptionArg("duckdb-library", required=true),
    @argparse.OptionArg("retained-task-root", required=true),
    @argparse.OptionArg("expected-cid", required=true),
    @argparse.OptionArg("expected-tasks", required=true),
    @argparse.OptionArg("native-ms", default_values=["1000"]),
    @argparse.OptionArg("local-eligible", default_values=["true"]),
    @argparse.OptionArg("local-task-ms", default_values=["-"]),
    @argparse.OptionArg("native-task-ms", default_values=["-"]),
    @argparse.OptionArg("source-rows", required=true),
    @argparse.OptionArg("task-rows", required=true),
    @argparse.OptionArg("columns", required=true),
    @argparse.OptionArg("value-bytes", required=true),
    @argparse.OptionArg("wire-bytes", required=true),
    @argparse.OptionArg("value-nodes", required=true),
    @argparse.OptionArg("text-bytes", required=true),
    @argparse.OptionArg("work", required=true),
    @argparse.OptionArg("entries", required=true),
    @argparse.OptionArg("batch-bytes", required=true),
    @argparse.OptionArg("planning-work", required=true),
    @argparse.OptionArg("transfer-cap", required=true),
    @argparse.OptionArg("retained-cap", required=true),
    @argparse.OptionArg("execution-cap", required=true),
  ])
  let matches = command.parse() catch { error => abort(error.to_string()) }
  let root = required(matches, "application-root")
  let database_path = required(matches, "database")
  let library_path = required(matches, "duckdb-library")
  let retained_task_root = required(matches, "retained-task-root")
  let expected_cid = required(matches, "expected-cid")
  let expected_tasks = int_option(matches, "expected-tasks")
  let local_eligible = match required(matches, "local-eligible") {
    "true" => true
    "false" => false
    _ => abort("invalid local eligibility")
  }
  let local_task_ms = task_rates_option(
    matches, "local-task-ms", expected_tasks,
  )
  let native_task_ms = task_rates_option(
    matches, "native-task-ms", expected_tasks,
  )
  if (!local_eligible && !local_task_ms.is_empty()) ||
    (!native_task_ms.is_empty() && local_eligible && local_task_ms.is_empty()) {
    abort("incomplete task estimate profile")
  }
  let source_rows = int_option(matches, "source-rows")
  let task_rows = int_option(matches, "task-rows")
  let columns = int_option(matches, "columns")
  let value_bytes = int_option(matches, "value-bytes")
  let wire_bytes = int_option(matches, "wire-bytes")
  let value_nodes = int_option(matches, "value-nodes")
  let text_bytes = int_option(matches, "text-bytes")
  let work = int_option(matches, "work")
  let entries = int_option(matches, "entries")
  let batch_bytes = int_option(matches, "batch-bytes")
  let execution_cap = int64_option(matches, "execution-cap")
  let native_ms : Int64 = @string.from_str(required(matches, "native-ms")) catch {
    _ => abort("invalid native-ms")
  }
  println("phase:application")
  let app = @application.load_native_remote_application_with_data(
    root,
    {
      program: "program.json",
      environment: "environment.json",
      environment_cid: "environment.cid",
      parameters: "parameters.json",
      registry: "registry.json",
      values: "values.json",
      fragment: "fragment.json",
      query: "query.json",
      evidence: "evidence.json",
      two_receipt: "two-receipt.json",
    },
    1048576L,
    "main",
    "records",
    {
      source_rows,
      task_rows,
      columns,
      value_bytes,
      wire_bytes,
      value_nodes,
      text_bytes,
      work,
      entries,
      batch_bytes,
    },
  ).unwrap()
  println("phase:library")
  let library = @duckdb.load_library(library_path).unwrap()
  println("phase:database")
  let database = library
    .open_database(
      {
        memory_bytes: execution_cap,
        threads: 1,
        external_access: false,
        read_only: false,
      },
      path=database_path,
    )
    .unwrap()
  println("phase:acquisition-start")
  let acquisition = @host.start_native_acquisition_runtime(
    @example.application_acquisition(app),
    "native-retained-diagnostic",
    database,
  ).unwrap()
  println("phase:acquisition-execute")
  let acquisition_observation = match
    @host.execute_native_acquisition_runtime(acquisition) {
    Ok(value) => value
    Err(failure) =>
      match failure.primary {
        @host.RuntimeState => abort("acquisition runtime state")
        @host.InvalidLimits => abort("acquisition limits")
        @host.ParameterCount => abort("acquisition parameter count")
        @host.MetadataShape => abort("acquisition metadata shape")
        @host.Runtime(_) => abort("acquisition DuckDB runtime")
        @host.Parameter(_) => abort("acquisition parameter")
        @host.Fields(_) => abort("acquisition physical fields")
        @host.Columns(_) => abort("acquisition transport columns")
        @host.Host(issue) =>
          match issue {
            @acquisition_host.InvalidState => abort("acquisition Host state")
            @acquisition_host.Evidence(_) => abort("acquisition Host evidence")
            @acquisition_host.Attempt(inner) =>
              match inner {
                @duckdb_acquisition.ForeignChoice =>
                  abort("acquisition foreign choice")
                @duckdb_acquisition.InvalidState =>
                  abort("acquisition attempt state")
                @duckdb_acquisition.Demand(_) => abort("acquisition demand")
                @duckdb_acquisition.Receipts(_) => abort("acquisition receipts")
                @duckdb_acquisition.Receiving(receiving) =>
                  match receiving {
                    @adapter.InvalidLimits =>
                      abort("acquisition receiving limits")
                    @adapter.InvalidState =>
                      abort("acquisition receiving state")
                    @adapter.ForeignReceipt =>
                      abort("acquisition foreign receipt")
                    @adapter.NotBaseTable => abort("acquisition not base table")
                    @adapter.InvalidMetadata => abort("acquisition metadata")
                    @adapter.Values(_) => abort("acquisition values")
                    @adapter.Guard(_, _, _, _) => abort("acquisition guard")
                    @adapter.Stream(_) => abort("acquisition stream")
                  }
              }
            @acquisition_host.Completion(_) =>
              abort("acquisition Host completion")
            @acquisition_host.Binding(_) => abort("acquisition Host binding")
          }
      }
  }
  let (guard_work, guard_bytes, guard_nodes) = @duckdb_acquisition.duckdb_native_observation_measurement_usage(
    acquisition_observation,
  )
  let comparison = @duckdb_acquisition.duckdb_native_observation_demand_usage(
    acquisition_observation,
  )
  println("phase:acquisition-output")
  let output = @host.native_acquisition_runtime_output(acquisition).unwrap()
  println("phase:source")
  let source = @duckdb_acquisition.native_captured_source(
    output, source_rows, work,
  ).unwrap()
  let ledger = @example.application_bounded_ledger({
    planning_work: int_option(matches, "planning-work"),
    attempts: 12,
    holdings: 12,
    transfer_bytes: int64_option(matches, "transfer-cap"),
    retained_bytes: int64_option(matches, "retained-cap"),
    execution_bytes: execution_cap,
  }) catch {
    _ => abort("registered ledger limits rejected")
  }
  println("phase:capture")
  let captured = @strategy.open_captured_dag(
    @example.application_graph(app),
    source,
    ledger,
  ).unwrap()
  // Capture owns the admitted rows; the acquisition database is no longer a
  // live input. Close its physical connection before task databases start.
  database.close()
  println("phase:dispatch")
  let dispatch = @example.application_native_retained_strategy_dispatch(
    app,
    captured,
    native_ms,
    wire_bytes.to_int64(),
    1L,
    1L,
    1L,
    false,
    local_task_ms~,
    native_task_ms~,
    local_eligible~,
  ) catch {
    _ => abort("native strategy dispatch rejected")
  }
  println("phase:strategy-open")
  let run = @host.open_native_standard_strategy_run(
    dispatch,
    {
      max_rows: task_rows,
      max_cells: (source_rows + task_rows) * columns,
      max_parameters: columns + 100,
      max_sql_bytes: 100000,
      max_batch_rows: Int::min(source_rows, 1000),
    },
    @example.application_native_retained_task_transfer_capacity(app),
    // The selected execution envelope also reserves decoder and query scratch.
    // The database receives its own half rather than claiming the whole pool.
    execution_cap / 2L,
    library=Some(library),
    database_path~,
    retained_profile={
      root_path: retained_task_root,
      run_occurrence: "native-application-" + @env.now().to_string(),
      max_file_bytes: wire_bytes.to_int64(),
      wire: {
        max_columns: columns,
        max_order_work: work,
        max_bytes: wire_bytes,
        max_nodes: value_nodes,
        max_depth: 64,
      },
      max_batch_bytes: batch_bytes,
      // The configured transport admits at most 512 rows per physical frame.
      max_chunk_rows: Int::min(task_rows, 512),
    },
  ).unwrap()
  println("phase:strategy-execute")
  match execute_timed_native_strategy_run(run) {
    Ok(_) => ()
    Err(@host.Closed) => abort("native strategy run closed")
    Err(@host.InvalidSelection) => abort("native strategy selection invalid")
    Err(@host.DuckDBUnavailable) => abort("native strategy DuckDB unavailable")
    Err(@host.Dispatch(issue)) =>
      match issue {
        @standard_host.InvalidConfiguration =>
          abort("native strategy dispatch configuration")
        @standard_host.NoStrategy => {
          println(
            "strategy-report-count:" +
            @strategy.strategy_report_count(captured).to_string(),
          )
          for report_index in 0..<@strategy.strategy_report_count(captured) {
            let assessment = @strategy.strategy_report_at(
              captured, report_index,
            ).unwrap()
            println(
              "strategy-rejection:" +
              report_index.to_string() +
              ":" +
              rejection_name(assessment.rejection) +
              ":retained=" +
              assessment.retained_bytes.to_string(),
            )
          }
          abort("native strategy missing")
        }
        @standard_host.ForeignSelection =>
          abort("native strategy foreign selection")
        @standard_host.PendingTask => abort("native strategy pending task")
        @standard_host.StaleTask => abort("native strategy stale task")
        @standard_host.Run(_) => abort("native strategy common Run rejected")
        @standard_host.Candidate(_) =>
          abort("native strategy candidate rejected")
        @standard_host.NativeCandidate(_) =>
          abort("native strategy native candidate rejected")
        @standard_host.Search(_) => abort("native strategy search rejected")
        @standard_host.EstimateOverflow =>
          abort("native strategy estimate overflow")
        @standard_host.JoinPreparation(_) =>
          abort("native strategy join preparation rejected")
      }
    Err(@host.Database(_)) => abort("native strategy database rejected")
    Err(@host.DuckDB(issue)) =>
      abort(
        "native strategy DuckDB task rejected: " +
        native_strategy_issue_name(issue),
      )
    Err(@host.Local(_)) => abort("native strategy Local task rejected")
  }
  let task = @example.application_compute_count(app)
  if task != expected_tasks {
    abort("checked task count differs from fixture")
  }
  println("phase:output-cid")
  let output = @host.read_native_standard_task_output(
    run,
    task,
    task_rows,
    {
      max_nodes: value_nodes,
      max_text_bytes: text_bytes,
      max_depth: 64,
      max_work: work,
    },
    {
      max_columns: columns,
      max_order_work: work,
      max_bytes: wire_bytes,
      max_nodes: value_nodes,
      max_depth: 64,
    },
    batch_bytes,
  ).unwrap()
  let cid = @execution.row_wire_cid(
    @execution.identify_completed_rows(output, {
      max_columns: columns,
      max_order_work: work,
      max_bytes: wire_bytes,
      max_nodes: value_nodes,
      max_depth: 64,
    }).unwrap(),
  )
  if cid != expected_cid {
    abort("final output identity differs from fixture oracle")
  }
  for index in 0..<@strategy.strategy_history_count(captured) {
    let revision = @strategy.strategy_history_at(captured, index).unwrap()
    for selected_task in 1..<(task + 1) {
      match @strategy.strategy_registration(revision, selected_task) {
        Some(registration) =>
          println(
            "selection:" +
            selected_task.to_string() +
            ":" +
            @connector.capability_description(registration).name,
          )
        None => ()
      }
    }
  }
  let execution_us = @bench.monotonic_clock_end(execution_start).to_int64()
  if execution_us < 0L {
    abort("invalid execution interval")
  }
  let cleanup_start = @bench.monotonic_clock_start()
  if !@host.close_native_standard_strategy_run(run).unwrap() {
    abort("native strategy cleanup unconfirmed")
  }
  @host.close_native_acquisition_runtime(acquisition)
  @strategy.stop_captured_dag(captured)
  let usage = @resources.ledger_usage(ledger)
  if usage.uncertain_transfer_bytes != 0L ||
    usage.reserved_transfer_bytes != 0L ||
    usage.held_bytes != 0L ||
    usage.reserved_retention_bytes != 0L ||
    usage.reserved_execution_bytes != 0L {
    abort("native strategy ledger has unresolved capacity")
  }
  let cleanup_us = @bench.monotonic_clock_end(cleanup_start).to_int64()
  if cleanup_us < 0L {
    abort("invalid cleanup interval")
  }
  println(
    "{\"task_count\":" +
    task.to_string() +
    ",\"rows_cid\":\"" +
    cid +
    "\",\"execution_us\":" +
    execution_us.to_string() +
    ",\"cleanup_us\":" +
    cleanup_us.to_string() +
    ",\"usage\":{\"planning_work\":" +
    usage.planning_work.to_string() +
    ",\"attempts\":" +
    usage.attempts.to_string() +
    ",\"transferred_bytes\":" +
    usage.transferred_bytes.to_string() +
    ",\"peak_retention_bytes\":" +
    usage.peak_retention_bytes.to_string() +
    "},\"acquisition\":{\"guard_work\":" +
    guard_work.to_string() +
    ",\"guard_bytes\":" +
    guard_bytes.to_string() +
    ",\"guard_nodes\":" +
    guard_nodes.to_string() +
    ",\"comparison_work\":" +
    comparison.physical_work.to_string() +
    ",\"comparison_bytes\":" +
    comparison.physical_bytes.to_string() +
    ",\"comparison_nodes\":" +
    comparison.physical_nodes.to_string() +
    ",\"comparison_rows\":" +
    comparison.rows.to_string() +
    "}" +
    "}",
  )
}

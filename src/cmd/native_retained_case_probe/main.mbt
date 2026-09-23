///|
/// Native registered-case product-path diagnostic. It does not provide independent
/// file holding or the four-comparator performance acceptance boundary.
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
fn rejection_name(issue : @resources.LedgerIssue?) -> String {
  match issue {
    None => "feasible"
    Some(@resources.PlanningLimit) => "planning"
    Some(@resources.AttemptLimit) => "attempt"
    Some(@resources.HoldingLimit) => "holding"
    Some(@resources.TransferLimit) => "transfer"
    Some(@resources.RetentionLimit) => "retention"
    Some(@resources.ExecutionLimit) => "execution"
    Some(_) => "other-ledger"
  }
}

///|
fn main {
  let command = @argparse.Command("actql-native-retained-case-probe", options=[
    @argparse.OptionArg("application-root", required=true),
    @argparse.OptionArg("database", required=true),
    @argparse.OptionArg("duckdb-library", required=true),
    @argparse.OptionArg("expected-cid", required=true),
    @argparse.OptionArg("expected-tasks", required=true),
    @argparse.OptionArg("native-ms", default_values=["1000"]),
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
  let expected_cid = required(matches, "expected-cid")
  let expected_tasks = int_option(matches, "expected-tasks")
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
  match @host.execute_native_acquisition_runtime(acquisition) {
    Ok(_) => ()
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
  println("phase:dispatch")
  let dispatch = @example.application_strategy_dispatch(
    app, captured, native_ms, false,
  ) catch {
    _ => abort("native strategy dispatch rejected")
  }
  println("phase:strategy-open")
  let run = @host.open_native_standard_strategy_run(
    dispatch,
    {
      max_rows: task_rows,
      max_cells: source_rows * columns,
      max_parameters: columns + 100,
      max_sql_bytes: 100000,
      max_batch_rows: Int::min(source_rows, 1000),
    },
    int64_option(matches, "transfer-cap"),
    execution_cap,
    library=Some(library),
    database_path~,
  ).unwrap()
  println("phase:strategy-execute")
  match @host.execute_native_standard_strategy_run(run) {
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
    Err(@host.DuckDB(_)) => abort("native strategy DuckDB task rejected")
  }
  let task = @example.application_compute_count(app)
  if task != expected_tasks {
    abort("checked task count differs from fixture")
  }
  println("phase:output-cid")
  let cid = @example.application_profile_output_cid(app, captured, task).unwrap()
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
  println(
    "{\"task_count\":" + task.to_string() + ",\"rows_cid\":\"" + cid + "\"}",
  )
  if !@host.close_native_standard_strategy_run(run).unwrap() {
    abort("native strategy cleanup unconfirmed")
  }
  @host.close_native_acquisition_runtime(acquisition)
  @strategy.stop_captured_dag(captured)
}

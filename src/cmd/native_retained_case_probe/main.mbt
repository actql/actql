///|
/// Native narrow-100 product-path diagnostic. It does not provide independent
/// file holding or the four-comparator performance acceptance boundary.
fn main {
  let command = @argparse.Command("actql-native-retained-case-probe", options=[
    @argparse.OptionArg("application-root", required=true),
    @argparse.OptionArg("database", required=true),
    @argparse.OptionArg("duckdb-library", required=true),
    @argparse.OptionArg("expected-cid", required=true),
    @argparse.OptionArg("native-ms", default_values=["1000"]),
  ])
  let matches = command.parse() catch { error => abort(error.to_string()) }
  let root = matches.values.get("application-root").unwrap()[0]
  let database_path = matches.values.get("database").unwrap()[0]
  let library_path = matches.values.get("duckdb-library").unwrap()[0]
  let expected_cid = matches.values.get("expected-cid").unwrap()[0]
  let native_ms : Int64 = @string.from_str(
    matches.values.get("native-ms").unwrap()[0],
  ) catch {
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
      source_rows: 100,
      task_rows: 2,
      columns: 2,
      value_bytes: 2048,
      wire_bytes: 6400,
      value_nodes: 3232,
      text_bytes: 3200,
      work: 25600,
      entries: 3232,
      batch_bytes: 6400,
    },
  ).unwrap()
  println("phase:library")
  let library = @duckdb.load_library(library_path).unwrap()
  println("phase:database")
  let database = library
    .open_database(
      {
        memory_bytes: 134217728L,
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
  let source = @duckdb_acquisition.native_captured_source(output, 1000, 10000).unwrap()
  let ledger = @example.application_ledger()
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
      max_rows: 100,
      max_cells: 200,
      max_parameters: 200,
      max_sql_bytes: 100000,
      max_batch_rows: 100,
    },
    1000000L,
    134217728L,
    library=Some(library),
    database_path~,
  ).unwrap()
  println("phase:strategy-execute")
  @host.execute_native_standard_strategy_run(run).unwrap()
  let task = @example.application_compute_count(app)
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

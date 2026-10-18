///|
// Literal public queries remain distinct from the original file-backed AQL
// protocol command. Neither command spelling nor an output format selects a
// different parser, Host, submission owner or retry policy.
fn local_quick_query_requested(
  operation : String,
  child : @argparse.Matches,
) -> Bool {
  operation == "sql" || (operation == "aql" && child.values.contains("query"))
}

///|
fn local_quick_query_format(
  child : @argparse.Matches,
) -> String raise ClientStop {
  let value = optional(child, "format").unwrap_or("table")
  if !["table", "json", "jsonl", "csv"].contains(value) {
    stop("InvalidQuickQueryResultFormat")
  }
  value
}

///|
fn normalize_native_query_arguments(
  matches : @argparse.Matches,
) -> Unit raise ClientStop {
  guard matches.subcommand is Some((operation, child)) else { return }
  if !local_quick_query_requested(operation, child) {
    if operation == "aql" {
      // Keep the original required fields before any project or credential I/O.
      for
        name in [
          "program-file", "format", "submission-ref-file", "operation-attempt-id",
        ] {
        ignore(required(child, name))
      }
    }
    return
  }
  ignore(required(child, "query"))
  for
    name in [
      "program-file", "parameter-declarations-file", "stop-before", "request-id",
      "submission-ref-file", "operation-attempt-id",
    ] {
    if child.values.contains(name) {
      stop("ConflictingQuickQuerySelection")
    }
  }
  match (optional(child, "params"), optional(child, "parameters-file")) {
    (Some(_), Some(_)) => stop("ConflictingParameterInputs")
    (Some(path), None) => {
      child.values["parameters-file"] = [path]
      ignore(child.values.remove("params"))
    }
    _ => ()
  }
  ignore(local_quick_query_format(child))
}

///|
// Observe and read the original accepted Run. A completed submission callback
// or an index flag is never a Result-availability or successful-delivery fact.
fn local_quick_query(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  sqlite : @local_sqlite.Library,
  environment : @checked.CheckEnvironment,
  input_root : String,
  operation : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let format = local_quick_query_format(child)
  // The existing delivery grant is for exact json/jsonl/csv bytes at stdout.
  // It cannot certify transformed table bytes or authorize a file writer.
  // These missing adapters refuse before allocating a submission or attempt.
  if format == "table" {
    stop("LocalQueryTablePresentationUnavailable")
  }
  if child.values.contains("output") {
    stop("LocalResultFileDeliveryUnavailable")
  }
  let original = local_submission_start(
    host,
    settings,
    crypto,
    sqlite,
    environment,
    input_root,
    operation,
    child,
    public_run=true,
  )
  let root = @decode.open_object(local_input_cursor(original)).unwrap_or_else(() => {
    stop("LocalQuerySavedStateUnavailable")
  })
  let run_id = run_text(root, "run_id")
  let correlation = " originalRunId=" +
    encode_request_json(Json::string(run_id), 8192) +
    " (observe this Run; do not repeat the query submission)"
  let ready = @publication.run_wait_ready_until(
    original,
    None,
    @publication.Final,
    65536,
    8192,
    64,
  ).unwrap_or_else(() => stop("LocalQuerySavedStateUnavailable" + correlation))
  if !ready {
    stop("LocalQueryNotFinal" + correlation)
  }
  // Select only that original returned Run; the Result Owner restores its
  // succeeded originals and rechecks current read permission independently.
  let selected = command().parse(
    argv=["result", "--format", format, "--", run_id],
    env=Map([]),
  ) catch {
    _ => stop("LocalQueryResultSelectionUnavailable" + correlation)
  }
  let (_, result) = selected.subcommand.unwrap()
  local_public_result(host, settings, crypto, sqlite, result) catch {
    ClientStop(issue) => stop(issue + correlation)
  }
}

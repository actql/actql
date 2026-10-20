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
// Refuse unsupported destinations before allocating a Submission or attempt.
// A stdout byte receipt cannot acknowledge an internal material receiver.
fn local_quick_query_delivery(
  child : @argparse.Matches,
) -> String raise ClientStop {
  let format = local_quick_query_format(child)
  if format == "table" {
    stop("LocalQueryTablePresentationUnavailable")
  }
  if child.values.contains("output") {
    stop("LocalResultFileDeliveryUnavailable")
  }
  format
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
      "program-file", "stop-before", "request-id", "submission-ref-file", "operation-attempt-id",
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
  let format = local_quick_query_delivery(child)
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
  let result = local_quick_query_result(original, format)
  local_public_result(host, settings, crypto, sqlite, result.0) catch {
    ClientStop(issue) => stop(issue + result.1)
  }
}

///|
// Select the exact returned Run only. A refusal after submission includes the
// original correlation; it never retries or starts a replacement query.
fn local_quick_query_result(
  original : String,
  format : String,
) -> (@argparse.Matches, String) raise ClientStop {
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
  (result, correlation)
}

///|
// Use the same admitted business selection and its actual publication Store.
// Run acceptance does not itself grant Result access: the existing captured
// Result Owner independently restores/current-checks that exact returned Run.
fn LocalCommandPreparationOriginal::execute_original_quick_query(
  self : LocalCommandPreparationOriginal,
  host : @local_host.NativeLocalHostConnection,
  capture : @local_host.NativeLocalJournalCapture,
  settings : LocalHostSettings,
  configuration_name : String,
  runtime : LocalPackagedRuntime,
  input_root : String,
  operation : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let presentation = local_quick_query_format(child)
  if child.values.contains("output") {
    stop("LocalResultFileDeliveryUnavailable")
  }
  if presentation == "table" &&
    !settings.installation_files.contains("material-read.json") {
    stop("LocalResultMaterialOriginalNotSelected")
  }
  // JSON is the private material transfer encoding, never a stdout receipt
  // relabelled as a table. The selected receiver owns the checked rows.
  let format = if presentation == "table" { "json" } else { presentation }
  let publication = self.prepare_business_submission(
    host, capture, configuration_name, runtime, input_root, operation, child,
  )
  let physical = self.host.unwrap_or_else(() => {
    stop("LocalBusinessOriginalUnavailable")
  })
  let pair = self.pair.unwrap_or_else(() => {
    stop("LocalBusinessOriginalUnavailable")
  })
  let sqlite = physical
    .borrow_local_host_sqlite(pair)
    .unwrap_or_else(() => stop("LocalBusinessOriginalUnavailable"))
  let crypto = self.inner_library.unwrap_or_else(() => {
    stop("LocalBusinessOriginalUnavailable")
  })
  let original = local_submission_start(
    host,
    settings,
    crypto,
    sqlite,
    publication.environment,
    input_root,
    operation,
    child,
    public_run=true,
    business=Some(publication),
  )
  let (result, correlation) = local_quick_query_result(original, format)
  try {
    let selected = self.prepare_original_result(
      host,
      capture,
      settings,
      configuration_name,
      runtime,
      sqlite,
      result,
      publication=Some(publication),
    )
    local_public_result(
      host,
      settings,
      crypto,
      sqlite,
      result,
      prepared=Some(selected),
      material_table=presentation == "table",
    )
  } catch {
    ClientStop(issue) => stop(issue + correlation)
  }
}

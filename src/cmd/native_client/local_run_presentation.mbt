///|
// Output options are presentation metadata over one original Run, not another
// Program, submission, File grant, receipt kind or retry instruction.
fn local_run_presentation_requested(child : @argparse.Matches) -> Bool {
  ["output", "deliver", "receipt"].any(name => child.values.contains(name))
}

///|
fn local_run_presentation_result(
  child : @argparse.Matches,
  delivery : LocalResultDeliverySelection,
  original : String,
) -> (@argparse.Matches, String) raise ClientStop {
  let root = @decode.open_object(local_input_cursor(original)).unwrap_or_else(() => {
    stop("LocalOriginalRunStateUnavailable")
  })
  let id = run_text(root, "run_id")
  let correlation = " originalRunId=" +
    encode_request_json(Json::string(id), 8192) +
    " (observe this Run; do not repeat the Program submission)"
  if !@publication.run_wait_ready_until(
      original,
      None,
      @publication.Final,
      65536,
      8192,
      64,
    ).unwrap_or_else(() => {
      stop("LocalOriginalRunStateUnavailable" + correlation)
    }) {
    stop("LocalRunResultDeliveryNotReady" + correlation)
  }
  let arguments = ["result"]
  if delivery.json {
    arguments.push("--json")
  }
  if child.values.contains("deliver") {
    for file in delivery.files {
      arguments.push("--deliver")
      arguments.push(
        file.result_name.unwrap() + "=" + file.format + ":" + file.path,
      )
    }
  } else {
    arguments.push("--format")
    arguments.push("jsonl")
    arguments.push("--output")
    arguments.push(delivery.files[0].path)
  }
  arguments.push("--")
  arguments.push(id)
  let selected = command().parse(argv=arguments[:], env=Map([])) catch {
    _ => stop("LocalRunResultSelectionUnavailable" + correlation)
  }
  (selected.subcommand.unwrap().1, correlation)
}

///|
// Submit once, then use the actual same publication and independent current
// RunRead/Result File admissions. An export failure never replays the Program.
fn LocalCommandPreparationOriginal::execute_original_run_presentation(
  self : LocalCommandPreparationOriginal,
  host : @local_host.NativeLocalHostConnection,
  capture : @local_host.NativeLocalJournalCapture,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  sqlite : @local_sqlite.Library,
  configuration_name : String,
  runtime : LocalPackagedRuntime,
  input_root : String,
  operation : String,
  child : @argparse.Matches,
  selection : LocalCommandBusinessPreparation,
) -> String raise ClientStop {
  let directory = @env.current_dir().unwrap_or_else(() => {
    stop("ProjectConfigurationDirectoryUnavailable")
  })
  let delivery = local_result_delivery_selection(
    child,
    directory,
    run_presentation=true,
  )
  let original = local_submission_start(
    host,
    settings,
    crypto,
    sqlite,
    selection.environment,
    input_root,
    operation,
    child,
    public_run=true,
    business=Some(selection),
  )
  if !local_run_presentation_requested(child) {
    return original
  }
  let root = @decode.open_object(local_input_cursor(original)).unwrap_or_else(() => {
    stop("LocalOriginalRunStateUnavailable")
  })
  let correlation = " originalRunId=" +
    encode_request_json(Json::string(run_text(root, "run_id")), 8192) +
    " (observe this Run; do not repeat the Program submission)"
  try {
    if delivery.receipt is Some(path) {
      guard self.business is Some(business) &&
        business.run_receipt_original is Some(observed) else {
        stop("LocalRunReceiptOriginalUnavailable")
      }
      let location = local_result_file_location(path)
      let receipt = observed
        .original_run_receipt_for_export(
          path,
          location.parent_path,
          location.directory_name,
        )
        .unwrap_or_else(() => stop("LocalRunReceiptReadUnavailable"))
      // This is the already issued run_receipt contract, never a Result
      // delivery receipt or a freshly reconstructed reference/outcome object.
      local_write_result_receipt(
        path,
        @publication.publication_contract_json(receipt),
        crypto,
      )
      let current = observed
        .original_run_receipt_for_export(
          path,
          location.parent_path,
          location.directory_name,
        )
        .unwrap_or_else(() => stop("LocalRunReceiptReadUnavailable"))
      if @publication.publication_contract_identity(current) !=
        @publication.publication_contract_identity(receipt) {
        stop("LocalRunReceiptOriginalChanged")
      }
    }
    if delivery.files.is_empty() {
      return original
    }
    let (result, _) = local_run_presentation_result(child, delivery, original)
    let selected = self.prepare_original_result(
      host,
      capture,
      settings,
      configuration_name,
      runtime,
      sqlite,
      result,
      publication=Some(selection),
    )
    let delivered = local_public_result(
      host,
      settings,
      crypto,
      sqlite,
      result,
      prepared=Some(selected),
    )
    if delivery.json {
      delivered
    } else {
      original
    }
  } catch {
    ClientStop(issue) => stop(issue + correlation)
  }
}

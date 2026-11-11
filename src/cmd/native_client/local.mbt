///|
/// Explicit operator configuration is read only from the selected root. No
/// document, URI or failed Remote negotiation can select an embedded engine.
fn local_configuration(text : String) -> (String, String) raise ClientStop {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: 65536,
      max_nodes: 4096,
      max_depth: 16,
    }) {
    Ok(value) => value
    Err(_) => stop("InvalidLocalConfiguration")
  }
  let root = match
    @decode.admit(source, {
      max_nodes: 4096,
      max_depth: 16,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => stop("InvalidLocalConfiguration")
  }
  let object = match
    @decode.closed_object(root, [
      "version", "native", "state_dir", "account_config",
    ]) {
    Ok(value) => value
    Err(_) => stop("InvalidLocalConfiguration")
  }
  let text_field = fn(object, key) {
    @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
  }
  guard text_field(object, "version") == Some("actql-config/0.1") &&
    @decode.lookup(object, "native") is Some(native) else {
    stop("InvalidLocalConfiguration")
  }
  if @decode.lookup(object, "state_dir") is Some(value) &&
    @decode.text(value) is Err(_) {
    stop("InvalidLocalConfiguration")
  }
  let native = match
    @decode.closed_object(native, ["check_environment", "local"]) {
    Ok(value) => value
    Err(_) => stop("InvalidLocalConfiguration")
  }
  guard @decode.lookup(native, "check_environment") is Some(environment) else {
    stop("InvalidLocalConfiguration")
  }
  let environment = match
    @decode.closed_object(environment, ["file", "evidence_bundle_cid"]) {
    Ok(value) => value
    Err(_) => stop("InvalidLocalConfiguration")
  }
  guard text_field(environment, "file") is Some(file) &&
    !file.is_empty() &&
    text_field(environment, "evidence_bundle_cid") is Some(cid) else {
    stop("InvalidLocalConfiguration")
  }
  (file, cid)
}

///|
fn local_input_cursor(text : String) -> @decode.Cursor raise ClientStop {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => stop("LocalInputNotAdmitted")
  }
  match
    @decode.admit(source, {
      max_nodes: 8192,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => stop("LocalInputNotAdmitted")
  }
}

///|
/// Preparation is not a public verified report or a dispatch permit. Run,
/// publication and Checkpoint operations require their durable Owner bindings.
fn execute_native_local(matches : @argparse.Matches) -> String raise ClientStop {
  if optional(matches, "state-dir") is Some(_) &&
    matches.sources.get("config-file") is Some(@argparse.Argv) {
    stop("ConflictingLocalInstallationSelection")
  }
  for
    name in [
      "endpoint", "connection-root", "connection-file", "token-root", "token-file",
      "http-library", "ca", "cert", "key",
    ] {
    if optional(matches, name) is Some(_) {
      stop("Local mode cannot use Remote connection options")
    }
  }
  guard matches.subcommand is Some((operation, child)) else {
    stop("LocalOperationUnavailable")
  }
  if operation == "run" {
    if local_run_presentation_requested(child) &&
      command_preparation_invocation.val is None {
      stop("LocalRunPresentationOriginalUnavailable")
    }
    // A public command spelling, not a new intent/admission/retry operation.
    // Preserve the original AQL envelope and explicitly saved identities.
    let original_operation = local_run_original_operation()
    let reply = if optional(matches, "config-file") is None {
      execute_native_local_product(matches, original_operation)
    } else {
      execute_native_local_adoption(matches, original_operation, child)
    }
    return if command_preparation_invocation.val is Some(_) {
      reply
    } else {
      local_run_reply(child, reply)
    }
  }
  if optional(matches, "config-file") is None {
    if !local_product_operation(operation) {
      stop("LocalOperationUnavailable")
    }
    return execute_native_local_product(matches, operation)
  }
  if operation == "check" ||
    operation == "adopt" ||
    operation == "connect" ||
    operation == "upgrade-policy" ||
    operation == "lookup-policy-upgrade" ||
    operation == "new-submission" ||
    operation == "lookup-submission" ||
    operation == "lookup-request" ||
    operation == "status" ||
    operation == "checkpoint-state" ||
    operation == "lookup-preparation-grant" ||
    operation == "lookup-preparation-raw" ||
    operation == "lookup-cancellation" ||
    operation == "cancel" ||
    operation == "delivery-attempt" ||
    operation == "read" ||
    operation == "result" ||
    operation == "start" ||
    operation == "sql" ||
    operation == "aql" {
    return execute_native_local_adoption(matches, operation, child)
  }
  if operation != "check" && operation != "explain" {
    stop("LocalOperationUnavailable")
  }
  let root = required(matches, "config-root")
  let input_root = local_document_root(matches, root)
  let (environment_file, evidence_cid) = local_configuration(
    text_file(root, required(matches, "config-file"), 65536L),
  )
  let environment = match
    local_admitted_check_environment(
      text_file(root, environment_file, 65536L),
      evidence_cid,
    ) {
    Some(value) => value
    None => stop("InvalidLocalCheckEnvironment")
  }
  local_explain_for_environment(environment, input_root, child)
}

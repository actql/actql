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
  if optional(matches, "config-file") is None {
    if !local_product_operation(operation) {
      stop("LocalOperationUnavailable")
    }
    return execute_native_local_product(matches, operation)
  }
  if operation == "adopt" ||
    operation == "connect" ||
    operation == "upgrade-policy" ||
    operation == "lookup-policy-upgrade" ||
    operation == "new-submission" ||
    operation == "lookup-submission" ||
    operation == "checkpoint-state" ||
    operation == "lookup-preparation-grant" ||
    operation == "lookup-preparation-raw" ||
    operation == "lookup-cancellation" ||
    operation == "cancel" ||
    operation == "delivery-attempt" ||
    operation == "read" ||
    operation == "start" ||
    operation == "aql" {
    return execute_native_local_adoption(matches, operation, child)
  }
  if operation != "check" {
    stop("LocalOperationUnavailable")
  }
  let root = required(matches, "config-root")
  let input_root = local_document_root(matches, root)
  let (environment_file, evidence_cid) = local_configuration(
    text_file(root, required(matches, "config-file"), 65536L),
  )
  let environment = match
    @run_host.admit_client_check_environment(
      text_file(root, environment_file, 65536L),
      evidence_cid,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ) {
    Some(value) => value
    None => stop("InvalidLocalCheckEnvironment")
  }
  let format = match @frontend.select_format(required(child, "format")) {
    Ok(value) => value
    Err(_) => stop("UnsupportedLocalSourceFormat")
  }
  let supplied = optional(child, "parameters-file").map(name => {
    local_input_cursor(text_file(input_root, name, 65536L))
  })
  let declarations = match optional(child, "parameter-declarations-file") {
    None => None
    Some(name) => {
      if format != Text && format != Sql {
        stop("external declarations require aql-text or sql")
      }
      let source = local_input_cursor(text_file(input_root, name, 65536L))
      match
        @parameters.read_declarations(Some(source), {
          max_parameters: 1024,
          max_nodes: 8192,
          max_depth: 64,
          max_text_bytes: 65536,
        }) {
        Ok(value) => Some(value)
        Err(_) => stop("LocalDeclarationsNotAdmitted")
      }
    }
  }
  let context = match
    @frontend.bind_query_context(
      [],
      @checked.checking_environment_cid(environment),
      parameter_declarations=declarations,
      model_tasks=@checked.checking_environment_model_tasks(environment),
    ) {
    Ok(value) => value
    Err(_) => stop("InvalidLocalQueryContext")
  }
  let prepared = match
    @local_host.prepare_native_client_program(
      text_file(input_root, required(child, "program-file"), 65536L),
      format,
      environment,
      supplied,
      Some(context),
      [],
      @run_host.client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(_) => stop("LocalPreparationNotReady")
  }
  // Only static identity is returned. No Run or Result grant is fabricated.
  let (identity, effectful) = match prepared {
    Computation(value) => (@run_host.prepared_client_identity(value), false)
    EffectComputation(value) =>
      (@run_host.prepared_client_effect_identity(value), true)
  }
  if !child.flags.get("json").unwrap_or(false) {
    return "Local Program prepared; no Run has been admitted.\n" +
      "Program: " +
      identity.program_definition_cid +
      "\n" +
      "Parameters: " +
      identity.parameter_values_cid +
      "\n" +
      "Effectful: " +
      effectful.to_string()
  }
  encode_request_json(
    Json::object(
      Map([
        ("kind", Json::string("prepared")),
        ("mode", Json::string("local")),
        ("programDefinitionCid", Json::string(identity.program_definition_cid)),
        ("parameterValuesCid", Json::string(identity.parameter_values_cid)),
        ("effectful", Json::boolean(effectful)),
      ]),
    ),
    4096,
  )
}

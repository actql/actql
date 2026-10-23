///|
// Presentation selection only. Names must come from the actual committed
// Manifest, never a Policy allowlist or a current project declaration.
fn local_result_name(
  original_names : String,
  requested : String?,
) -> String raise ClientStop {
  guard @decode.elements(local_input_cursor(original_names)) is Ok(items) else {
    stop("LocalResultInventoryUnavailable")
  }
  let names : Map[String, Bool] = Map([])
  let mut sole = ""
  for item in items {
    guard @decode.text(item) is Ok(name) &&
      !name.is_empty() &&
      name.length() <= 128 &&
      !names.contains(name) else {
      stop("LocalResultInventoryUnavailable")
    }
    names[name] = true
    sole = name
  }
  match requested {
    Some(name) => {
      if !names.contains(name) {
        stop("LocalResultNotDeclared")
      }
      name
    }
    None => {
      if names.length() != 1 {
        stop("LocalResultNameRequired")
      }
      sole
    }
  }
}

///|
fn local_result_format(child : @argparse.Matches) -> String raise ClientStop {
  let format = optional(child, "format").unwrap_or("jsonl")
  if !(format == "jsonl" || format == "json" || format == "csv") {
    stop("InvalidLocalReadSelection")
  }
  format
}

///|
// File delivery needs its actual Writer/egress adapter and receipt custody.
// A stdout grant is never redirected or relabelled as file delivery.
fn local_result_stdout_only(child : @argparse.Matches) -> Unit raise ClientStop {
  for name in ["output", "deliver", "receipt"] {
    if child.values.contains(name) {
      stop("LocalResultFileDeliveryUnavailable")
    }
  }
  if child.flags.get("json").unwrap_or(false) {
    stop("LocalResultJsonEnvelopeUnavailable")
  }
}

///|
// Read the same original Run and same Store; none of these metadata suppliers
// issues current permission, a new Run or an available-payload observation.
fn local_public_result(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  sqlite : @local_sqlite.Library,
  child : @argparse.Matches,
  prepared? : LocalCommandResultOriginal? = None,
  material_table? : Bool = false,
) -> String raise ClientStop {
  native_timing_begin(6)
  defer native_timing_end(6)
  let directory = @env.current_dir().unwrap_or_else(() => {
    stop("ProjectConfigurationDirectoryUnavailable")
  })
  let delivery = local_result_delivery_selection(child, directory)
  if delivery.files.is_empty() {
    local_result_stdout_only(child)
  }
  if material_table && !delivery.files.is_empty() {
    stop("ConflictingLocalResultDelivery")
  }
  let format = local_result_format(child)
  let file = settings.read_file.unwrap_or_else(() => {
    stop("LocalReadPolicyOriginalNotSelected")
  })
  let (scope, original) = match prepared {
    Some(actual) => {
      if !physical_equal(actual.host, host) ||
        !actual.owner.journal_read_open ||
        actual.owner.closing ||
        actual.owner.closed {
        stop("LocalReadOriginalCustodyUnavailable")
      }
      local_result_host_value(
        actual.capture.check_current_in_original_read(),
        "selected read current",
      )
      (actual.scope, actual.original)
    }
    None => {
      let scope = local_host_result(
        host.authority_scope_cid(
          settings.principal,
          settings.connection,
          crypto,
        ),
      )
      let original = match
        host.lookup_submitted_run_original_by_id(
          crypto,
          settings.principal,
          settings.connection,
          required(child, "run"),
        ) {
        Ok(value) => value
        Err(issue) => stop(local_saved_state_issue(issue))
      }
      // Missing saved state is not inferred from an index or repaired.
      match
        host.lookup_submitted_run_state(
          crypto,
          settings.principal,
          settings.connection,
          original.reference(),
          original.request(),
          @env.now().to_double(),
        ) {
        Ok(_) => ()
        Err(issue) => stop(local_saved_state_issue(issue))
      }
      (scope, original)
    }
  }
  let reference = local_original_run_reference(original.definition(), scope)
  guard reference is Object(fields) else { stop("LocalOriginalRunUnavailable") }
  let selected : LocalOriginalRunSelection = {
    request: original.request(),
    submission: original.reference(),
    reference,
    namespace_id: json_text(fields, "namespaceId").unwrap_or_else(() => {
      stop("LocalOriginalRunUnavailable")
    }),
    run_definition_cid: json_text(fields, "runDefinitionCid").unwrap_or_else(() => {
      stop("LocalOriginalRunUnavailable")
    }),
  }
  let binding = match prepared {
    Some(actual) if material_table => {
      if !settings.installation_files.contains("material-read.json") {
        stop("LocalResultMaterialOriginalNotSelected")
      }
      match
        actual.capture.bind_result_material_read_policy_for_run_in_original_read(
          actual.policy,
          original.reference(),
          original.request(),
          @env.now().to_double(),
          "material-read.json",
        ) {
        Ok(value) => value
        Err(issue) => stop(local_read_issue(issue))
      }
    }
    None if material_table => stop("LocalResultMaterialOriginalUnavailable")
    Some(actual) => actual.binding
    None =>
      local_read_binding_for_original(
        host~,
        settings~,
        crypto~,
        file~,
        selected~,
      )
  }
  let parameters = match binding.disclosure_parameters() {
    Ok(value) => value
    Err(issue) => stop(local_read_issue(issue))
  }
  let purpose = parameters.purpose
  let max_output = parameters.max_output_bytes
  // One fresh correlation value for this invocation; never retry an attempt.
  let attempt_id = local_generation_cid(crypto)
  let store = match prepared {
    Some(actual) => actual.store
    None =>
      local_original_result_store(host, settings, sqlite, selected.namespace_id)
  }
  let reply = {
    // A supplied Store stays with the original command carrier, including
    // errors before a session exists. Only the legacy constructor closes here.
    errdefer (if prepared is None {
      local_result_store_close(store, attempt_id)
    })
    let names_result = match prepared {
      None =>
        host.lookup_original_result_names_json(
          crypto,
          settings.principal,
          settings.connection,
          original,
          store,
          selected.namespace_id,
        )
      Some(actual) =>
        local_result_host_value(
          actual.capture.lookup_original_result_names_json_in_original_read(
            settings.principal,
            settings.connection,
            original,
            store,
            selected.namespace_id,
          ),
          "publication inventory",
        )
    }
    let names = match names_result {
      Ok(Some(value)) => value
      Ok(None) => stop("LocalResultPublicationUnavailable")
      Err(issue) => stop(local_saved_state_issue(@local_host.Journal(issue)))
    }
    if !delivery.files.is_empty() {
      guard prepared is Some(actual) else {
        stop("LocalResultFileOriginalUnavailable")
      }
      return local_result_file_deliveries(
        host, settings, crypto, child, actual, selected, names, delivery,
      )
    }
    let result_name = local_result_name(names, optional(child, "result"))
    let current = () => {
      local_delivery_lookup_allowed(
        host,
        settings,
        crypto,
        scope,
        result_name,
        capture=prepared.map(value => value.capture),
      )
    }
    if !current() {
      stop("LocalReadAuthorizationDenied")
    }
    let request : @local_result.NativeResultAccessRequest = {
      namespace_id: selected.namespace_id,
      authority_scope_cid: scope,
      run_definition_cid: selected.run_definition_cid,
      principal_id: settings.principal,
      purpose,
      result_name,
      format,
      attempt_id,
    }
    let material = if material_table {
      guard prepared is Some(actual) &&
        actual.owner.business is Some(business) &&
        business.result_binding is None &&
        business.result_material is None else {
        stop("LocalReadOriginalCustodyUnavailable")
      }
      // Retain the selected binding before workspace/current admission can
      // fail. Its receiver and this carrier preserve the same partial child.
      business.result_binding = Some(binding)
      let receiver = match
        binding.prepare_material_receiver(
          selected.request,
          store,
          request,
          local_generation_cid(crypto),
          local_utc_now(),
          1000,
          max_output,
          128,
          Int::min(16384, max_output),
        ) {
        Ok(value) => value
        Err(issue) => stop(local_read_issue(issue))
      }
      business.result_material = Some(receiver)
      Some(receiver)
    } else {
      None
    }
    match
      binding.authorize_read_request(
        selected.request,
        request,
        local_utc_now(),
        max_output_bytes=Some(max_output),
      ) {
      Ok(_) => ()
      Err(issue) => stop(local_read_issue(issue))
    }
    local_admitted_result_stream(
      host~,
      settings~,
      selected~,
      binding~,
      request~,
      scope~,
      purpose~,
      result_name~,
      format~,
      attempt_id~,
      max_output~,
      current~,
      store~,
      retained=prepared.map(value => value.owner.business.unwrap()),
      captured_selection=prepared.map(value => value.original),
      material~,
    )
  }
  if prepared is None {
    local_result_store_close(store, attempt_id)
  }
  reply
}

///|
// Only the output boundary: a Local sink has already written payload bytes.
// This does not observe Run completion, publication or a delivery receipt.
fn local_payload_already_streamed(matches : @argparse.Matches) -> Bool {
  match matches.subcommand {
    Some(("result", child)) if child.flags.get("json").unwrap_or(false) => false
    Some(("read", _)) | Some(("result", _)) | Some(("sql", _)) =>
      matches.values.get("mode") == Some(["local"])
    Some(("aql", child)) =>
      child.values.contains("query") &&
      matches.values.get("mode") == Some(["local"])
    _ => false
  }
}

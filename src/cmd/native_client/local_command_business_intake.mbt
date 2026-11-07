///|
// Observed producer storage in the SAME existing Request. Whole-file and
// escaped-wire bounds are checked before constructors; no policy is raised.
fn LocalCommandPreparationOriginal::reserve_business_intake(
  self : LocalCommandPreparationOriginal,
  units : Int64,
) -> Unit raise ClientStop {
  guard self.business is Some(business) &&
    business.request_input is Some(input) &&
    business.request_parent is Some(parent) &&
    business.active &&
    units >= 0L &&
    units <= (2147483518L - 1024L) / 6L - business.request_intake_units else {
    stop("LocalInputExtentUnavailable")
  }
  // Keep this original observation before a grow/current callback can fail.
  business.request_intake_units += units
  let maximum = business.request_intake_units * 6L + 1024L
  match
    @local_values.reserve_request_native_intake_wire(
      parent,
      input,
      maximum.to_int(),
    ) {
    Err(issue) => {
      self.retain_primary(CommandRequestPreparation(issue))
      stop("LocalInputCapacityUnavailable")
    }
    Ok(_) => ()
  }
}

///|
fn LocalCommandPreparationOriginal::business_input_text(
  self : LocalCommandPreparationOriginal,
  input : LocalCommandBusinessInput,
  selected : String,
  json : Bool,
) -> String raise ClientStop {
  guard self.business is Some(business) &&
    business.request_input is Some(original) &&
    physical_equal(original, input) &&
    business.request_read_failure is None else {
    stop("LocalBusinessOriginalUnavailable")
  }
  // Paths are original argument DATA. The Request's fixed entry is already
  // backed; reserve their actual variable storage before path resolution.
  self.reserve_business_intake(
    input.root.length().to_int64() + selected.length().to_int64(),
  )
  let location = local_input_file_location(input.root, selected)
  let text = match
    @files.read_observed_ordinary_text_file_in_current_read_context_with_custody(
      location.root,
      location.name,
      self.profile.diagnostic_ceiling,
      bytes => {
        try {
          self.reserve_business_intake(bytes)
          true
        } catch {
          ClientStop(_) => false
        }
      },
    ) {
    Err(failure) => {
      business.request_read_failure = Some(failure)
      stop("LocalInputReadUnavailable")
    }
    Ok(text) => text
  }
  if json {
    let bytes = @utf8.encode(text)
    match
      @source.parse_json_bytes_preserving(bytes, {
        max_input_bytes: bytes.length(),
        max_nodes: 8192,
        max_depth: 32,
      }) {
      Err(_) => stop("InvalidLocalInputJson")
      Ok(_) => ()
    }
  }
  text
}

///|
// One original String serialization. Unlike the old whole Map/Json capture,
// raw JSON files need no second detached native tree before intent admission.
fn local_business_quote_input(text : String) -> String raise ClientStop {
  let bound = text.length().to_int64() * 6L + 2L
  if bound >= 2147483519L {
    stop("LocalInputExtentUnavailable")
  }
  let writer = @encode.writer(bound.to_int(), 8192, 32) catch {
    _ => stop("LocalInputEncodingUnavailable")
  }
  try {
    @encode.emit_json(Json::string(text), writer)
    @encode.finish(writer)
  } catch {
    _ => stop("LocalInputEncodingUnavailable")
  }
}

///|
fn LocalCommandPreparationOriginal::construct_business_intent(
  self : LocalCommandPreparationOriginal,
) -> @run_host.ClientSubmittedIntent raise ClientStop {
  guard self.business is Some(business) &&
    business.request_input is Some(input) &&
    business.active &&
    business.request_parent is Some(_) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  if input.retained_intent is Some(intent) {
    return intent
  }
  let child = input.arguments
  let operation = input.operation
  let query = local_quick_query_requested(operation, child)
  let program = if operation == "start" {
    self.business_input_text(input, required(child, "program-file"), true)
  } else {
    let format = if query {
      if operation == "sql" {
        "sql"
      } else {
        "aql-text"
      }
    } else {
      required(child, "format")
    }
    guard @frontend.select_format(format) is Ok(_) else {
      stop("UnsupportedLocalSourceFormat")
    }
    let text = if query {
      let text = required(child, "query")
      self.reserve_business_intake(text.length().to_int64() * 3L)
      text
    } else {
      self.business_input_text(input, required(child, "program-file"), false)
    }
    let declarations = match optional(child, "parameter-declarations-file") {
      None => ""
      Some(file) => {
        if format != "aql-text" && format != "sql" {
          stop("external declarations require aql-text or sql")
        }
        ",\"parameterDeclarations\":" +
        self.business_input_text(input, file, true)
      }
    }
    "{\"text\":" +
    local_business_quote_input(text) +
    ",\"format\":" +
    local_business_quote_input(format) +
    declarations +
    "}"
  }
  let parameters = match optional(child, "parameters-file") {
    Some(file) => self.business_input_text(input, file, true)
    None => "null"
  }
  let stop_before = match native_requested_stop_before(child) {
    Some(value) => ",\"stopBefore\":" + local_business_quote_input(value)
    None => ""
  }
  let wire = "{\"kind\":\"" +
    (if operation == "start" { "program" } else { "aql" }) +
    "\",\"input\":" +
    program +
    ",\"parameters\":" +
    parameters +
    stop_before +
    (if query { ",\"readOnly\":true}" } else { "}" })
  let bound = wire.length().to_int64() * 3L
  if bound >= 2147483519L {
    stop("LocalInputExtentUnavailable")
  }
  @run_host.prepare_client_submitted_intent(wire, bound.to_int(), 8192, 64).unwrap_or_else(() => {
      stop("LocalSubmittedInputNotAdmitted")
    },
  )
}

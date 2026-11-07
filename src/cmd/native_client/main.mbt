///|
priv suberror ClientStop {
  ClientStop(String)
}

///|
#borrow(bytes)
extern "C" fn write_stdout_ffi(bytes : Bytes, length : Int) -> Bool = "actql_native_client_write_stdout"

///|
#borrow(bytes)
extern "C" fn fail_ffi(bytes : Bytes, length : Int) -> Unit = "actql_native_client_fail"

///|
fn fail_command(message : String) -> Unit {
  let bytes = @utf8.encode(
    local_command_diagnostic_text(
      "ACTQL_E_COMMAND_FAILED",
      message,
      command_diagnostic_json.val,
    ),
  )
  fail_ffi(bytes, bytes.length())
}

///|
fn fail_cleanup_command(message : String) -> Unit {
  let bytes = @utf8.encode(
    local_command_diagnostic_text(
      "ACTQL_E_CLEANUP_PENDING",
      message,
      command_diagnostic_json.val,
    ),
  )
  fail_ffi(bytes, bytes.length())
}

///|
fn[T] stop(message : String) -> T raise ClientStop {
  raise ClientStop(message)
}

///|
fn required(
  matches : @argparse.Matches,
  name : String,
) -> String raise ClientStop {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => stop("missing or repeated option --" + name)
  }
}

///|
fn optional(
  matches : @argparse.Matches,
  name : String,
) -> String? raise ClientStop {
  match matches.values.get(name) {
    None => None
    Some([value]) if !value.is_empty() => Some(value)
    _ => stop("invalid or repeated option --" + name)
  }
}

///|
fn positive_int(value : String, name : String) -> Int raise ClientStop {
  let parsed : Int = @string.from_str(value) catch {
    _ => stop("invalid integer option --" + name)
  }
  if parsed <= 0 {
    stop("invalid integer option --" + name)
  }
  parsed
}

///|
fn cancellation_revision(value : String) -> Int raise ClientStop {
  let parsed : Int = @string.from_str(value) catch {
    _ => stop("invalid integer option --expected-revision")
  }
  if parsed < 0 {
    stop("invalid integer option --expected-revision")
  }
  parsed
}

///|
fn text_file(
  root : String,
  name : String,
  maximum : Int64,
) -> String raise ClientStop {
  if command_preparation_invocation.val is Some(original) {
    return command_preparation_result(
      original.text_file(root, name, maximum),
      stage=Some("configuration-read"),
    )
  }
  if initial_crypto_invocation.val is Some(original) && original.scope_open {
    return local_initial_crypto_text_file(original, root, name, maximum)
  }
  match @files.read_bounded_text_file(root, name, maximum) {
    Ok(value) => value
    Err(_) => stop("failed to read bounded file " + name)
  }
}

///|
fn json_file(
  root : String,
  name : String,
  maximum : Int64,
) -> Json raise ClientStop {
  json_file_text(text_file(root, name, maximum), name, maximum)
}

///|
fn json_file_text(
  text : String,
  name : String,
  maximum : Int64,
) -> Json raise ClientStop {
  native_timing_count(17)
  match
    @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: maximum.to_int(),
      max_nodes: 8192,
      max_depth: 32,
    }) {
    Ok(_) => @json.parse(text) catch { _ => stop("invalid JSON file " + name) }
    Err(error) =>
      match error.issue {
        InputLimit | NodeLimit | DepthLimit =>
          stop("JSON file exceeds configured bounds " + name)
        _ => stop("invalid JSON file " + name)
      }
  }
}

///|
fn endpoint_url(value : String) -> String raise ClientStop {
  if !value.has_prefix("https://") ||
    value.length() > 4096 ||
    value.contains("?") ||
    value.contains("#") ||
    value.contains("@") {
    stop("invalid Client Host endpoint")
  }
  let authority = value[8:]
  let authority = if authority.has_suffix("/") {
    authority[:authority.length() - 1]
  } else {
    authority
  }
  if authority.is_empty() ||
    authority.contains("/") ||
    authority.contains("\\") ||
    authority.contains(" ") {
    stop("invalid Client Host endpoint")
  }
  "https://" + authority.to_owned() + "/"
}

///|
fn json_text(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn confirmed_profile(wire : String, connection : Json) -> Json raise ClientStop {
  let profile = @json.parse(wire) catch {
    _ => stop("invalid Client Host profile")
  }
  match wire_profile_issue(profile, connection) {
    Some(RequestedValueUnavailable) =>
      stop("requested durable profile is unavailable")
    Some(InvalidShape) | Some(ConnectionMismatch) =>
      stop("invalid Client Host profile")
    None => ()
  }
  profile
}

///|
fn admitted_run(wire : String, connection : Json) -> Bool {
  let value = @json.parse(wire) catch { _ => return false }
  wire_admission(value, connection)
}

///|
fn valid_reference(value : Json) -> Bool {
  wire_run_ref_shape(value)
}

///|
fn attached_reference_matches(
  request_wire : Bytes,
  reply_wire : String,
) -> Bool {
  let request_text = @utf8.decode(request_wire) catch { _ => return false }
  let request = @json.parse(request_text) catch { _ => return false }
  let reply = @json.parse(reply_wire) catch { _ => return false }
  guard request is Object(request_fields) &&
    request_fields.get("ref") is Some(requested_ref) &&
    reply is Object(reply_fields) &&
    reply_fields.get("ref") is Some(returned_ref) &&
    valid_reference(requested_ref) &&
    valid_reference(returned_ref) else {
    return false
  }
  guard requested_ref is Object(requested) && returned_ref is Object(returned) else {
    return false
  }
  json_text(requested, "namespaceId") == json_text(returned, "namespaceId") &&
  json_text(requested, "authorityScopeCid") ==
  json_text(returned, "authorityScopeCid") &&
  json_text(requested, "runDefinitionCid") ==
  json_text(returned, "runDefinitionCid")
}

///|
// The requested operation is reconstructed only from the bytes this command
// submitted. Numeric JSON spellings never change its integer revision.
fn cancellation_reference(request_wire : Bytes) -> Json? {
  let text = @utf8.decode(request_wire) catch { _ => return None }
  let value = @json.parse(text) catch { _ => return None }
  guard value is Object(fields) &&
    fields.get("ref") is Some(Object(reference)) &&
    fields.get("cancelId") is Some(cancel_id) &&
    fields.get("expectedRevision") is Some(revision) else {
    return None
  }
  let combined : Map[String, Json] = Map([])
  for key, value in reference {
    combined[key] = value
  }
  combined["cancelId"] = cancel_id
  combined["expectedRevision"] = revision
  let result = Json::object(combined)
  if wire_cancellation_ref_shape(result) {
    Some(result)
  } else {
    None
  }
}

///|
fn same_cancellation_target(
  left : Map[String, Json],
  right : Map[String, Json],
) -> Bool {
  json_text(left, "namespaceId") == json_text(right, "namespaceId") &&
  json_text(left, "authorityScopeCid") == json_text(right, "authorityScopeCid") &&
  json_text(left, "runDefinitionCid") == json_text(right, "runDefinitionCid")
}

///|
fn same_cancellation_reference(value : Json, expected : Json) -> Bool {
  guard wire_cancellation_ref_shape(value) &&
    wire_cancellation_ref_shape(expected) &&
    value is Object(actual) &&
    expected is Object(requested) &&
    actual.get("expectedRevision") is Some(Number(actual_revision, ..)) &&
    requested.get("expectedRevision") is Some(Number(requested_revision, ..)) else {
    return false
  }
  same_cancellation_target(actual, requested) &&
  json_text(actual, "cancelId") == json_text(requested, "cancelId") &&
  actual_revision == requested_revision
}

///|
fn valid_cancellation_outcome(value : Json, expected : Json) -> Bool {
  guard wire_cancellation_shape(value) &&
    value is Object(fields) &&
    expected is Object(requested) &&
    fields.get("cancelRef") is Some(cancel_ref) &&
    same_cancellation_reference(cancel_ref, expected) &&
    fields.get("ref") is Some(Object(reference)) &&
    same_cancellation_target(reference, requested) &&
    fields.get("revision") is Some(Number(revision, ..)) &&
    requested.get("expectedRevision") is Some(Number(original_revision, ..)) else {
    return false
  }
  revision >= original_revision &&
  (
    json_text(fields, "kind") != Some("accepted") ||
    revision > original_revision
  )
}

///|
fn valid_cancellation_reply(
  value : Json,
  request_wire : Bytes,
  lookup : Bool,
) -> Bool {
  guard cancellation_reference(request_wire) is Some(expected) else {
    return false
  }
  if !lookup {
    let request_text = @utf8.decode(request_wire) catch { _ => return false }
    let request = @json.parse(request_text) catch { _ => return false }
    guard wire_cancellation_attempt_shape(value) &&
      value is Object(fields) &&
      request is Object(requested) &&
      requested.get("attemptRef") is Some(attempt) &&
      fields.get("attemptRef") == Some(attempt) else {
      return false
    }
    match json_text(fields, "kind") {
      Some("accepted") | Some("already_satisfied") => {
        guard fields.get("cancellation") is Some(outcome) &&
          valid_cancellation_outcome(outcome, expected) &&
          outcome is Object(original) else {
          return false
        }
        if json_text(fields, "kind") == Some("accepted") {
          json_text(original, "kind") == Some("accepted")
        } else {
          json_text(original, "kind") == Some("already_requested") ||
          json_text(original, "kind") == Some("already_terminal")
        }
      }
      Some("refused") =>
        match fields.get("cancelRef") {
          None => true
          Some(reference) => same_cancellation_reference(reference, expected)
        }
      Some("conflict") =>
        fields.get("cancelRef") is Some(reference) &&
        same_cancellation_reference(reference, expected)
      _ => false
    }
  } else {
    guard wire_cancellation_lookup_shape(value) && value is Object(fields) else {
      return false
    }
    match json_text(fields, "kind") {
      Some("found") =>
        fields.get("cancellation") is Some(outcome) &&
        valid_cancellation_outcome(outcome, expected)
      Some("unknown") =>
        fields.get("cancelRef") is Some(reference) &&
        same_cancellation_reference(reference, expected)
      _ => false
    }
  }
}

///|
fn cancellation_unknown(request_wire : Bytes) -> String {
  guard cancellation_reference(request_wire) is Some(reference) else {
    return "CancellationUnknown"
  }
  let writer = @encode.writer(4096, 32, 4) catch {
    _ => return "CancellationUnknown"
  }
  let wire = try {
    @encode.emit_json(reference, writer)
    @encode.finish(writer)
  } catch {
    _ => return "CancellationUnknown"
  }
  "CancellationUnknown cancel-ref=" + wire + " lookup=lookup-cancellation"
}

///|
fn admitted_lookup_contract(
  name : String,
  value : Json,
  maximum : Int,
) -> @publication.PublicationContract? {
  let writer = @encode.writer(maximum, 8192, 32) catch { _ => return None }
  let wire = try {
    @encode.emit_json(value, writer)
    @encode.finish(writer)
  } catch {
    _ => return None
  }
  match @publication.admit_publication_contract(name, wire, maximum, 8192, 32) {
    Ok(contract) => Some(contract)
    Err(_) => None
  }
}

///|
fn valid_attempt_lookup(
  value : Json,
  request_wire : Bytes,
  maximum : Int,
) -> Bool {
  let request_text = @utf8.decode(request_wire) catch { _ => return false }
  let request = @json.parse(request_text) catch { _ => return false }
  guard request is Object(request_fields) &&
    request_fields.get("ref") is Some(Object(reference)) &&
    json_text(reference, "runDefinitionCid") is Some(run_definition) &&
    json_text(request_fields, "attemptId") is Some(attempt_id) &&
    json_text(request_fields, "resultName") is Some(result_name) &&
    value is Object(fields) else {
    return false
  }
  match json_text(fields, "kind") {
    Some("not_found") => fields.length() == 1
    Some("found") => {
      guard fields.length() == 4 &&
        fields.get("attempt") is Some(attempt_value) &&
        attempt_value is Object(attempt_fields) &&
        json_text(attempt_fields, "attempt_id") == Some(attempt_id) &&
        json_text(attempt_fields, "run_definition_cid") == Some(run_definition) &&
        json_text(attempt_fields, "result_name") == Some(result_name) &&
        admitted_lookup_contract("delivery_attempt", attempt_value, maximum)
        is Some(attempt) else {
        return false
      }
      match (fields.get("record"), fields.get("hostReleaseReceipt")) {
        (Some(Null), Some(Null)) => true
        (Some(record_value), Some(receipt_value)) => {
          guard record_value is Object(record_fields) &&
            admitted_lookup_contract("delivery_record", record_value, maximum)
            is Some(record) &&
            json_text(record_fields, "delivery_attempt_cid") ==
            Some(@publication.publication_contract_identity(attempt)) else {
            return false
          }
          if json_text(record_fields, "state") == Some("succeeded") {
            guard admitted_lookup_contract(
                "result_delivery_receipt", receipt_value, maximum,
              )
              is Some(receipt) else {
              return false
            }
            @publication.validate_delivery_success_evidence(
              attempt, receipt, record,
            )
            is Ok(_)
          } else {
            receipt_value is Null
          }
        }
        _ => false
      }
    }
    _ => false
  }
}

///|
fn encode_request_json(value : Json, maximum : Int) -> String raise ClientStop {
  let writer = @encode.writer(maximum, 8192, 32) catch {
    _ => stop("request exceeds configured bounds")
  }
  try {
    @encode.emit_json(value, writer)
    @encode.finish(writer)
  } catch {
    _ => stop("request exceeds configured bounds")
  }
}

///|
fn valid_submission_ref(value : Json) -> Bool {
  guard wire_submission_ref_shape(value) &&
    value is Object(reference) &&
    reference.get("epoch") is Some(epoch_value) &&
    wire_submission_epoch_shape(epoch_value) &&
    epoch_value is Object(epoch) &&
    json_text(epoch, "authorityScopeCid") is Some(authority) &&
    json_text(epoch, "epochNonce") is Some(epoch_nonce) &&
    epoch.get("notBefore") is Some(Number(not_before, ..)) &&
    epoch.get("expiresAt") is Some(Number(expires_at, ..)) &&
    json_text(reference, "nonce") is Some(nonce) else {
    return false
  }
  let admitted = match
    @request_scope.prepare_submission_epoch(
      authority, epoch_nonce, not_before, expires_at,
    ) {
    Ok(admitted) => admitted
    Err(_) => return false
  }
  @request_scope.submission_request_id(admitted, nonce) is Ok(_)
}

///|
fn valid_original_submission_reply(
  value : Json,
  request_wire : Bytes,
  selected : Json,
  lookup : Bool,
) -> Bool {
  if lookup {
    if !wire_submission_lookup_shape(value) {
      return false
    }
  } else if !wire_submission_outcome_shape(value) {
    return false
  }
  let text = @utf8.decode(request_wire) catch { _ => return false }
  let request = @json.parse(text) catch { _ => return false }
  guard request is Object(request_fields) &&
    value is Object(fields) &&
    request_fields.get("submissionRef") is Some(expected) &&
    valid_submission_ref(expected) &&
    fields.get("submissionRef") == Some(expected) else {
    return false
  }
  if !lookup && fields.get("intentCid") != request_fields.get("intentCid") {
    return false
  }
  let history = fields.get("unresolvedHistory")
  // A submit reply cannot introduce an acknowledgement the caller never sent.
  // Readonly lookup may return the original saved link, bound to this epoch.
  if !lookup && history != request_fields.get("unresolvedHistory") {
    return false
  }
  if history is Some(value) {
    guard wire_submission_restart_shape(value) &&
      value is Object(restart) &&
      restart.get("submissionRef") is Some(original) &&
      valid_submission_ref(original) &&
      original is Object(old_reference) &&
      old_reference.get("epoch") is Some(Object(old_epoch)) &&
      expected is Object(fresh_reference) &&
      fresh_reference.get("epoch") is Some(Object(fresh_epoch)) &&
      old_epoch.get("expiresAt") is Some(Number(old_expiry, ..)) &&
      fresh_epoch.get("expiresAt") is Some(Number(fresh_expiry, ..)) else {
      return false
    }
    if old_epoch.get("authorityScopeCid") !=
      fresh_epoch.get("authorityScopeCid") ||
      old_expiry >= fresh_expiry {
      return false
    }
  }
  match json_text(fields, "kind") {
    Some("ready") => {
      guard fields.get("admission") is Some(admission) &&
        wire_admission(admission, selected) &&
        admission is Object(admitted) &&
        admitted.get("ref") is Some(Object(run)) &&
        expected is Object(reference) &&
        reference.get("epoch") is Some(Object(epoch)) else {
        return false
      }
      run.get("authorityScopeCid") == epoch.get("authorityScopeCid")
    }
    Some("held") => {
      guard fields.get("held") is Some(held) &&
        expected is Object(reference) &&
        json_text(reference, "nonce") is Some(nonce) else {
        return false
      }
      wire_held(held, nonce) && wire_connection_shape(selected)
    }
    _ => true
  }
}

///|
fn valid_submission_reply(
  value : Json,
  request_wire : Bytes,
  selected : Json,
  lookup : Bool,
) -> Bool {
  if lookup {
    return valid_original_submission_reply(value, request_wire, selected, true)
  }
  guard wire_submission_attempt_shape(value) && value is Object(fields) else {
    return false
  }
  let text = @utf8.decode(request_wire) catch { _ => return false }
  let request = @json.parse(text) catch { _ => return false }
  guard request is Object(request_fields) &&
    fields.get("attemptRef") == request_fields.get("attemptRef") &&
    fields.get("attemptRef") is Some(Object(attempt)) &&
    json_text(attempt, "operation") == Some("submit") else {
    return false
  }
  if fields.get("outcome") is Some(original) {
    return valid_original_submission_reply(
      original, request_wire, selected, false,
    )
  }
  if json_text(fields, "kind") == Some("refused") &&
    json_text(fields, "reason") == Some("authorization") {
    return true
  }
  fields.get("submissionRef") == request_fields.get("submissionRef") &&
  fields.get("intentCid") == request_fields.get("intentCid")
}

///|
fn request_body(
  operation : String,
  child : @argparse.Matches,
  root : String,
  connection : Json,
  maximum : Int,
) -> Bytes raise ClientStop {
  let stop_before = if operation == "aql" || operation == "start" {
    native_requested_stop_before(child)
  } else {
    None
  }
  let fields : Map[String, Json] = Map([("connection", connection)])
  match operation {
    "connect" | "new-submission" => ()
    "aql" => {
      let format = required(child, "format")
      if format != "json" &&
        format != "yaml" &&
        format != "aql-json" &&
        format != "aql-yaml" &&
        format != "aql-text" &&
        format != "sql" {
        stop("unsupported AQL source format")
      }
      fields["submissionRef"] = json_file(
        root,
        required(child, "submission-ref-file"),
        8192L,
      )
      fields["kind"] = Json::string("aql")
      let source : Map[String, Json] = Map([
        (
          "text",
          Json::string(
            text_file(root, required(child, "program-file"), maximum.to_int64()),
          ),
        ),
        ("format", Json::string(format)),
      ])
      if optional(child, "parameter-declarations-file") is Some(name) {
        if format != "aql-text" && format != "sql" {
          stop("external declarations require aql-text or sql")
        }
        let declarations = json_file(root, name, maximum.to_int64())
        guard declarations is Object(_) else {
          stop("parameter declarations must be a JSON object")
        }
        source["parameterDeclarations"] = declarations
      }
      fields["input"] = Json::object(source)
      fields["parameters"] = match optional(child, "parameters-file") {
        Some(name) => json_file(root, name, maximum.to_int64())
        None => Json::null()
      }
    }
    "start" => {
      fields["submissionRef"] = json_file(
        root,
        required(child, "submission-ref-file"),
        8192L,
      )
      fields["kind"] = Json::string("program")
      fields["input"] = json_file(
        root,
        required(child, "program-file"),
        maximum.to_int64(),
      )
      fields["parameters"] = match optional(child, "parameters-file") {
        Some(name) => json_file(root, name, maximum.to_int64())
        None => Json::null()
      }
    }
    "lookup-submission" =>
      fields["submissionRef"] = json_file(
        root,
        required(child, "submission-ref-file"),
        8192L,
      )
    "lookup-request" =>
      fields["requestId"] = Json::string(required(child, "request-id"))
    "attach" | "status" | "reconcile" =>
      fields["ref"] = json_file(root, required(child, "ref-file"), 8192L)
    "cancel" | "lookup-cancellation" => {
      let reference = json_file(root, required(child, "ref-file"), 8192L)
      guard wire_run_ref_shape(reference) && reference is Object(original) else {
        stop("InvalidCancellationReference")
      }
      let cancel_id = Json::string(required(child, "cancel-id"))
      let revision = Json::number(
        cancellation_revision(required(child, "expected-revision")).to_double(),
      )
      let combined : Map[String, Json] = Map([])
      for key, value in original {
        combined[key] = value
      }
      combined["cancelId"] = cancel_id
      combined["expectedRevision"] = revision
      if !wire_cancellation_ref_shape(Json::object(combined)) {
        stop("InvalidCancellationReference")
      }
      fields["ref"] = reference
      fields["cancelId"] = cancel_id
      fields["expectedRevision"] = revision
      if operation == "cancel" {
        let attempt = Json::object(
          Map([
            ("operation", Json::string("cancel")),
            ("attemptId", Json::string(required(child, "operation-attempt-id"))),
          ]),
        )
        if !wire_operation_attempt_ref_shape(attempt) {
          stop("InvalidOperationAttemptReference")
        }
        fields["attemptRef"] = attempt
      }
    }
    "wait" => {
      fields["ref"] = json_file(root, required(child, "ref-file"), 8192L)
      fields["until"] = match optional(child, "until") {
        Some(value) => Json::string(value)
        None => Json::null()
      }
      fields["since"] = match optional(child, "since") {
        None => Json::null()
        Some(value) => {
          let revision : Int64 = @string.from_str(value) catch {
            _ => stop("InvalidWaitRevision")
          }
          if revision < 0L || revision > 9007199254740991L {
            stop("InvalidWaitRevision")
          }
          Json::number(revision.to_double())
        }
      }
    }
    "read" | "delivery-attempt" => {
      fields["ref"] = json_file(root, required(child, "ref-file"), 8192L)
      fields["resultName"] = Json::string(required(child, "result-name"))
      fields["attemptId"] = Json::string(required(child, "attempt-id"))
      if operation == "read" {
        fields["format"] = Json::string("jsonl")
      }
    }
    _ => stop("unsupported Client operation")
  }
  if stop_before is Some(boundary) {
    fields["stopBefore"] = Json::string(boundary)
  }
  if operation == "aql" ||
    operation == "start" ||
    operation == "lookup-submission" {
    guard fields.get("submissionRef") is Some(original) &&
      valid_submission_ref(original) else {
      stop("InvalidSubmissionRef")
    }
    if optional(child, "request-id") is Some(nonce) &&
      original is Object(reference) &&
      json_text(reference, "nonce") != Some(nonce) {
      stop("InvalidSubmissionRef")
    }
    if operation != "lookup-submission" {
      let attempt = Json::object(
        Map([
          ("operation", Json::string("submit")),
          ("attemptId", Json::string(required(child, "operation-attempt-id"))),
        ]),
      )
      if !wire_operation_attempt_ref_shape(attempt) {
        stop("InvalidOperationAttemptReference")
      }
      fields["attemptRef"] = attempt
      let intent : Map[String, Json] = Map([])
      for key in ["kind", "input", "parameters"] {
        intent[key] = fields[key]
      }
      if stop_before is Some(boundary) {
        intent["stopBefore"] = Json::string(boundary)
      }
      let original_wire = encode_request_json(Json::object(intent), maximum)
      let admitted = match
        @run_host.prepare_client_submitted_intent(
          original_wire, maximum, 8192, 32,
        ) {
        Ok(value) => value
        Err(@run_host.Limit) =>
          stop("submitted intent exceeds configured bounds")
        Err(_) => stop("InvalidClientSubmittedIntent")
      }
      fields["intentCid"] = Json::string(
        @run_host.client_submitted_intent_cid(admitted),
      )
    }
  }
  let writer = @encode.writer(maximum, 8192, 32) catch {
    _ => stop("request exceeds configured bounds")
  }
  let wire = try {
    @encode.emit_json(Json::object(fields), writer)
    @encode.finish(writer)
  } catch {
    _ => stop("request exceeds configured bounds")
  }
  @utf8.encode(wire)
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql",
    about="Check, explain, and run ActQL Programs",
    version=native_package_version(),
    subcommand_required=true,
    options=[
      @argparse.OptionArg(
        "mode",
        about="Host mode: local or remote",
        default_values=["remote"],
        global=true,
      ),
      @argparse.OptionArg(
        "config-root",
        about="Directory used to resolve configuration files",
        default_values=["."],
        global=true,
      ),
      @argparse.OptionArg(
        "config-file",
        about="Configuration file relative to --config-root",
        global=true,
      ),
      @argparse.OptionArg(
        "config",
        about="Path to the project configuration file",
        global=true,
      ),
      @argparse.OptionArg(
        "profile",
        about="Project configuration profile",
        global=true,
      ),
      @argparse.OptionArg(
        "state-dir",
        about="Local installation state directory",
        global=true,
      ),
      @argparse.OptionArg(
        "input-root",
        about="Directory used to resolve Program and parameter files",
        global=true,
      ),
      @argparse.OptionArg(
        "endpoint",
        about="Remote Host HTTPS endpoint",
        global=true,
      ),
      @argparse.OptionArg(
        "connection-root",
        about="Directory containing connection and reference files",
        global=true,
      ),
      @argparse.OptionArg(
        "connection-file",
        about="Host connection JSON file",
        global=true,
      ),
      @argparse.OptionArg(
        "token-root",
        about="Directory containing the authentication token file",
        global=true,
      ),
      @argparse.OptionArg(
        "token-file",
        about="Authentication token file",
        global=true,
      ),
      @argparse.OptionArg(
        "http-library",
        about="Path to the native HTTPS library",
        global=true,
      ),
      @argparse.OptionArg(
        "ca",
        about="TLS certificate authority file",
        global=true,
      ),
      @argparse.OptionArg(
        "cert",
        about="TLS client certificate file",
        global=true,
      ),
      @argparse.OptionArg(
        "key",
        about="TLS client private key file",
        global=true,
      ),
      @argparse.OptionArg(
        "max-request-bytes",
        about="Maximum encoded request size in bytes",
        default_values=["65536"],
        global=true,
      ),
      @argparse.OptionArg(
        "max-response-bytes",
        about="Maximum response size in bytes",
        default_values=["1048576"],
        global=true,
      ),
    ],
    subcommands=[
      @argparse.Command(
        "project-init-support",
        about="Report project binding implementation availability",
      ),
      @argparse.Command("schema", about="Print the Program JSON Schema"),
      @argparse.Command(
        "verify",
        about="Verify saved output against its receipt",
        subcommand_required=true,
        subcommands=[
          @argparse.Command(
            "output",
            about="Verify a saved output file against a delivery receipt",
            flags=[
              @argparse.FlagArg(
                "json",
                about="Print the command response and diagnostics as JSON",
              ),
            ],
            positionals=[
              @argparse.PositionArg(
                "receipt",
                about="Path to the output verification receipt",
              ),
              @argparse.PositionArg(
                "output",
                about="Path to the saved output file to verify",
              ),
            ],
          ),
        ],
      ),
      @argparse.Command(
        "check",
        about="Validate a Program without reading business data",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "program",
            about="Path to the Program to check, explain, or run",
            conflicts_with=["program-file"],
          ),
        ],
        options=[
          @argparse.OptionArg("program-file", about="Path to a Program file", conflicts_with=[
            "program",
          ]),
          @argparse.OptionArg(
            "format",
            about="Program syntax: json, yaml, aql, or sql",
          ),
          @argparse.OptionArg(
            "parameters-file",
            about="JSON file of parameter values (alias: --params)",
            conflicts_with=["params"],
          ),
          @argparse.OptionArg("params", about="JSON file of parameter values", conflicts_with=[
            "parameters-file",
          ]),
          @argparse.OptionArg(
            "parameter-declarations-file",
            about="JSON file of named parameter value contracts",
          ),
        ],
      ),
      @argparse.Command(
        "explain",
        about="Show a Program plan or a saved Run plan",
        flags=[
          @argparse.FlagArg(
            "verbose",
            about="Include full plan identities and port details",
          ),
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "program",
            about="Path to the Program to check, explain, or run",
            conflicts_with=["program-file", "run"],
          ),
        ],
        options=[
          @argparse.OptionArg("program-file", about="Path to a Program file", conflicts_with=[
            "program", "run",
          ]),
          @argparse.OptionArg("run", about="Saved Run ID to explain", conflicts_with=[
            "program", "program-file", "format", "parameters-file", "params", "parameter-declarations-file",
          ]),
          @argparse.OptionArg(
            "format",
            about="Program syntax: json, yaml, aql, or sql",
          ),
          @argparse.OptionArg(
            "parameters-file",
            about="JSON file of parameter values (alias: --params)",
            conflicts_with=["params"],
          ),
          @argparse.OptionArg("params", about="JSON file of parameter values", conflicts_with=[
            "parameters-file",
          ]),
          @argparse.OptionArg(
            "parameter-declarations-file",
            about="JSON file of named parameter value contracts",
          ),
        ],
      ),
      @argparse.Command(
        "adopt",
        about="Adopt a Local installation and its signing or journal state",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
          @argparse.FlagArg(
            "initialize-signing",
            about="Initialize Local signing state during adoption",
          ),
          @argparse.FlagArg(
            "migrate-journal",
            about="Migrate the Local journal during adoption",
          ),
        ],
      ),
      @argparse.Command(
        "connect",
        about="Inspect the configured Host connection",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
      ),
      @argparse.Command(
        "upgrade-policy",
        about="Apply a retention and store policy upgrade",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
        options=[
          @argparse.OptionArg(
            "operation-id",
            about="Policy upgrade operation ID",
            required=true,
          ),
          @argparse.OptionArg(
            "retention-file",
            about="Retention policy JSON file",
            default_values=["retention.json"],
          ),
          @argparse.OptionArg("store-file", about="Store policy JSON file", default_values=[
            "store.json",
          ]),
        ],
      ),
      @argparse.Command(
        "lookup-policy-upgrade",
        about="Look up a policy upgrade by operation ID",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
        options=[
          @argparse.OptionArg(
            "operation-id",
            about="Policy upgrade operation ID",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "new-submission",
        about="Create a submission reference for a request",
        options=[
          @argparse.OptionArg(
            "request-id",
            about="Request ID used to identify a submission",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "sql",
        about="Run a read-only SQL query and print Result rows",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print command diagnostics as JSON; --format controls Result rows",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "query",
            about="Query text",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
        options=[
          @argparse.OptionArg("params", about="JSON file of parameter values", conflicts_with=[
            "parameters-file",
          ]),
          @argparse.OptionArg(
            "parameters-file",
            about="JSON file of parameter values (alias: --params)",
            conflicts_with=["params"],
          ),
          @argparse.OptionArg(
            "parameter-declarations-file",
            about="JSON file of named parameter value contracts",
          ),
          @argparse.OptionArg(
            "format",
            about="Result row format: table, json, jsonl, or csv",
          ),
          @argparse.OptionArg(
            "output",
            about="Write Result rows to a new file instead of stdout",
          ),
        ],
      ),
      @argparse.Command(
        "aql",
        about="Run a Pipe query or submit a Program file",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print command diagnostics as JSON; --format controls Result rows",
          ),
        ],
        positionals=[
          @argparse.PositionArg("query", about="Query text", conflicts_with=[
            "program-file",
          ]),
        ],
        options=[
          @argparse.OptionArg("program-file", about="Path to a Program file", conflicts_with=[
            "query",
          ]),
          @argparse.OptionArg(
            "stop-before",
            about="Stop at a Checkpoint before the commit boundary",
          ),
          @argparse.OptionArg("params", about="JSON file of parameter values", conflicts_with=[
            "parameters-file",
          ]),
          @argparse.OptionArg(
            "parameters-file",
            about="JSON file of parameter values (alias: --params)",
            conflicts_with=["params"],
          ),
          @argparse.OptionArg(
            "parameter-declarations-file",
            about="JSON file of named parameter value contracts",
          ),
          @argparse.OptionArg(
            "format",
            about="Result row format: table, json, jsonl, or csv",
          ),
          @argparse.OptionArg(
            "output",
            about="Write Result rows to a new file instead of stdout",
          ),
          @argparse.OptionArg(
            "request-id",
            about="Request ID used to identify a submission",
          ),
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
          ),
          @argparse.OptionArg(
            "operation-attempt-id",
            about="Operation attempt ID",
          ),
        ],
      ),
      @argparse.Command(
        "run",
        about="Run a Program and report its state",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "program",
            about="Path to the Program to check, explain, or run",
            conflicts_with=["program-file"],
          ),
        ],
        options=[
          @argparse.OptionArg("program-file", about="Path to a Program file", conflicts_with=[
            "program",
          ]),
          @argparse.OptionArg(
            "stop-before",
            about="Stop at a Checkpoint before the commit boundary",
          ),
          @argparse.OptionArg(
            "parameters-file",
            about="JSON file of parameter values (alias: --params)",
            conflicts_with=["params"],
          ),
          @argparse.OptionArg("params", about="JSON file of parameter values", conflicts_with=[
            "parameters-file",
          ]),
          @argparse.OptionArg(
            "parameter-declarations-file",
            about="JSON file of named parameter value contracts",
          ),
          @argparse.OptionArg("format", about="Output format"),
          @argparse.OptionArg(
            "output",
            about="Write Result rows to a new file instead of stdout",
          ),
          @argparse.OptionArg(
            "deliver",
            about="Deliver a Result as result=format:file; repeat for multiple Results",
            action=Append,
          ),
          @argparse.OptionArg(
            "receipt",
            about="Write output verification receipts to a new file",
          ),
          @argparse.OptionArg(
            "request-id",
            about="Request ID used to identify a submission",
            requires=["submission-ref-file"],
          ),
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
            requires=["operation-attempt-id"],
          ),
          @argparse.OptionArg(
            "operation-attempt-id",
            about="Operation attempt ID",
            requires=["submission-ref-file"],
          ),
        ],
      ),
      @argparse.Command(
        "start",
        about="Start a submission with explicit operation references",
        options=[
          @argparse.OptionArg(
            "program-file",
            about="Path to a Program file",
            required=true,
          ),
          @argparse.OptionArg(
            "stop-before",
            about="Stop at a Checkpoint before the commit boundary",
          ),
          @argparse.OptionArg(
            "parameters-file",
            about="JSON file of parameter values (alias: --params)",
          ),
          @argparse.OptionArg(
            "request-id",
            about="Request ID used to identify a submission",
          ),
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "operation-attempt-id",
            about="Operation attempt ID",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "lookup-submission",
        about="Look up a submission by reference",
        options=[
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "approve",
        about="Approve a waiting Checkpoint",
        flags=[
          @argparse.FlagArg("wait", about="Wait for the Run after approving"),
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "checkpoint-id",
            about="Checkpoint ID to decide",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
        options=[
          @argparse.OptionArg(
            "signer",
            about="Signer ID for the Checkpoint decision",
          ),
        ],
      ),
      @argparse.Command(
        "reject",
        about="Reject a waiting Checkpoint",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "checkpoint-id",
            about="Checkpoint ID to decide",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
        options=[
          @argparse.OptionArg(
            "signer",
            about="Signer ID for the Checkpoint decision",
          ),
        ],
      ),
      @argparse.Command(
        "checkpoint-state",
        about="Read a Checkpoint state for a submission",
        options=[
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "lookup-preparation-grant",
        about="Look up a preparation grant",
        options=[
          @argparse.OptionArg(
            "grant-ref-file",
            about="Preparation grant reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "operation-cid",
            about="Preparation operation content ID",
            required=true,
          ),
          @argparse.OptionArg(
            "issuer-file",
            about="Preparation grant issuer JSON file",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "lookup-preparation-raw",
        about="Read preparation evidence using a grant",
        options=[
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "grant-ref-file",
            about="Preparation grant reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "operation-cid",
            about="Preparation operation content ID",
            required=true,
          ),
          @argparse.OptionArg(
            "use-id",
            about="Preparation grant use ID",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "lookup-request",
        about="Look up a submission by request ID",
        options=[
          @argparse.OptionArg(
            "request-id",
            about="Request ID used to identify a submission",
            required=true,
          ),
        ],
      ),
      @argparse.Command("attach", about="Attach to a Run by reference", options=[
        @argparse.OptionArg(
          "ref-file",
          about="Run or Checkpoint reference JSON file",
          required=true,
        ),
      ]),
      @argparse.Command(
        "status",
        about="Show a Run state or watch for changes",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
          @argparse.FlagArg("watch", about="Watch the Run for state changes"),
        ],
        positionals=[
          @argparse.PositionArg("run", about="Saved Run ID", conflicts_with=[
            "run-id", "ref-file", "submission-ref-file",
          ]),
        ],
        options=[
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
          ),
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
          ),
          @argparse.OptionArg(
            "run-id",
            about="Run ID (alternative to the positional Run)",
            conflicts_with=["run"],
          ),
          @argparse.OptionArg("until", about="State to wait for"),
          @argparse.OptionArg(
            "timeout",
            about="Watch timeout, for example 30s or 2m",
          ),
        ],
      ),
      @argparse.Command(
        "wait",
        about="Wait for a Run to reach the selected state",
        options=[
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
            required=true,
          ),
          @argparse.OptionArg("until", about="State to wait for"),
          @argparse.OptionArg("since", about="Run revision to wait from"),
        ],
      ),
      @argparse.Command(
        "cancel",
        about="Request cancellation at an expected Run revision",
        options=[
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
          ),
          @argparse.OptionArg(
            "cancel-id",
            about="Cancellation request ID",
            required=true,
          ),
          @argparse.OptionArg(
            "expected-revision",
            about="Expected current Run revision",
            required=true,
          ),
          @argparse.OptionArg(
            "operation-attempt-id",
            about="Operation attempt ID",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "lookup-cancellation",
        about="Look up a cancellation request",
        options=[
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
          ),
          @argparse.OptionArg(
            "cancel-id",
            about="Cancellation request ID",
            required=true,
          ),
          @argparse.OptionArg(
            "expected-revision",
            about="Expected current Run revision",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "reconcile",
        about="Reconcile a Run with pending work",
        options=[
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "result",
        about="Read saved Result rows from a Run",
        flags=[
          @argparse.FlagArg(
            "json",
            about="Print the command response and diagnostics as JSON",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "run",
            about="Saved Run ID",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
        options=[
          @argparse.OptionArg(
            "result",
            about="Name of the saved Result to read",
          ),
          @argparse.OptionArg(
            "format",
            about="Result row format: table, json, jsonl, or csv",
          ),
          @argparse.OptionArg(
            "output",
            about="Write Result rows to a new file instead of stdout",
          ),
          @argparse.OptionArg(
            "deliver",
            about="Deliver a Result as result=format:file; repeat for multiple Results",
            action=Append,
          ),
          @argparse.OptionArg(
            "receipt",
            about="Write output verification receipts to a new file",
          ),
        ],
      ),
      @argparse.Command(
        "read",
        about="Read a named Result with a delivery attempt",
        options=[
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
          ),
          @argparse.OptionArg("purpose", about="Result delivery purpose"),
          @argparse.OptionArg("format", about="Output format"),
          @argparse.OptionArg(
            "max-output-bytes",
            about="Maximum delivered output size in bytes",
          ),
          @argparse.OptionArg(
            "result-name",
            about="Name of the saved Result",
            required=true,
          ),
          @argparse.OptionArg(
            "attempt-id",
            about="Result delivery attempt ID",
            required=true,
          ),
        ],
      ),
      @argparse.Command(
        "delivery-attempt",
        about="Look up a Result delivery attempt",
        options=[
          @argparse.OptionArg(
            "ref-file",
            about="Run or Checkpoint reference JSON file",
            required=true,
          ),
          @argparse.OptionArg(
            "submission-ref-file",
            about="Submission reference JSON file",
          ),
          @argparse.OptionArg("purpose", about="Result delivery purpose"),
          @argparse.OptionArg(
            "result-name",
            about="Name of the saved Result",
            required=true,
          ),
          @argparse.OptionArg(
            "attempt-id",
            about="Result delivery attempt ID",
            required=true,
          ),
        ],
      ),
    ],
  )
}

///|
fn execute(matches : @argparse.Matches) -> String raise ClientStop {
  normalize_native_query_arguments(matches)
  normalize_native_status_arguments(matches)
  normalize_native_result_arguments(matches)
  match required(matches, "mode") {
    "local" => return execute_native_local(matches)
    "remote" =>
      if matches.subcommand is Some(("check", _)) ||
        matches.subcommand is Some(("explain", _)) ||
        matches.subcommand is Some(("run", _)) ||
        matches.subcommand is Some(("result", _)) ||
        matches.subcommand is Some(("adopt", _)) ||
        matches.subcommand is Some(("checkpoint-state", _)) ||
        matches.subcommand is Some(("lookup-preparation-grant", _)) ||
        matches.subcommand is Some(("lookup-preparation-raw", _)) {
        stop("operation requires an explicit Local configuration")
      }
    _ => stop("unsupported Client mode")
  }
  if optional(matches, "state-dir") is Some(_) {
    stop("Local installation directory is unavailable in Remote mode")
  }
  if matches.subcommand is Some((operation, child)) &&
    local_quick_query_requested(operation, child) {
    stop("QuickQueryRequiresLocalHost")
  }
  if optional(matches, "input-root") is Some(_) {
    stop("Local document root is unavailable in Remote mode")
  }
  if matches.subcommand is Some(("status", child)) &&
    (
      child.flags.get("watch").unwrap_or(false) ||
      optional(child, "until") is Some(_) ||
      optional(child, "timeout") is Some(_)
    ) {
    stop("Local status watch options are unavailable in Remote mode")
  }
  if matches.subcommand is Some(("status", child)) &&
    (
      optional(child, "run-id") is Some(_) ||
      optional(child, "submission-ref-file") is Some(_)
    ) {
    stop("Original Local status selection is unavailable in Remote mode")
  }
  if matches.subcommand is Some((operation, child)) &&
    (
      operation == "lookup-cancellation" ||
      operation == "cancel" ||
      operation == "delivery-attempt" ||
      operation == "read"
    ) &&
    optional(child, "submission-ref-file") is Some(_) {
    stop("Original Local submission binding is unavailable in Remote mode")
  }
  if matches.subcommand is Some(("delivery-attempt", child)) &&
    optional(child, "purpose") is Some(_) {
    stop("Explicit Local delivery purpose is unavailable in Remote mode")
  }
  if matches.subcommand is Some(("read", child)) {
    for name in ["purpose", "format", "max-output-bytes"] {
      if optional(child, name) is Some(_) {
        stop("Explicit Local read options are unavailable in Remote mode")
      }
    }
  }
  let endpoint = endpoint_url(required(matches, "endpoint"))
  let request_max = positive_int(
    required(matches, "max-request-bytes"),
    "max-request-bytes",
  )
  let response_max = positive_int(
    required(matches, "max-response-bytes"),
    "max-response-bytes",
  )
  if request_max > 1048576 || response_max > 16777216 {
    stop("Client transport limit exceeds supported maximum")
  }
  let root = required(matches, "connection-root")
  let connection = json_file(root, required(matches, "connection-file"), 8192L)
  if !wire_connection_shape(connection) {
    stop("invalid Client connection")
  }
  let token = match
    @files.read_bounded_text_file(
      required(matches, "token-root"),
      required(matches, "token-file"),
      8192L,
      trim_newline=true,
    ) {
    Ok(value) if !value.is_empty() &&
      !value.contains("\n") &&
      !value.contains("\r") &&
      !value.contains(" ") => value
    _ => stop("invalid Client credential file")
  }
  guard matches.subcommand is Some((operation, child)) else {
    stop("missing Client operation")
  }
  let body = request_body(operation, child, root, connection, request_max)
  let connect_body = request_body(
    "connect", child, root, connection, request_max,
  )
  let library = match @http.load_library(required(matches, "http-library")) {
    Ok(value) => value
    Err(_) => stop("native HTTPS library unavailable")
  }
  let client = match
    library.create_client(
      required(matches, "ca"),
      required(matches, "cert"),
      required(matches, "key"),
      response_max.to_int64(),
      5000,
      30000,
    ) {
    Ok(value) => value
    Err(_) => stop("native HTTPS client unavailable")
  }
  let route = if operation == "aql" || operation == "start" {
    "submit-intent"
  } else {
    operation
  }
  let headers : Array[@http.NativeHttpHeader] = [
    { name: "authorization", value: "Bearer " + token, },
    { name: "content-type", value: "application/json", },
  ]
  let negotiation = client.request(
    @http.Post,
    endpoint + "actql/client/0.1/connect",
    headers,
    connect_body,
  )
  let confirmed = match negotiation {
    Ok(value) if value.status >= 200 && value.status < 300 => {
      let text = @utf8.decode(value.body) catch {
        _ => stop("invalid Client Host profile")
      }
      ignore(confirmed_profile(text, connection))
      if operation == "connect" {
        ignore(client.close())
        return text
      }
      text
    }
    Ok(value) => stop("ClientHostHTTP" + value.status.to_string())
    Err(_) => stop("ClientTransportUnknown")
  }
  if operation == "new-submission" {
    let profile = @json.parse(confirmed) catch {
      _ => stop("InvalidHostProfile")
    }
    guard profile is Object(fields) &&
      fields.get("submissionEpoch") is Some(epoch) else {
      stop("SubmissionEpochUnavailable")
    }
    let reference = Json::object(
      Map([
        ("epoch", epoch),
        ("nonce", Json::string(required(child, "request-id"))),
      ]),
    )
    if !valid_submission_ref(reference) {
      stop("InvalidSubmissionRef")
    }
    ignore(client.close())
    return encode_request_json(reference, response_max)
  }
  let response = client.request(
    @http.Post,
    endpoint + "actql/client/0.1/" + route,
    headers,
    body,
  )
  ignore(client.close())
  let result = match response {
    Ok(value) => value
    Err(_) if route == "submit-intent" =>
      stop(
        "SubmissionUnknown submission-ref-file=" +
        required(child, "submission-ref-file"),
      )
    Err(_) if route == "read" =>
      stop("ResultReadUnknown attempt-id=" + required(child, "attempt-id"))
    Err(_) if route == "cancel" => stop(cancellation_unknown(body))
    Err(_) => stop("ClientTransportUnknown")
  }
  if result.status < 200 || result.status >= 300 {
    if route == "submit-intent" {
      stop(
        "SubmissionUnknown submission-ref-file=" +
        required(child, "submission-ref-file"),
      )
    }
    if route == "read" {
      stop("ResultReadUnknown attempt-id=" + required(child, "attempt-id"))
    }
    if route == "cancel" && result.status >= 500 {
      stop(cancellation_unknown(body))
    }
    stop("ClientHostHTTP" + result.status.to_string())
  }
  let text = @utf8.decode(result.body) catch {
    _ =>
      if route == "submit-intent" {
        stop(
          "SubmissionUnknown submission-ref-file=" +
          required(child, "submission-ref-file"),
        )
      } else if route == "read" {
        stop("ResultReadUnknown attempt-id=" + required(child, "attempt-id"))
      } else if route == "cancel" {
        stop(cancellation_unknown(body))
      } else {
        stop("invalid UTF-8 Host response")
      }
  }
  if route == "submit-intent" || route == "lookup-submission" {
    if @source.parse_json_bytes_preserving(result.body, {
        max_input_bytes: response_max,
        max_nodes: 8192,
        max_depth: 32,
      })
      is Err(_) {
      stop(
        (if route == "submit-intent" {
          "SubmissionUnknown"
        } else {
          "InvalidHostSubmissionLookup"
        }) +
        " submission-ref-file=" +
        required(child, "submission-ref-file"),
      )
    }
    let outcome = @json.parse(text) catch {
      _ =>
        stop(
          (if route == "submit-intent" {
            "SubmissionUnknown"
          } else {
            "InvalidHostSubmissionLookup"
          }) +
          " submission-ref-file=" +
          required(child, "submission-ref-file"),
        )
    }
    if !valid_submission_reply(
        outcome,
        body,
        connection,
        route == "lookup-submission",
      ) {
      stop(
        (if route == "submit-intent" {
          "SubmissionUnknown"
        } else {
          "InvalidHostSubmissionLookup"
        }) +
        " submission-ref-file=" +
        required(child, "submission-ref-file"),
      )
    }
    if route == "submit-intent" && outcome is Object(attempt) {
      guard attempt.get("outcome") is Some(Object(fields)) else {
        // A typed refusal or conflict is this invocation's result, not a
        // durable receipt or an inferred permission to resubmit.
        return text
      }
      match json_text(fields, "kind") {
        Some("ready") =>
          return encode_request_json(fields["admission"], response_max)
        Some("held") => return encode_request_json(fields["held"], response_max)
        Some("not_accepted") | Some("preparation_failed") => {
          guard fields.get("problem") is Some(Object(problem)) &&
            json_text(problem, "code") is Some(code) else {
            stop("InvalidHostSubmissionOutcome")
          }
          stop(code)
        }
        _ =>
          stop(
            "SubmissionPreparing submission-ref-file=" +
            required(child, "submission-ref-file"),
          )
      }
    }
    return text
  }
  if route == "attach" && !admitted_run(text, connection) {
    stop("InvalidHostAdmission")
  }
  if route == "attach" && !attached_reference_matches(body, text) {
    stop("ForeignHostAdmission")
  }
  if (route == "cancel" || route == "lookup-cancellation") &&
    @source.parse_json(text, {
      max_input_bytes: response_max,
      max_nodes: 128,
      max_depth: 8,
    })
    is Err(_) {
    stop("InvalidHostCancellation " + cancellation_unknown(body))
  }
  if route == "read" {
    if !text.has_suffix("\u{1e}") {
      stop("IncompleteResultStream attempt-id=" + required(child, "attempt-id"))
    }
    text[:text.length() - 1].to_owned()
  } else {
    let value = @json.parse(text) catch {
      _ =>
        if route == "cancel" || route == "lookup-cancellation" {
          stop("InvalidHostCancellation " + cancellation_unknown(body))
        } else {
          stop("invalid JSON Host response")
        }
    }
    if (route == "cancel" || route == "lookup-cancellation") &&
      !valid_cancellation_reply(value, body, route == "lookup-cancellation") {
      stop("InvalidHostCancellation " + cancellation_unknown(body))
    }
    if route == "lookup-request" &&
      !wire_request_lookup(value, required(child, "request-id")) {
      stop("InvalidHostRequestLookup")
    }
    if route == "delivery-attempt" &&
      !valid_attempt_lookup(value, body, response_max) {
      stop("InvalidHostAttemptLookup")
    }
    text
  }
}

///|
#borrow(bytes)
extern "C" fn report_failure_ffi(bytes : Bytes, length : Int) -> Unit = "actql_native_client_report_failure"

///|
extern "C" fn exit_failure_ffi() -> Unit = "actql_native_client_exit_failure"

///|
extern "C" fn exit_argument_failure_ffi() -> Unit = "actql_native_client_exit_argument_failure"

///|
// Keep the selected reply and UTF8 alias inside this invocation action. Actual
// domain retirement after this return still checks all original escaped users.
fn execute_and_write_native_reply(
  matches : @argparse.Matches,
  pending_reply : Ref[String?],
) -> Unit raise ClientStop {
  native_timing_begin(1)
  defer native_timing_end(1)
  local_command_diagnostic_reset()
  command_diagnostic_json.val = local_command_json_selected(matches)
  command_check_invalid_exit.val = false
  command_result_delivery_failed.val = false
  // This fixed query reports implementation only, before any project/runtime
  // selection, file acquisition, Account, Store or signing preparation.
  if matches.subcommand is Some(("project-init-support", _)) {
    pending_reply.val = Some(local_project_init_support())
    return
  }
  // Language discovery returns the registered Program schema, without project
  // selection, installation IO, a Host or a Run. Main owns stdout/flush errors.
  if matches.subcommand is Some(("schema", _)) {
    pending_reply.val = Some(generated_program_schema())
    return
  }
  // Integrity verification reads explicit files and does not acquire a Host,
  // resolve a project, create an installation or grant payload access.
  if matches.subcommand is Some(("verify", child)) {
    pending_reply.val = Some(local_verify_output_command(child))
    return
  }
  // The same carrier is registered before the first project/runtime/Store IO.
  // Help/version and parse errors have already terminated without acquisition.
  prepare_native_command_invocation(matches)
  let selected = execute_native_project_selection(matches)
  let value = match selected {
    Ok(value) => value
    Err(original) => {
      ignore(original.issue())
      if original.retry_cleanup() is Err(_) {
        stop("ProjectConfigurationReadCleanupPending")
      } else {
        stop("ProjectConfigurationReadUnavailable")
      }
    }
  }
  if local_payload_already_streamed(matches) {
    return
  }
  if command_preparation_invocation.val is Some(original) {
    // Static metadata is copied only after leaving its original Read. Keep the
    // same physical carrier and all aliases until main confirms every cleanup;
    // a partial close must never publish an adoption/check success beforehand.
    command_preparation_result(original.leave())
    if original.journal_read_open ||
      pending_reply.val is Some(_) ||
      value.length() > 1048576 {
      stop("LocalCommandReplyUnavailable")
    }
    pending_reply.val = Some(command_control_copy_text(value))
    return
  }
  let reply = if matches.subcommand is Some(("read", _)) {
    value
  } else {
    value + "\n"
  }
  let bytes = @utf8.encode(reply)
  if !write_stdout_ffi(bytes, bytes.length()) {
    stop("stdout write failed")
  }
}

///|
fn main {
  native_timing_begin(0)
  local_command_diagnostic_reset()
  // Bound and retain ordinary process input before constructing the parser.
  // No pre-main provenance or private libc state is required.
  // These selected Darwin input ceilings include argv0 and terminal bytes;
  // they are not the initial-control or physical-capacity admission itself.
  // Help/version and argument failure acquire no Host/Root/Read resources.
  let selected_arguments = match
    command_preargument_bound(1048576, 1048576, 1048576, 8192) {
    Ok(selected) => selected
    Err(_) => {
      fail_command("LocalCommandArgumentsUnavailable")
      abort("native Client original argument failure")
    }
  }
  command_capture_native_entry()
  let control = parse_native_initial_command(selected_arguments) catch {
    NativeCommandArgumentStop(message) => {
      let bytes = @utf8.encode(
        local_command_diagnostic_text(
          "ACTQL_E_ARGUMENT_INVALID",
          message,
          command_diagnostic_json.val,
        ),
      )
      report_failure_ffi(bytes, bytes.length())
      exit_argument_failure_ffi()
      abort("native Client argument failure")
    }
    error => {
      fail_command(error.to_string())
      abort("native Client argument failure")
    }
  }
  native_timing_end(0)
  // At most one bounded UTF-16 metadata copy escapes into initial control.
  // It overlaps the retained Read original until actual child cleanup ACKs.
  let pending_reply : Ref[String?] = Ref(None)
  let failed = try {
    control.consume_matches(matches => {
      execute_and_write_native_reply(matches, pending_reply)
    })
    false
  } catch {
    ClientStop(message) => {
      let bytes = @utf8.encode(
        local_command_failure_text(message, command_diagnostic_json.val),
      )
      report_failure_ffi(bytes, bytes.length())
      true
    }
  }
  // stdout/flush, Library, component, context/domain/map, Host and FD retirement
  // are separate facts. An output or process exit never substitutes for ACK.
  native_timing_begin(5)
  if local_finish_output_verification() is Err(_) {
    fail_cleanup_command("OutputVerificationCleanupPending")
  }
  if local_finish_result_receipt() is Err(_) {
    fail_cleanup_command("ResultReceiptCleanupPending")
  }
  let command_cleanup = local_finish_command_preparation()
  let command_closed = command_cleanup is Ok(_)
  let crypto_closed = if command_closed {
    local_finish_initial_crypto()
  } else {
    false
  }
  native_timing_end(5)
  if command_cleanup is Err(issue) {
    let stage = match command_preparation_invocation.val {
      Some(original) => original.cleanup_stage
      None => "original-retained"
    }
    let observed = match (issue, command_preparation_invocation.val) {
      (CommandPair(@initial_arena.Read(_)), Some(original)) =>
        original.cleanup_read_observation()
      _ => ""
    }
    fail_cleanup_command(
      local_command_recovery_failure(
        "LocalCommandPreparationCleanupPending: " +
        stage +
        ": " +
        command_preparation_cleanup_kind(issue) +
        observed +
        " cause=" +
        command_preparation_cleanup_cause(issue),
      ),
    )
  }
  if !crypto_closed {
    fail_cleanup_command("InitialCryptoCleanupPending")
  }
  if failed {
    exit_failure_ffi()
  }
  if pending_reply.val is Some(body) {
    let bytes = @utf8.encode(body + "\n")
    if !write_stdout_ffi(bytes, bytes.length()) {
      fail_command("stdout write failed")
    }
    pending_reply.val = None
  }
  command_initial_control_keep_alive(control)
  // The invalid report has already been written/flushed, and all original
  // child cleanup has acknowledged. Run-state outcomes never set this flag.
  if command_check_invalid_exit.val || command_result_delivery_failed.val {
    exit_failure_ffi()
  }
}

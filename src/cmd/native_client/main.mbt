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
  let bytes = @utf8.encode("actql-native-client: " + message)
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
fn text_file(
  root : String,
  name : String,
  maximum : Int64,
) -> String raise ClientStop {
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
  let text = text_file(root, name, maximum)
  match
    @source.parse_json(text, {
      max_input_bytes: maximum.to_int(),
      max_nodes: 8192,
      max_depth: 32,
    }) {
    Ok(_) => @json.parse(text) catch { _ => stop("invalid JSON file " + name) }
    Err(_) => stop("invalid JSON file " + name)
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
fn valid_cid(value : String) -> Bool {
  if !value.has_prefix("sha256:") || value.length() != 71 {
    return false
  }
  let bytes = @utf8.encode(value)
  for index = 7; index < bytes.length(); index = index + 1 {
    let byte = bytes[index].to_int()
    if !((byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)) {
      return false
    }
  }
  true
}

///|
fn positive_limit(fields : Map[String, Json], name : String) -> Bool {
  match fields.get(name) {
    Some(Number(value, ..)) =>
      value >= 1.0 && value <= 9007199254740991.0 && value == value.floor()
    _ => false
  }
}

///|
fn confirmed_profile(wire : String, connection : Json) -> Json raise ClientStop {
  let profile = @json.parse(wire) catch {
    _ => stop("invalid Client Host profile")
  }
  guard profile is Object(fields) else { stop("invalid Client Host profile") }
  guard connection is Object(selected) else {
    stop("invalid Client connection")
  }
  guard json_text(selected, "mode") is Some(mode) &&
    json_text(selected, "owner") is Some(owner) &&
    (
      (mode == "remote" && owner == "remote") ||
      (mode == "local" && owner == "local") ||
      (mode == "hybrid" && (owner == "local" || owner == "cloud"))
    ) else {
    stop("invalid Client connection")
  }
  guard json_text(fields, "version") is Some("actql-client-host/0.1") &&
    json_text(fields, "mode") is Some(profile_mode) &&
    profile_mode == mode &&
    json_text(fields, "owner") is Some(profile_owner) &&
    profile_owner == owner &&
    json_text(fields, "scopeRef") is Some(scope) &&
    !scope.is_empty() &&
    fields.get("capabilities") is Some(Array(capabilities)) &&
    fields.get("limits") is Some(Object(limits)) else {
    stop("invalid Client Host profile")
  }
  for capability in capabilities {
    guard capability is String(name) && !name.is_empty() else {
      stop("invalid Client Host profile")
    }
  }
  if limits.length() != 7 ||
    !positive_limit(limits, "maxReadWireBytes") ||
    !positive_limit(limits, "maxRowWireBytes") ||
    !positive_limit(limits, "maxRowRetainedValueBytes") ||
    !positive_limit(limits, "maxRetainedValueBytes") ||
    !positive_limit(limits, "maxRows") ||
    !positive_limit(limits, "maxBatchRows") ||
    !positive_limit(limits, "maxBatchRetainedValueBytes") {
    stop("invalid Client Host profile")
  }
  guard json_text(fields, "durability") is Some(durability) &&
    (durability == "volatile" || durability == "durable") else {
    stop("invalid Client Host profile")
  }
  if json_text(selected, "durability") is Some("durable") &&
    durability != "durable" {
    stop("requested durable profile is unavailable")
  }
  profile
}

///|
fn admitted_run(wire : String, requested_durable : Bool) -> Bool {
  let value = @json.parse(wire) catch { _ => return false }
  guard value is Object(fields) else { return false }
  guard fields.get("ref") is Some(Object(reference)) else { return false }
  guard json_text(reference, "namespaceId") is Some(namespace_id) &&
    !namespace_id.is_empty() &&
    json_text(reference, "authorityScopeCid") is Some(scope) &&
    valid_cid(scope) &&
    json_text(reference, "runDefinitionCid") is Some(definition) &&
    valid_cid(definition) &&
    fields.get("revision") is Some(Number(revision, ..)) &&
    revision >= 0.0 &&
    revision <= 9007199254740991.0 &&
    revision == revision.floor() else {
    return false
  }
  guard json_text(fields, "durability") is Some(durability) &&
    (durability == "volatile" || durability == "durable") else {
    return false
  }
  !requested_durable || durability == "durable"
}

///|
// The closed submit_preparation_error contract is tested against its
// registered schema. Unknown HTTP errors do not prove non-admission.
fn preparation_refusal(bytes : Bytes) -> String? {
  let text = @utf8.decode(bytes) catch { _ => return None }
  if @source.parse_json(text, {
      max_input_bytes: 4096,
      max_nodes: 16,
      max_depth: 4,
    })
    is Err(_) {
    return None
  }
  let value = @json.parse(text) catch { _ => return None }
  guard value is Object(fields) && fields.length() == 1 else { return None }
  match json_text(fields, "code") {
    Some(code) =>
      match code {
        "ClientProgramInvalidInput"
        | "ClientParametersInvalid"
        | "ClientParametersTooLarge"
        | "ClientProgramUnsupported"
        | "ClientProgramNeedsInputs"
        | "ClientProgramRejected" => Some(code)
        _ => None
      }
    None => None
  }
}

///|
fn valid_reference(value : Json) -> Bool {
  guard value is Object(fields) && fields.length() == 3 else { return false }
  guard json_text(fields, "namespaceId") is Some(namespace_id) &&
    !namespace_id.is_empty() &&
    json_text(fields, "authorityScopeCid") is Some(scope) &&
    valid_cid(scope) &&
    json_text(fields, "runDefinitionCid") is Some(definition) &&
    valid_cid(definition) else {
    return false
  }
  true
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
fn nonempty_member(fields : Map[String, Json], name : String) -> Bool {
  match json_text(fields, name) {
    Some(value) => !value.is_empty()
    None => false
  }
}

///|
fn bounded_control_member(fields : Map[String, Json], name : String) -> Bool {
  guard json_text(fields, name) is Some(text) &&
    !text.is_empty() &&
    text.length() <= 256 else {
    return false
  }
  for unit in text {
    if unit.to_int() < 32 || unit.to_int() == 127 {
      return false
    }
  }
  true
}

///|
// A held reply is a request control result with no RunRef. Inspection never
// approves it, starts it, or changes the Host's durable resume decision.
fn valid_held(value : Json, request_id : String) -> Bool {
  guard value is Object(fields) else { return false }
  let keys = [
    "kind", "requestId", "prepareAttemptId", "state", "durability", "lookupExpiresAt",
    "checkpoint", "endReason", "terminalErrorCode",
  ]
  for key, _ in fields {
    if !keys.contains(key) {
      return false
    }
  }
  if json_text(fields, "kind") != Some("held") ||
    json_text(fields, "requestId") != Some(request_id) ||
    json_text(fields, "durability") != Some("durable") ||
    !bounded_control_member(fields, "requestId") ||
    !bounded_control_member(fields, "prepareAttemptId") ||
    !bounded_control_member(fields, "lookupExpiresAt") {
    return false
  }
  for key in ["endReason", "terminalErrorCode"] {
    if fields.contains(key) && !bounded_control_member(fields, key) {
      return false
    }
  }
  if fields.get("checkpoint") is Some(checkpoint) {
    guard checkpoint is Object(checkpoint) &&
      checkpoint.length() == 4 &&
      bounded_control_member(checkpoint, "checkpointId") &&
      bounded_control_member(checkpoint, "expiresAt") &&
      json_text(checkpoint, "checkpointCid") is Some(cid) &&
      valid_cid(cid) &&
      json_text(checkpoint, "kind") is Some(kind) &&
      ["run_scope", "read_access", "data_egress", "cost_scope", "effect_set"].contains(
        kind,
      ) else {
      return false
    }
  }
  match json_text(fields, "state") {
    Some("waiting_checkpoint") =>
      fields.contains("checkpoint") &&
      !fields.contains("endReason") &&
      !fields.contains("terminalErrorCode")
    Some("resuming") =>
      !fields.contains("endReason") && !fields.contains("terminalErrorCode")
    Some("ended") => fields.contains("endReason")
    _ => false
  }
}

///|
fn held_reply(text : String, request_id : String) -> Bool {
  if @source.parse_json(text, {
      max_input_bytes: 8192,
      max_nodes: 64,
      max_depth: 4,
    })
    is Err(_) {
    return false
  }
  let value = @json.parse(text) catch { _ => return false }
  valid_held(value, request_id)
}

///|
fn valid_reference_member(fields : Map[String, Json]) -> Bool {
  match fields.get("ref") {
    Some(reference) => valid_reference(reference)
    None => false
  }
}

///|
fn valid_request_lookup(value : Json, expected_request_id : String) -> Bool {
  guard value is Object(fields) else { return false }
  match json_text(fields, "kind") {
    Some("held") => valid_held(value, expected_request_id)
    Some("not_found") => fields.length() == 1
    Some("unknown") => fields.length() == 2 && nonempty_member(fields, "reason")
    Some("found") =>
      fields.length() == 5 &&
      json_text(fields, "requestId") == Some(expected_request_id) &&
      valid_reference_member(fields) &&
      (
        json_text(fields, "durability") == Some("volatile") ||
        json_text(fields, "durability") == Some("durable")
      ) &&
      nonempty_member(fields, "lookupExpiresAt")
    _ => false
  }
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
fn request_body(
  operation : String,
  child : @argparse.Matches,
  root : String,
  connection : Json,
  maximum : Int,
) -> Bytes raise ClientStop {
  let fields : Map[String, Json] = Map([("connection", connection)])
  match operation {
    "connect" => ()
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
      fields["requestId"] = Json::string(required(child, "request-id"))
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
      fields["requestId"] = Json::string(required(child, "request-id"))
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
    "lookup-request" =>
      fields["requestId"] = Json::string(required(child, "request-id"))
    "attach" | "status" | "cancel" | "reconcile" =>
      fields["ref"] = json_file(root, required(child, "ref-file"), 8192L)
    "wait" => {
      fields["ref"] = json_file(root, required(child, "ref-file"), 8192L)
      fields["until"] = match optional(child, "until") {
        Some(value) => Json::string(value)
        None => Json::null()
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
    "actql-native-client",
    about="Bounded native Client Host transport",
    version="0.1",
    subcommand_required=true,
    options=[
      @argparse.OptionArg("endpoint", required=true, global=true),
      @argparse.OptionArg("connection-root", required=true, global=true),
      @argparse.OptionArg("connection-file", required=true, global=true),
      @argparse.OptionArg("token-root", required=true, global=true),
      @argparse.OptionArg("token-file", required=true, global=true),
      @argparse.OptionArg("http-library", required=true, global=true),
      @argparse.OptionArg("ca", required=true, global=true),
      @argparse.OptionArg("cert", required=true, global=true),
      @argparse.OptionArg("key", required=true, global=true),
      @argparse.OptionArg(
        "max-request-bytes",
        default_values=["65536"],
        global=true,
      ),
      @argparse.OptionArg(
        "max-response-bytes",
        default_values=["1048576"],
        global=true,
      ),
    ],
    subcommands=[
      @argparse.Command("connect"),
      @argparse.Command("aql", options=[
        @argparse.OptionArg("program-file", required=true),
        @argparse.OptionArg("parameters-file"),
        @argparse.OptionArg("parameter-declarations-file"),
        @argparse.OptionArg("format", required=true),
        @argparse.OptionArg("request-id", required=true),
      ]),
      @argparse.Command("start", options=[
        @argparse.OptionArg("program-file", required=true),
        @argparse.OptionArg("parameters-file"),
        @argparse.OptionArg("request-id", required=true),
      ]),
      @argparse.Command("lookup-request", options=[
        @argparse.OptionArg("request-id", required=true),
      ]),
      @argparse.Command("attach", options=[
        @argparse.OptionArg("ref-file", required=true),
      ]),
      @argparse.Command("status", options=[
        @argparse.OptionArg("ref-file", required=true),
      ]),
      @argparse.Command("wait", options=[
        @argparse.OptionArg("ref-file", required=true),
        @argparse.OptionArg("until"),
      ]),
      @argparse.Command("cancel", options=[
        @argparse.OptionArg("ref-file", required=true),
      ]),
      @argparse.Command("reconcile", options=[
        @argparse.OptionArg("ref-file", required=true),
      ]),
      @argparse.Command("read", options=[
        @argparse.OptionArg("ref-file", required=true),
        @argparse.OptionArg("result-name", required=true),
        @argparse.OptionArg("attempt-id", required=true),
      ]),
      @argparse.Command("delivery-attempt", options=[
        @argparse.OptionArg("ref-file", required=true),
        @argparse.OptionArg("result-name", required=true),
        @argparse.OptionArg("attempt-id", required=true),
      ]),
    ],
  )
}

///|
fn execute(matches : @argparse.Matches) -> String raise ClientStop {
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
    "submit"
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
  ignore(confirmed)
  let response = client.request(
    @http.Post,
    endpoint + "actql/client/0.1/" + route,
    headers,
    body,
  )
  ignore(client.close())
  let result = match response {
    Ok(value) => value
    Err(_) if route == "submit" =>
      stop("SubmissionUnknown request-id=" + required(child, "request-id"))
    Err(_) if route == "read" =>
      stop("ResultReadUnknown attempt-id=" + required(child, "attempt-id"))
    Err(_) => stop("ClientTransportUnknown")
  }
  if result.status < 200 || result.status >= 300 {
    if route == "submit" {
      if result.status >= 400 && result.status < 500 {
        if preparation_refusal(result.body) is Some(code) {
          stop(code)
        }
      }
      stop("SubmissionUnknown request-id=" + required(child, "request-id"))
    }
    if route == "read" {
      stop("ResultReadUnknown attempt-id=" + required(child, "attempt-id"))
    }
    stop("ClientHostHTTP" + result.status.to_string())
  }
  let text = @utf8.decode(result.body) catch {
    _ =>
      if route == "submit" {
        stop("SubmissionUnknown request-id=" + required(child, "request-id"))
      } else if route == "read" {
        stop("ResultReadUnknown attempt-id=" + required(child, "attempt-id"))
      } else {
        stop("invalid UTF-8 Host response")
      }
  }
  if route == "submit" &&
    !held_reply(text, required(child, "request-id")) &&
    !admitted_run(
      text,
      json_text(
        match connection {
          Object(fields) => fields
          _ => Map([])
        },
        "durability",
      ) ==
      Some("durable"),
    ) {
    stop("SubmissionUnknown request-id=" + required(child, "request-id"))
  }
  if route == "attach" && !admitted_run(text, false) {
    stop("InvalidHostAdmission")
  }
  if route == "attach" && !attached_reference_matches(body, text) {
    stop("ForeignHostAdmission")
  }
  if route == "read" {
    if !text.has_suffix("\u{1e}") {
      stop("IncompleteResultStream attempt-id=" + required(child, "attempt-id"))
    }
    text[:text.length() - 1].to_owned()
  } else {
    let value = @json.parse(text) catch {
      _ => stop("invalid JSON Host response")
    }
    if route == "lookup-request" &&
      !valid_request_lookup(value, required(child, "request-id")) {
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
fn main {
  let matches = command().parse() catch {
    error => {
      fail_command(error.to_string())
      abort("native Client argument failure")
    }
  }
  let value = execute(matches) catch {
    ClientStop(message) => {
      fail_command(message)
      abort("native Client operation failure")
    }
  }
  if matches.subcommand is Some(("read", _)) {
    let bytes = @utf8.encode(value)
    if !write_stdout_ffi(bytes, bytes.length()) {
      fail_command("stdout write failed")
    }
  } else {
    println(value)
  }
}

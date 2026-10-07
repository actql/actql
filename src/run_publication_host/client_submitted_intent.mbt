///|
/// Original submitted content before checking. No execution identity, source
/// authorization or verified conclusion is manufactured by this admission.
struct ClientSubmittedIntent {
  wire : String
  cid : String
} derive(Eq, Debug)

///|
pub(all) enum ClientSubmittedIntentIssue {
  InvalidLimits
  Limit
  InvalidEnvelope
  Encoding
} derive(Eq, Debug)

///|
pub fn client_submitted_intent_wire(value : ClientSubmittedIntent) -> String {
  value.wire
}

///|
/// Durable terminal decisions are immutable. Preparing and a supported held
/// intent can acquire a Run; neither can become a pre-acceptance rejection.
pub fn client_submitted_intent_transition(
  before : String,
  after : String,
) -> Bool {
  match before {
    "preparing" =>
      ["preparing", "held", "ready", "preparation_failed"].contains(after)
    "held" => ["held", "ready", "preparation_failed"].contains(after)
    "ready" | "not_accepted" | "preparation_failed" => before == after
    _ => false
  }
}

///|
pub fn client_submitted_intent_cid(value : ClientSubmittedIntent) -> String {
  value.cid
}

///|
pub fn prepare_client_submitted_intent(
  body : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientSubmittedIntent, ClientSubmittedIntentIssue] {
  if max_bytes < 1 ||
    max_bytes > 1048576 ||
    max_nodes < 1 ||
    max_nodes > 65536 ||
    max_depth < 1 ||
    max_depth > 64 {
    return Err(InvalidLimits)
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(body), {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(source) => source
    Err(error) =>
      match error.issue {
        InputLimit | NodeLimit | DepthLimit => return Err(Limit)
        _ => return Err(InvalidEnvelope)
      }
  }
  let value = @canonical.from_source(
    source,
    max_nodes,
    max_depth,
    max_bytes,
    data_keys=true,
  ) catch {
    @canonical.InputLimit => return Err(Limit)
    _ => return Err(InvalidEnvelope)
  }
  if @canonical.object_field_count(value) != Some(3) {
    return Err(InvalidEnvelope)
  }
  guard @canonical.object_field(value, "kind") is Some(@canonical.String(kind)) &&
    (kind == "program" || kind == "aql") &&
    @canonical.object_field(value, "input") is Some(input) &&
    @canonical.object_field_count(input) is Some(_) &&
    @canonical.object_field(value, "parameters") is Some(parameters) else {
    return Err(InvalidEnvelope)
  }
  if !(parameters is @canonical.Null) &&
    @canonical.object_field_count(parameters) is None {
    return Err(InvalidEnvelope)
  }
  let wire = @canonical.stringify_value(value, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Limit)
  }
  let writer = @encode.hashing_writer(
    max_bytes + 128,
    max_nodes + 4,
    max_depth + 1,
  ) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "intent")
    @canonical.emit_value(value, writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-submitted-intent/0.1")
    @encode.end_object(writer)
    Ok({ wire, cid: "sha256:" + @encode.finish_hash(writer), })
  } catch {
    _ => Err(Encoding)
  }
}

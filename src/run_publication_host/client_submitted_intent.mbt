///|
/// Original submitted content before checking. No execution identity, source
/// authorization or verified conclusion is manufactured by this admission.
struct ClientSubmittedIntent {
  wire : String
  // Exact byte count from the SAME canonical text emission. Journal
  // inventory must not allocate another complete UTF8 body just to count it.
  wire_bytes : Int
  cid : String
  stop_before_commit : Bool
  read_only : Bool
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
/// An admitted continuation restriction, not Account or resume authority.
pub fn client_submitted_intent_requests_commit_stop(
  value : ClientSubmittedIntent,
) -> Bool {
  value.stop_before_commit
}

///|
/// An original continuation restriction, never an execution or Account grant.
pub fn client_submitted_intent_requests_read_only(
  value : ClientSubmittedIntent,
) -> Bool {
  value.read_only
}

///|
/// Consult the complete inventory of this same checked computation. Neither
/// row cardinality, reachability nor a current policy decision removes an
/// Effect occurrence. The Host separately retains the original intent/pair.
pub fn client_submitted_intent_effect_compatible(
  intent : ClientSubmittedIntent,
  prepared : PreparedClientEffectComputation,
) -> Bool {
  !intent.read_only ||
  @syntax.effect_header_count(
    @checked.effect_program_static_headers(prepared.candidate),
  ) ==
  0
}

///|
pub fn prepare_client_submitted_intent(
  body : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientSubmittedIntent, ClientSubmittedIntentIssue] {
  prepare_client_submitted_intent_originals(
    body,
    max_bytes,
    max_nodes,
    max_depth,
    false,
    (bytes, limits) => @source.parse_json_bytes_preserving(bytes, limits),
  ).map(parts => parts.0)
}

///|
/// The same admitted envelope's immutable value and decoder view. This is
/// input DATA only; Program checking, current permission and Run admission
/// remain separate. No caller-supplied cursor or claimed identity is accepted.
pub fn prepare_client_submitted_input_parts(
  body : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  tree_limits : @decode.Limits,
) -> Result[
  (ClientSubmittedIntent, @canonical.CanonicalValue, @decode.Cursor),
  ClientSubmittedIntentIssue,
] {
  prepare_client_submitted_input_parts_with_reader(
    body,
    max_bytes,
    max_nodes,
    max_depth,
    tree_limits,
    (bytes, limits) => @source.parse_json_bytes_preserving(bytes, limits),
  )
}

///|
fn prepare_client_submitted_input_parts_with_reader(
  body : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  tree_limits : @decode.Limits,
  read : (Bytes, @source.ParseLimits) -> Result[
    @source.Node,
    @source.ParseError,
  ],
) -> Result[
  (ClientSubmittedIntent, @canonical.CanonicalValue, @decode.Cursor),
  ClientSubmittedIntentIssue,
] {
  let (intent, original, value) = match
    prepare_client_submitted_intent_originals(
      body, max_bytes, max_nodes, max_depth, true, read,
    ) {
    Ok(parts) => parts
    Err(issue) => return Err(issue)
  }
  // Decoder diagnostics previously referred to the canonical intent wire.
  // Reuse source coordinates only when those exact bytes were admitted;
  // differently spelled input keeps the original canonical-wire parse.
  let source = match original {
    Some(source) => source
    None =>
      match
        read(@utf8.encode(intent.wire), {
          max_input_bytes: max_bytes,
          max_nodes,
          max_depth,
        }) {
        Ok(source) => source
        Err(_) => return Err(Limit)
      }
  }
  let cursor = match @decode.admit(source, tree_limits) {
    Ok(cursor) => cursor
    Err(_) => return Err(InvalidEnvelope)
  }
  Ok((intent, value, cursor))
}

///|
// Preserve the existing envelope/identity admission and return only its own
// original parsed facts to the immediate synchronous preparation caller.
fn prepare_client_submitted_intent_originals(
  body : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  retain_source : Bool,
  read : (Bytes, @source.ParseLimits) -> Result[
    @source.Node,
    @source.ParseError,
  ],
) -> Result[
  (ClientSubmittedIntent, @source.Node?, @canonical.CanonicalValue),
  ClientSubmittedIntentIssue,
] {
  // The selected owner supplies finite policy bounds. Only representation
  // headroom for the hash envelope (+128 bytes,+4 nodes,+1 depth) is intrinsic.
  if !valid_client_submitted_intent_limits(max_bytes, max_nodes, max_depth) {
    return Err(InvalidLimits)
  }
  let source = match
    read(@utf8.encode(body), {
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
  let intent = match
    prepare_client_submitted_intent_value(
      value, max_bytes, max_nodes, max_depth,
    ) {
    Ok(intent) => intent
    Err(issue) => return Err(issue)
  }
  Ok(
    (
      intent,
      if retain_source && body == intent.wire {
        Some(source)
      } else {
        None
      },
      value,
    ),
  )
}

///|
// One envelope/identity definition for textual, restored and captured inputs.
// The caller has admitted the canonical value under the same limits.
fn prepare_client_submitted_intent_value(
  value : @canonical.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientSubmittedIntent, ClientSubmittedIntentIssue] {
  let stop_before_commit = match @canonical.object_field(value, "stopBefore") {
    None => false
    Some(@canonical.String("commit")) => true
    _ => return Err(InvalidEnvelope)
  }
  let read_only = match @canonical.object_field(value, "readOnly") {
    None => false
    Some(@canonical.Bool(true)) => true
    _ => return Err(InvalidEnvelope)
  }
  let expected_fields = 3 +
    (if stop_before_commit { 1 } else { 0 }) +
    (if read_only { 1 } else { 0 })
  if @canonical.object_field_count(value) != Some(expected_fields) {
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
  let (wire, bytes, _, _) = @canonical.stringify_value_with_usage(
    value, max_bytes, max_nodes, max_depth,
  ) catch {
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
    Ok({
      wire,
      wire_bytes: bytes,
      cid: "sha256:" + @encode.finish_hash(writer),
      stop_before_commit,
      read_only,
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// The SAME detached native input enters the existing envelope/identity law.
/// No whole-input serialization/parser, new authority or caller verdict is
/// used. The fixed owner must reserve the construction overlap before entry.
pub fn[T] prepare_captured_client_submitted_intent(
  input : T,
  reader : @source.JsonDataReader[T],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_key_units_out? : Ref[Int]? = None,
) -> Result[ClientSubmittedIntent, ClientSubmittedIntentIssue] {
  if !valid_client_submitted_intent_limits(max_bytes, max_nodes, max_depth) {
    return Err(InvalidLimits)
  }
  let value = match
    captured_client_submitted_intent_value(
      input,
      reader,
      max_bytes,
      max_nodes,
      max_depth,
      max_key_units_out~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Source/native admission frames have returned before either writer begins.
  prepare_client_submitted_intent_value(value, max_bytes, max_nodes, max_depth)
}

///|
fn[T] captured_client_submitted_intent_value(
  input : T,
  reader : @source.JsonDataReader[T],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_key_units_out? : Ref[Int]? = None,
) -> Result[@canonical.CanonicalValue, ClientSubmittedIntentIssue] {
  let parsed = match
    @source.admit_captured_json(
      input,
      reader,
      { max_input_bytes: max_bytes, max_nodes, max_depth, },
      max_key_units_out~,
    ) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.issue {
          InputLimit | NodeLimit | DepthLimit => Limit
          _ => InvalidEnvelope
        },
      )
  }
  Ok(
    @canonical.from_source(
      parsed.node,
      max_nodes,
      max_depth,
      max_bytes,
      data_keys=true,
    ),
  ) catch {
    @canonical.InputLimit => Err(Limit)
    _ => Err(InvalidEnvelope)
  }
}

///|
// One representation-headroom rule for every entrance to this identity law.
fn valid_client_submitted_intent_limits(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  max_bytes >= 1 &&
  max_bytes <= 2147483519 &&
  max_nodes >= 1 &&
  max_nodes <= 2147483643 &&
  max_depth >= 1 &&
  max_depth <= 2147483646
}

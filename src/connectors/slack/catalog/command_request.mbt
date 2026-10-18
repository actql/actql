///|
pub(all) enum SlackCommandKind {
  Post
  Reply
  React
  ArchiveChannel
} derive(Eq, Debug)

///|
/// Codec bounds, not an installation, Effect, transport or capacity admission.
pub(all) struct SlackCommandRequestLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_value_text_bytes : Int
}

///|
pub(all) enum SlackCommandRequestIssue {
  InvalidLimits
  BudgetExceeded
  InvalidTarget
  InvalidMarker
  InvalidInput
  InvalidField(String)
  TextWouldTruncate
} derive(Eq, Debug)

///|
/// A vendor encoding of this original checked input. The consuming Command
/// owner must supply its original target, item identity, approval, current
/// Account/Site use, durable claim and custody before any physical send.
pub struct SlackCommandRequest {
  priv kind : SlackCommandKind
  priv input : @admitted.CheckedValue
  priv channel : String
  priv marker : String?
  priv document : @encode.EncodedDocument
}

///|
fn command_expected_fields(kind : SlackCommandKind) -> Array[String] {
  match kind {
    Post => ["text"]
    Reply => ["text", "thread_ts"]
    React => ["name", "ts"]
    ArchiveChannel => []
  }
}

///|
fn command_bounded_text(text : String, bound : Int) -> Bool {
  !text.is_empty() && @scalar.admit_utf8_length(text, bound) is Ok(_)
}

///|
fn command_input_text(input : @admitted.CheckedValue, name : String) -> String? {
  guard input.value is @admitted.Object(fields) else { return None }
  for index in 0..<@admitted.element_count(fields) {
    let (field, value) = @admitted.element_at(fields, index).unwrap()
    if field == name {
      return match value {
        @admitted.Text(text) => Some(text)
        _ => None
      }
    }
  }
  None
}

///|
/// Never obtains a CheckedValue by re-admitting similarly shaped JSON. Enum,
/// extent and nullable requirements belong to the supplied original contract.
/// A marker is required for post/reply and forbidden on unmarked operations;
/// supplying its String does not prove an original Effect item or permission.
pub fn prepare_slack_command_request(
  kind : SlackCommandKind,
  input : @admitted.CheckedValue,
  channel : String,
  effect_item_id : String?,
  limits : SlackCommandRequestLimits,
) -> Result[SlackCommandRequest, SlackCommandRequestIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_value_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !command_bounded_text(channel, limits.max_value_text_bytes) {
    return Err(InvalidTarget)
  }
  match (kind, effect_item_id) {
    (Post | Reply, Some(marker)) =>
      if !command_bounded_text(marker, limits.max_value_text_bytes) {
        return Err(InvalidMarker)
      }
    (React | ArchiveChannel, None) => ()
    _ => return Err(InvalidMarker)
  }
  let expected = command_expected_fields(kind)
  guard !input.contract.nullable &&
    input.contract.shape is @contract.Object(declarations) &&
    @contract.field_count(declarations) == expected.length() &&
    input.value is @admitted.Object(values) &&
    @admitted.element_count(values) == expected.length() else {
    return Err(InvalidInput)
  }
  // The original checked field inventory is canonical and closed. Validate
  // every original child type before reading any corresponding value.
  for index in 0..<expected.length() {
    let field = @contract.field_at(declarations, index).unwrap()
    if field.name != expected[index] ||
      field.contract.nullable ||
      !(field.contract.shape is @contract.Text(_)) {
      return Err(InvalidField(field.name))
    }
  }
  guard @admitted.recheck_runtime_value_usage(input.value, input.contract, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_value_text_bytes,
    })
    is Some(_) else {
    return Err(BudgetExceeded)
  }
  for name in expected {
    guard command_input_text(input, name) is Some(text) else {
      return Err(InvalidField(name))
    }
    if name != "text" && text.is_empty() {
      return Err(InvalidField(name))
    }
    if name == "text" && @scalar.unicode_scalar_count(text).unwrap() > 40000 {
      // Slack truncates text beyond its write-request bound. Never silently
      // replace the approved text with a shorter message or implicit upload.
      return Err(TextWouldTruncate)
    }
  }
  try {
    let writer = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_object(writer)
    @encode.key(writer, "channel")
    @encode.string_value(writer, channel)
    match effect_item_id {
      Some(marker) => {
        @encode.key(writer, "metadata")
        @encode.begin_object(writer)
        @encode.key(writer, "event_payload")
        @encode.begin_object(writer)
        @encode.key(writer, "effect_item_id")
        @encode.string_value(writer, marker)
        @encode.end_object(writer)
        @encode.key(writer, "event_type")
        @encode.string_value(writer, "actql_effect")
        @encode.end_object(writer)
      }
      None => ()
    }
    for name in expected {
      @encode.key(writer, name)
      @encode.string_value(writer, command_input_text(input, name).unwrap())
    }
    @encode.end_object(writer)
    Ok({
      kind,
      input,
      channel,
      marker: effect_item_id,
      document: @encode.finish_document(writer),
    })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn slack_command_request_kind(
  request : SlackCommandRequest,
) -> SlackCommandKind {
  request.kind
}

///|
pub fn slack_command_request_path(request : SlackCommandRequest) -> String {
  match request.kind {
    Post | Reply => "/api/chat.postMessage"
    React => "/api/reactions.add"
    ArchiveChannel => "/api/conversations.archive"
  }
}

///|
pub fn slack_command_request_body(request : SlackCommandRequest) -> String {
  @encode.document_text(request.document)
}

///|
pub fn slack_command_request_channel(request : SlackCommandRequest) -> String {
  request.channel
}

///|
pub fn slack_command_request_marker(request : SlackCommandRequest) -> String? {
  request.marker
}

///|
pub fn slack_command_request_input_matches(
  request : SlackCommandRequest,
  input : @admitted.CheckedValue,
) -> Bool {
  physical_equal(request.input, input)
}

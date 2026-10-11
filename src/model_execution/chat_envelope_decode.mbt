///|
// Private physical codec child, not another execution or permission owner.
// The original HTTP bytes/EOF/status and Artifact custody remain independent.
priv enum ChatEnvelopePhase {
  ParseChat(@source.JsonParse)
  AdmitChat(@decode.Admission)
  ScanChat
  ChatReclaimed
}

///|
priv enum ChatEnvelopeRole {
  RootEnvelope
  ChoiceEnvelope
  MessageEnvelope
  UsageEnvelope
}

///|
priv struct ChatEnvelopeFrame {
  source : @decode.Cursor
  role : ChatEnvelopeRole
  mut next : Int
}

///|
// Preserve the entire admitted original, including unknown opaque metadata.
// No SDK-generated defaults or configured model name enter these facts.
priv struct ChatEnvelopeFacts {
  original : @decode.Cursor
  mut answer : String?
  mut provider_model : String?
  mut provider_request_id : String?
  mut input_tokens : Int64?
  mut output_tokens : Int64?
  mut finish_reason : String?
  mut choices_seen : Bool
  mut index_seen : Bool
  mut message_seen : Bool
  mut role_seen : Bool
  mut refused : Bool
  mut malformed : Bool
}

///|
priv struct ChatEnvelopeDecode {
  mut phase : ChatEnvelopePhase
  limits : @environment.ModelResponseProfileLimits
  mut remaining : Int
  mut facts : ChatEnvelopeFacts?
  frames : Array[ChatEnvelopeFrame]
}

///|
fn start_chat_envelope_decode(
  body : String,
  limits : @environment.ModelResponseProfileLimits,
) -> Result[ChatEnvelopeDecode, ModelExecutionIssue] {
  if limits.parse_work <= 0 {
    return Err(WorkLimit)
  }
  let parse = match
    @source.start_json_parse(
      body,
      {
        max_input_bytes: limits.response_bytes,
        max_nodes: limits.parse_nodes,
        max_depth: limits.parse_depth,
      },
      data_keys=true,
    ) {
    Ok(parse) => parse
    Err(_) => return Err(OutputValue)
  }
  Ok({
    phase: ParseChat(parse),
    limits,
    remaining: limits.parse_work,
    facts: None,
    frames: [],
  })
}

///|
fn cancel_chat_envelope_decode(cursor : ChatEnvelopeDecode) -> Unit {
  match cursor.phase {
    ParseChat(parse) => @source.cancel_json_parse(parse)
    AdmitChat(admission) => @decode.cancel_admission(admission)
    ScanChat | ChatReclaimed => ()
  }
  cursor.frames.clear()
  cursor.facts = None
  cursor.phase = ChatReclaimed
}

///|
fn chat_optional_text(source : @decode.Cursor) -> Result[String?, Unit] {
  if @decode.is_null(source) {
    return Ok(None)
  }
  match @decode.text(source) {
    Ok(text) if !text.is_empty() => Ok(Some(text))
    _ => Err(())
  }
}

///|
fn chat_optional_tokens(source : @decode.Cursor) -> Result[Int64?, Unit] {
  if @decode.is_null(source) {
    return Ok(None)
  }
  match @decode.safe_integer(source) {
    Ok(tokens) if tokens >= 0L => Ok(Some(tokens))
    _ => Err(())
  }
}

///|
// A fixed four-role codec: root, one choice, one message and optional usage.
// Unknown fields stay in the retained original; they are not discarded or
// treated as malformed required answers. One field is inspected per advance.
fn scan_chat_envelope_field(
  cursor : ChatEnvelopeDecode,
  facts : ChatEnvelopeFacts,
  role : ChatEnvelopeRole,
  name : String,
  value : @decode.Cursor,
) -> Unit {
  match role {
    RootEnvelope =>
      match name {
        "choices" => {
          facts.choices_seen = true
          if @decode.array_length(value) == Some(1) &&
            @decode.element_at(value, 0) is Some(choice) &&
            @decode.object_length(choice) is Some(_) {
            cursor.frames.push({
              source: choice,
              role: ChoiceEnvelope,
              next: 0,
            })
          } else {
            facts.malformed = true
          }
        }
        "object" =>
          if @decode.text(value) != Ok("chat.completion") {
            facts.malformed = true
          }
        "model" =>
          match chat_optional_text(value) {
            Ok(model) => facts.provider_model = model
            Err(_) => facts.malformed = true
          }
        "id" =>
          match chat_optional_text(value) {
            Ok(id) => facts.provider_request_id = id
            Err(_) => facts.malformed = true
          }
        "usage" =>
          if !@decode.is_null(value) {
            if @decode.object_length(value) is Some(_) {
              cursor.frames.push({
                source: value,
                role: UsageEnvelope,
                next: 0,
              })
            } else {
              facts.malformed = true
            }
          }
        _ => ()
      }
    ChoiceEnvelope =>
      match name {
        "index" => {
          facts.index_seen = true
          if @decode.safe_integer(value) != Ok(0L) {
            facts.malformed = true
          }
        }
        "finish_reason" =>
          match chat_optional_text(value) {
            Ok(reason) => facts.finish_reason = reason
            Err(_) => facts.malformed = true
          }
        "message" => {
          facts.message_seen = true
          if @decode.object_length(value) is Some(_) {
            cursor.frames.push({
              source: value,
              role: MessageEnvelope,
              next: 0,
            })
          } else {
            facts.malformed = true
          }
        }
        _ => ()
      }
    MessageEnvelope =>
      match name {
        "role" => {
          facts.role_seen = true
          if @decode.text(value) != Ok("assistant") {
            facts.malformed = true
          }
        }
        "content" =>
          match @decode.text(value) {
            Ok(answer) => facts.answer = Some(answer)
            _ => facts.malformed = true
          }
        "refusal" => if !@decode.is_null(value) { facts.refused = true }
        "tool_calls" | "annotations" =>
          if !@decode.is_null(value) && @decode.array_length(value) != Some(0) {
            facts.malformed = true
          }
        "audio" => if !@decode.is_null(value) { facts.malformed = true }
        _ => ()
      }
    UsageEnvelope =>
      match name {
        "prompt_tokens" =>
          match chat_optional_tokens(value) {
            Ok(tokens) => facts.input_tokens = tokens
            Err(_) => facts.malformed = true
          }
        "completion_tokens" =>
          match chat_optional_tokens(value) {
            Ok(tokens) => facts.output_tokens = tokens
            Err(_) => facts.malformed = true
          }
        _ => ()
      }
  }
}

///|
// This is endpoint shape only, never HTTP EOF, typed answer or success proof.
fn chat_envelope_complete(facts : ChatEnvelopeFacts) -> Bool {
  !facts.malformed &&
  !facts.refused &&
  facts.choices_seen &&
  facts.index_seen &&
  facts.message_seen &&
  facts.role_seen &&
  facts.finish_reason == Some("stop") &&
  facts.answer is Some(_)
}

///|
fn advance_chat_envelope_decode(
  cursor : ChatEnvelopeDecode,
) -> Result[ChatEnvelopeFacts?, ModelExecutionIssue] {
  if cursor.phase is ChatReclaimed {
    return Err(OutputIdentity)
  }
  if cursor.remaining <= 0 {
    cancel_chat_envelope_decode(cursor)
    return Err(WorkLimit)
  }
  cursor.remaining -= 1
  match cursor.phase {
    ParseChat(parse) =>
      match @source.advance_json_parse(parse, 1) {
        Ok(@source.JsonParseContinue(..)) => ()
        Ok(@source.JsonParseComplete(source, ..)) => {
          let admission = match
            @decode.start_admission(source.node, {
              max_nodes: cursor.limits.parse_nodes,
              max_depth: cursor.limits.parse_depth,
              max_string_bytes: cursor.limits.response_bytes,
              max_total_string_bytes: cursor.limits.response_bytes,
            }) {
            Ok(admission) => admission
            Err(_) => {
              cancel_chat_envelope_decode(cursor)
              return Err(OutputValue)
            }
          }
          cursor.phase = AdmitChat(admission)
        }
        _ => {
          cancel_chat_envelope_decode(cursor)
          return Err(OutputValue)
        }
      }
    AdmitChat(admission) =>
      match @decode.advance_admission(admission, 1) {
        Ok(@decode.AdmissionContinue(..)) => ()
        Ok(@decode.AdmissionComplete(root, ..)) => {
          if @decode.object_length(root) is None {
            cancel_chat_envelope_decode(cursor)
            return Err(OutputValue)
          }
          cursor.facts = Some({
            original: root,
            answer: None,
            provider_model: None,
            provider_request_id: None,
            input_tokens: None,
            output_tokens: None,
            finish_reason: None,
            choices_seen: false,
            index_seen: false,
            message_seen: false,
            role_seen: false,
            refused: false,
            malformed: false,
          })
          cursor.frames.push({ source: root, role: RootEnvelope, next: 0, })
          cursor.phase = ScanChat
        }
        _ => {
          cancel_chat_envelope_decode(cursor)
          return Err(OutputValue)
        }
      }
    ScanChat => {
      guard cursor.facts is Some(facts) else { return Err(OutputIdentity) }
      guard cursor.frames.last() is Some(frame) else {
        cursor.facts = None
        cursor.phase = ChatReclaimed
        return Ok(Some(facts))
      }
      match @decode.field_at(frame.source, frame.next) {
        Some((name, value)) => {
          frame.next += 1
          scan_chat_envelope_field(cursor, facts, frame.role, name, value)
        }
        None => cursor.frames.pop() |> ignore
      }
    }
    ChatReclaimed => return Err(OutputIdentity)
  }
  Ok(None)
}
